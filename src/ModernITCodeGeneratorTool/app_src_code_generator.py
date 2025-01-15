import boto3
import json
import os
from botocore.exceptions import ClientError
import logging
from datetime import datetime
import time
import random
from typing import Optional, Tuple, List

def setup_logging(script_name: str) -> tuple:
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    base_name = os.path.splitext(os.path.basename(script_name))[0]
    log_filename = f"{base_name}_{timestamp}.log"
    
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    
    file_handler = logging.FileHandler(log_filename)
    file_handler.setFormatter(formatter)
    
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    
    logger = logging.getLogger(__name__)
    logger.setLevel(logging.INFO)
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)
    
    return logger, log_filename

def upload_log_to_s3(bucket_name: str, log_filename: str) -> None:
    try:
        s3_client = boto3.client('s3')
        log_key = f"logs/{log_filename}"
        
        with open(log_filename, 'rb') as log_file:
            s3_client.upload_fileobj(log_file, bucket_name, log_key)
        
        logger.info(f"Log file uploaded to s3://{bucket_name}/{log_key}")
        os.remove(log_filename)
        logger.info(f"Local log file {log_filename} removed")
        
    except ClientError as e:
        logger.error(f"Error uploading log file to S3: {str(e)}")
        raise

class BedrockRetryException(Exception):
    pass

def exponential_backoff(attempt: int, max_delay: int = 32) -> float:
    delay = min(max_delay, (2 ** (attempt - 1))) + random.uniform(0, 0.1)
    return delay

