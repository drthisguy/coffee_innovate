import boto3
import json
import time
from botocore.exceptions import ClientError
import logging
from typing import Optional, List
import random
import os
from datetime import datetime

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
    except Exception as e:
        logger.error(f"Unexpected error uploading log file: {str(e)}")
        raise

class BedrockRetryException(Exception):
    pass

def get_base_filename(file_path: str) -> str:
    filename = os.path.basename(file_path)
    return os.path.splitext(filename)[0]

def generate_requirements_key(source_key: str, epic_folder: str) -> str:
    base_name = get_base_filename(source_key)
    return f"{epic_folder}/{base_name}_requirements.md"

def exponential_backoff(attempt: int, max_delay: int = 32) -> float:
    delay = min(max_delay, (2 ** (attempt - 1))) + random.uniform(0, 0.1)
    return delay

def list_python_files(bucket_name: str, prefix: str) -> List[str]:
    try:
        s3_client = boto3.client('s3')
        paginator = s3_client.get_paginator('list_objects_v2')
        python_files = []

        for page in paginator.paginate(Bucket=bucket_name, Prefix=prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    if obj['Key'].endswith('.py'):
                        python_files.append(obj['Key'])
        
        logger.info(f"Found {len(python_files)} Python files to process")
        return python_files
    except ClientError as e:
        logger.error(f"Error listing files from S3: {e.response['Error']}")
        raise

def read_file_from_s3(bucket_name: str, file_key: str) -> str:
    try:
        s3_client = boto3.client('s3')
        response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
        logger.info(f"Successfully read file from S3. Status: {response['ResponseMetadata']['HTTPStatusCode']}")
        file_content = response['Body'].read().decode('utf-8')
        return file_content
    except ClientError as e:
        logger.error(f"Error reading file from S3: {e.response['Error']}")
        raise

def write_to_s3(bucket_name: str, file_key: str, content: str) -> None:
    try:
        s3_client = boto3.client('s3')
        response = s3_client.put_object(
            Bucket=bucket_name,
            Key=file_key,
            Body=content.encode('utf-8')
        )
        logger.info(f"Successfully wrote to S3. Status: {response['ResponseMetadata']['HTTPStatusCode']}")
    except ClientError as e:
        logger.error(f"Error writing to S3: {e.response['Error']}")
        raise

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
            logger.info(f"Response Headers: {json.dumps(response['ResponseMetadata'], indent=2)}")
            
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
                delay = exponential_backoff(attempt)
                logger.info(f"Retrying in {delay:.2f} seconds...")
                time.sleep(delay)
                continue
            
            if attempt == max_retries:
                raise BedrockRetryException(f"Failed after {max_retries} attempts. Last error: {error_message}")
            raise e

def generate_requirements(code_content: str) -> str:
    try:
        bedrock_client = boto3.client('bedrock-runtime')
        
        prompt = f"""Analyze this Python code and generate comprehensive agile requirements documentation in Markdown format. 
        Include:
        
        1. Epic Overview
           - Epic title
           - Epic description
           - Business value
           - Success metrics
        
        2. Features
           - List of major features
           - Description for each feature
           - Technical considerations
           - Dependencies
        
        3. User Stories
           For each feature, include user stories with:
           - Story title
           - As a [role], I want [goal], so that [benefit]
           - Story points estimation
           - Priority (Must Have/Should Have/Could Have)
           - Acceptance Criteria (minimum 3 per story)
        
        Here's the code to analyze:

        {code_content}"""

        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        })

        response = call_bedrock_with_retry(bedrock_client, body)
        response_body = json.loads(response['body'].read())
        return response_body['content'][0]['text']

    except BedrockRetryException as e:
        logger.error(f"All retry attempts failed: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error in generate_requirements: {str(e)}")
        raise

def process_single_file(bucket_name: str, source_key: str, epic_folder: str) -> None:
    try:
        logger.info(f"Processing file: {source_key}")
        code_content = read_file_from_s3(bucket_name, source_key)
        
        logger.info("Generating requirements documentation...")
        requirements = generate_requirements(code_content)
        requirements_key = generate_requirements_key(source_key, epic_folder)
        write_to_s3(bucket_name, requirements_key, requirements)
        
        logger.info(f"Requirements generated successfully for {source_key}")
        
    except Exception as e:
        logger.error(f"Error processing file {source_key}: {str(e)}")
        raise

def main(bucket_name: str, source_prefix: str, epic_folder: str) -> None:
    try:
        logger.info(f"Starting batch requirements generation process for {source_prefix}")
        
        python_files = list_python_files(bucket_name, source_prefix)
        total_files = len(python_files)
        
        for index, file_key in enumerate(python_files, 1):
            try:
                logger.info(f"Processing file {index}/{total_files}: {file_key}")
                process_single_file(bucket_name, file_key, epic_folder)
                logger.info(f"Completed processing file {index}/{total_files}")
            except Exception as e:
                logger.error(f"Failed to process file {file_key}: {str(e)}")
                logger.info("Continuing with next file...")
                continue
        
        logger.info("Batch requirements generation process completed")
        
    except Exception as e:
        logger.error(f"Error in batch requirements process: {str(e)}")
        raise
    finally:
        upload_log_to_s3(bucket_name, log_filename)

if __name__ == "__main__":
    script_name = os.path.abspath(__file__)
    logger, log_filename = setup_logging(script_name)
    
    BUCKET_NAME = "s3-genai-coffee-and-innovate"
    SOURCE_PREFIX = "target/src"
    EPIC_FOLDER = "target/epics"
    
    try:
        main(BUCKET_NAME, SOURCE_PREFIX, EPIC_FOLDER)
    except Exception as e:
        logger.error("Process failed with error:", exc_info=True)
        upload_log_to_s3(BUCKET_NAME, log_filename)
        exit(1)