def list_plsql_files(s3_client, bucket_name: str, source_prefix: str) -> List[str]:
    try:
        paginator = s3_client.get_paginator('list_objects_v2')
        all_files = set()

        for page in paginator.paginate(Bucket=bucket_name, Prefix=source_prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    if obj['Key'].endswith('.pks') or obj['Key'].endswith('.pkb'):
                        base_name = os.path.splitext(os.path.basename(obj['Key']))[0]
                        all_files.add(base_name)
        
        logger.info(f"Found {len(all_files)} unique PL/SQL file pairs to process")
        return list(all_files)
    except ClientError as e:
        logger.error(f"Error listing files from S3: {e.response['Error']}")
        raise

def read_file_from_s3(s3_client, bucket_name: str, file_path: str) -> str:
    try:
        response = s3_client.get_object(Bucket=bucket_name, Key=file_path)
        raw_content = response['Body'].read()
        
        encodings_to_try = ['utf-8', 'iso-8859-1', 'cp1252', 'latin1']
        file_content = None

        for encoding in encodings_to_try:
            try:
                file_content = raw_content.decode(encoding)
                logger.info(f"Successfully decoded {file_path} using {encoding} encoding")
                break
            except UnicodeDecodeError:
                continue

        if file_content is None:
            file_content = raw_content.decode('utf-8', errors='ignore')
        return file_content
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchKey':
            logger.warning(f"File not found: {file_path}, returning empty string.")
        else:
            logger.error(f"Error reading file {file_path}: {e}")
        return ""

def write_file_to_s3(s3_client, bucket_name: str, key: str, content: str) -> bool:
    try:
        s3_client.put_object(Bucket=bucket_name, Key=key, Body=content.encode('utf-8'))
        logger.info(f"Successfully wrote file: {key}")
        return True
    except ClientError as e:
        logger.error(f"Error writing file {key}: {e}")
        return False

def call_bedrock_with_retry(bedrock_client, body: str, max_retries: int = 10) -> Optional[dict]:
    retryable_errors = [
        'ThrottlingException',
        'InternalServerError',
        'ServiceUnavailable',
        'ModelStreamLimitExceeded',
        'ValidationException',
        'ModelTimeoutException'
    ]
    
    for attempt in range(1, max_retries + 1):
        try:
            response = bedrock_client.invoke_model(
                modelId='anthropic.claude-3-5-sonnet-20240620-v1:0',
                body=body
            )
            
            status_code = response['ResponseMetadata']['HTTPStatusCode']
            logger.info(f"Bedrock API call successful on attempt {attempt}. Status Code: {status_code}")
            
            return response

        except ClientError as e:
            error_code = e.response['Error'].get('Code', 'Unknown')
            error_message = e.response['Error'].get('Message', 'No message available')
            status_code = e.response['ResponseMetadata'].get('HTTPStatusCode', 'Unknown')
            
            logger.warning(f"""
                Bedrock API Error (Attempt {attempt}/{max_retries}):
                Status Code: {status_code}
                Error Code: {error_code}
                Error Message: {error_message}
            """)
            
            if error_code in retryable_errors and attempt < max_retries:
                if "Too many tokens" in error_message:
                    raise BedrockRetryException("Too many tokens")
                
                delay = exponential_backoff(attempt)
                logger.info(f"Retrying in {delay:.2f} seconds...")
                time.sleep(delay)
                continue
            
            if attempt == max_retries:
                raise BedrockRetryException(f"Failed after {max_retries} attempts. Last error: {error_message}")
            raise e

def split_code_into_chunks(pks_code: str, pkb_code: str, chunk_size: int = 6000) -> List[Tuple[str, str]]:
    def split_plsql(code: str, chunk_size: int) -> List[str]:
        if not code:
            return [""]
        
        chunks = []
        current_chunk = ""
        
        delimiters = [
            "PROCEDURE", "FUNCTION", "CREATE OR REPLACE",
            "procedure", "function", "create or replace"
        ]
        
        lines = code.split('\n')
        for line in lines:
            if any(delimiter in line.upper() for delimiter in delimiters) and len(current_chunk) > chunk_size:
                if current_chunk:
                    chunks.append(current_chunk)
                current_chunk = ""
            current_chunk += line + '\n'
            
        if current_chunk:
            chunks.append(current_chunk)
            
        return chunks

    pks_chunks = split_plsql(pks_code, chunk_size)
    pkb_chunks = split_plsql(pkb_code, chunk_size)
    
    max_chunks = max(len(pks_chunks), len(pkb_chunks))
    paired_chunks = []
    
    for i in range(max_chunks):
        pks_chunk = pks_chunks[i] if i < len(pks_chunks) else ""
        pkb_chunk = pkb_chunks[i] if i < len(pkb_chunks) else ""
        paired_chunks.append((pks_chunk, pkb_chunk))
    
    logger.info(f"Split code into {len(paired_chunks)} chunks")
    return paired_chunks

def convert_plsql_chunk_to_python(bedrock_client, chunk_number: int, total_chunks: int, 
                                pks_chunk: str, pkb_chunk: str) -> Optional[str]:
    max_retries = 10
    
    for attempt in range(1, max_retries + 1):
        try:
            prompt = f"""You are an expert in both PL/SQL and Python, specifically focusing on chess engine development. 
            This is chunk {chunk_number} of {total_chunks} total chunks.
            Please convert the following chunk of PL/SQL chess engine code to equivalent Python code. 
            
            Specification (.pks) chunk:
            {pks_chunk}

            Body (.pkb) chunk:
            {pkb_chunk}

            Please convert this chunk to Python code that:
            1. Maintains the same chess logic and functionality
            2. Uses Pythonic patterns and best practices
            3. Can be integrated with other chunks of the same codebase
            4. Includes appropriate Python docstrings and type hints
            5. Maintains the same logic and functionality
            
            Important: This is chunk {chunk_number} of {total_chunks}, so ensure the code can be properly combined with other chunks.
            Please provide only the converted Python code without any explanations."""

            body = json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 100000,
                "messages": [
                    {
                        "role": "user",
                        "content": prompt
                    }
                ]
            })

            response = call_bedrock_with_retry(bedrock_client, body)
            response_body = json.loads(response['body'].read())
            logger.info(f"Successfully converted chunk {chunk_number}/{total_chunks}")
            return response_body['content'][0]['text']
            
        except BedrockRetryException as e:
            if "Too many tokens" in str(e):
                if attempt < max_retries:
                    delay = exponential_backoff(attempt)
                    logger.warning(f"Too many tokens for chunk {chunk_number}, attempt {attempt}/{max_retries}. Retrying in {delay:.2f} seconds...")
                    time.sleep(delay)
                    continue
                else:
                    logger.error(f"Failed to convert chunk {chunk_number} after {max_retries} attempts due to token limit")
                    raise
            else:
                raise
        except Exception as e:
            logger.error(f"Error converting chunk {chunk_number} on attempt {attempt}: {str(e)}")
            if attempt < max_retries:
                delay = exponential_backoff(attempt)
                logger.info(f"Retrying chunk {chunk_number} in {delay:.2f} seconds...")
                time.sleep(delay)
                continue
            raise

def convert_plsql_to_python(bedrock_client, pks_code: str, pkb_code: str) -> Optional[str]:
    try:
        logger.info("Attempting to convert entire code at once...")
        max_retries = 10
        
        prompt = f"""You are an expert in both PL/SQL and Python, specifically focusing on chess engine development. 
        Please convert the following PL/SQL chess engine code to equivalent Python code. 
        The code is split into specification (.pks) and body (.pkb) files.

        Specification (.pks):
        {pks_code}

        Body (.pkb):
        {pkb_code}

        Please convert this to a well-structured Python implementation that:
        1. Maintains the same chess logic and functionality
        2. Uses Pythonic patterns and best practices
        3. Implements proper Python class structure
        4. Includes appropriate Python docstrings and type hints
        5. Uses modern Python chess board representation
        6. Maintains the same move generation and evaluation logic
        7. Implements the same game rules and move validation

        Please provide only the converted Python code without any explanations."""

        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 200000,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        })

        # Try full conversion with retries
        for attempt in range(1, max_retries + 1):
            try:
                response = call_bedrock_with_retry(bedrock_client, body)
                response_body = json.loads(response['body'].read())
                logger.info(f"Full code conversion successful on attempt {attempt}")
                return response_body['content'][0]['text']
                
            except BedrockRetryException as e:
                if "Too many tokens" in str(e):
                    if attempt < max_retries:
                        delay = exponential_backoff(attempt)
                        logger.warning(f"Too many tokens for full conversion, attempt {attempt}/{max_retries}. Retrying in {delay:.2f} seconds...")
                        time.sleep(delay)
                        continue
                    else:
                        logger.warning(f"Full conversion failed after {max_retries} attempts. Switching to chunk processing...")
                        break
                else:
                    raise
                    
        # If we reach here, all full conversion attempts failed, switch to chunks
        logger.info("Starting chunk processing...")
        chunks = split_code_into_chunks(pks_code, pkb_code)
        total_chunks = len(chunks)
        logger.info(f"Processing code in {total_chunks} chunks")
        
        converted_chunks = []
        for i, (pks_chunk, pkb_chunk) in enumerate(chunks, 1):
            try:
                logger.info(f"Processing chunk {i}/{total_chunks}")
                converted_chunk = convert_plsql_chunk_to_python(
                    bedrock_client, i, total_chunks, pks_chunk, pkb_chunk
                )
                converted_chunks.append(converted_chunk)
                logger.info(f"Successfully processed chunk {i}/{total_chunks}")
            except Exception as chunk_error:
                logger.error(f"Failed to process chunk {i} after all retries: {str(chunk_error)}")
                raise

        combined_code = "\n\n".join(converted_chunks)
        
        logger.info("Performing final pass to ensure code consistency...")
        final_prompt = f"""You are an expert Python developer. 
        The following Python code was converted from PL/SQL in chunks. 
        Please review and ensure all the code is properly integrated, 
        remove any duplicates, and ensure consistent naming and structure.
        Return only the final, cleaned-up Python code:

        {combined_code}"""
        
        final_body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 100000,
            "messages": [
                {
                    "role": "user",
                    "content": final_prompt
                }
            ]
        })
        
        final_response = call_bedrock_with_retry(bedrock_client, final_body)
        final_response_body = json.loads(final_response['body'].read())
        logger.info("Chunk combination and final cleanup successful")
        return final_response_body['content'][0]['text']
    
    except Exception as e:
        logger.error(f"Error in conversion: {str(e)}")
        raise

def process_single_file(s3_client, bedrock_client, bucket_name: str, base_name: str, 
                       source_prefix: str, output_prefix: str) -> None:
    try:
        pks_path = f"{source_prefix}/{base_name}.pks"
        pkb_path = f"{source_prefix}/{base_name}.pkb"
        
        logger.info(f"Processing files: {pks_path} and {pkb_path}")
        
        pks_code = read_file_from_s3(s3_client, bucket_name, pks_path)
        pkb_code = read_file_from_s3(s3_client, bucket_name, pkb_path)
        
        python_code = convert_plsql_to_python(bedrock_client, pks_code, pkb_code)
        
        if python_code:
            output_key = f"{output_prefix}/{base_name}.py"
            if write_file_to_s3(s3_client, bucket_name, output_key, python_code):
                logger.info(f"Successfully converted and saved: {output_key}")
            else:
                logger.error(f"Failed to save converted code for {base_name}")
                raise Exception("Failed to save converted code")
        else:
            logger.error(f"Failed to convert code for {base_name}")
            raise Exception("Failed to convert code")
            
    except Exception as e:
        logger.error(f"Error processing file {base_name}: {str(e)}")
        raise


def main():
    try:
        BUCKET_NAME = 's3-genai-coffee-and-innovate'
        SOURCE_PREFIX = 'source/PL-SQL-Chess-master/src'
        OUTPUT_PREFIX = 'target'
        
        s3_client = boto3.client('s3')
        bedrock_client = boto3.client('bedrock-runtime')
        
        plsql_files = list_plsql_files(s3_client, BUCKET_NAME, SOURCE_PREFIX)
        total_files = len(plsql_files)
        
        logger.info(f"Starting batch conversion process for {total_files} files")
        
        for index, base_name in enumerate(plsql_files, 1):
            try:
                logger.info(f"Processing file {index}/{total_files}: {base_name}")
                process_single_file(s3_client, bedrock_client, BUCKET_NAME, base_name, 
                                 SOURCE_PREFIX, OUTPUT_PREFIX)
                logger.info(f"Completed processing file {index}/{total_files}")
            except Exception as e:
                logger.error(f"Failed to process file {base_name}: {str(e)}")
                logger.info("Continuing with next file...")
                continue
        
        logger.info("Batch conversion process completed")
        
    except Exception as e:
        logger.error(f"Error in batch conversion process: {str(e)}")
        raise
    finally:
        upload_log_to_s3(BUCKET_NAME, log_filename)

if __name__ == "__main__":
    script_name = os.path.abspath(__file__)
    logger, log_filename = setup_logging(script_name)
    
    try:
        main()
    except Exception as e:
        logger.error("Process failed with error:", exc_info=True)
        upload_log_to_s3(BUCKET_NAME, log_filename)
        exit(1)