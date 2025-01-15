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
        log_key = f"target/logs/{log_filename}"
        
        with open(log_filename, 'rb') as log_file:
            s3_client.upload_fileobj(log_file, bucket_name, log_key)
        
        logger.info(f"Log file uploaded to s3://{bucket_name}/{log_key}")
        os.remove(log_filename)
        logger.info(f"Local log file {log_filename} removed")
    except Exception as e:
        logger.error(f"Error uploading log file to S3: {str(e)}")
        raise

def is_plsql_file(file_key: str) -> bool:
    """Check if the file is a PL/SQL file and not in ignore list."""
    # Files to ignore
    ignore_files = ['pl_pig_chess_data.pks']
    
    # Check if file should be ignored
    if any(ignore_file in file_key for ignore_file in ignore_files):
        logger.info(f"Skipping ignored file: {file_key}")
        return False
    
    valid_extensions = ['.sql', '.pls', '.plsql', '.pck', '.pkb', '.pks']
    _, ext = os.path.splitext(file_key.lower())
    return ext in valid_extensions

def is_readme_file(file_key: str) -> bool:
    """Check if the file is a README file."""
    base_name = os.path.basename(file_key).lower()
    return base_name in ['readme.txt', 'readme.md']

def list_files_by_type(bucket_name: str, prefix: str) -> tuple[List[str], List[str]]:
    try:
        s3_client = boto3.client('s3')
        paginator = s3_client.get_paginator('list_objects_v2')
        plsql_files = []
        readme_files = []

        for page in paginator.paginate(Bucket=bucket_name, Prefix=prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    key = obj['Key']
                    if is_plsql_file(key):
                        plsql_files.append(key)
                    elif is_readme_file(key):
                        readme_files.append(key)
        
        logger.info(f"Found {len(plsql_files)} PL/SQL files and {len(readme_files)} README files in {prefix}")
        return plsql_files, readme_files
    except ClientError as e:
        logger.error(f"Error listing files from S3: {e.response['Error']}")
        raise

def generate_output_key(source_key: str, output_type: str) -> str:
    base_name = os.path.splitext(os.path.basename(source_key))[0]
    return f"target/knowledge_base/{output_type}/{base_name}.md"

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
            logger.info(f"Bedrock API call successful on attempt {attempt}")
            return response
            
        except ClientError as e:
            error_code = e.response['Error'].get('Code', 'Unknown')
            error_message = e.response['Error'].get('Message', 'No message available')
            request_id = e.response['ResponseMetadata'].get('RequestId', 'No RequestId')
            status_code = e.response['ResponseMetadata'].get('HTTPStatusCode', 'No StatusCode')
            
            error_details = {
                'Attempt': attempt,
                'Error Code': error_code,
                'Error Message': error_message,
                'Request ID': request_id,
                'Status Code': status_code
            }
            
            logger.error(f"Bedrock API Error Details:\n{json.dumps(error_details, indent=2)}")
            
            if error_code in retryable_errors and attempt < max_retries:
                delay = min(32, (2 ** (attempt - 1))) + random.uniform(0, 0.1)
                logger.info(f"Retrying in {delay:.2f} seconds... (Attempt {attempt}/{max_retries})")
                time.sleep(delay)
                continue
            
            if attempt == max_retries:
                logger.error(f"Final attempt failed. Giving up after {max_retries} attempts.")
                raise Exception(f"Failed after {max_retries} attempts. Last error: {error_message}")
            raise e

def read_file_content(s3_client, bucket_name: str, file_key: str) -> str:
    """
    Read file content with multiple encoding attempts and cleanup
    """
    try:
        response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
        content_bytes = response['Body'].read()
        
        # Try different encodings
        encodings_to_try = ['utf-8', 'latin1', 'cp1252', 'iso-8859-1']
        
        for encoding in encodings_to_try:
            try:
                logger.info(f"Attempting to decode {file_key} with {encoding} encoding")
                content = content_bytes.decode(encoding, errors='replace')
                # Replace any questionable characters with spaces
                content = ''.join(char if ord(char) < 128 else ' ' for char in content)
                # Remove any null characters
                content = content.replace('\x00', '')
                # Replace multiple spaces with single space
                content = ' '.join(content.split())
                logger.info(f"Successfully decoded {file_key} with {encoding} encoding")
                return content
            except UnicodeDecodeError as e:
                logger.warning(f"Failed to decode {file_key} with {encoding} encoding: {str(e)}")
                continue
        
        # If all encodings fail, use 'replace' with utf-8 as last resort
        logger.warning(f"All standard encodings failed for {file_key}, using utf-8 with replacement")
        content = content_bytes.decode('utf-8', errors='replace')
        content = ''.join(char if ord(char) < 128 else ' ' for char in content)
        content = content.replace('\x00', '')
        content = ' '.join(content.split())
        return content
        
    except Exception as e:
        logger.error(f"Error reading file {file_key}: {str(e)}")
        raise

def process_plsql_file(bucket_name: str, file_key: str) -> None:
    try:
        s3_client = boto3.client('s3')
        bedrock_client = boto3.client('bedrock-runtime')
        
        # Read the source file with enhanced encoding handling
        logger.info(f"Reading file {file_key} with enhanced encoding handling")
        code_content = read_file_content(s3_client, bucket_name, file_key)
        
        # Define prompts for PL/SQL analysis
        prompts = {
            "documentation": """Generate comprehensive documentation for this PL/SQL code:
            1. Overview and purpose
            2. Detailed procedure/function descriptions
            3. Parameters and return values
            4. Dependencies and prerequisites
            5. Usage examples
            6. Best practices and considerations
            
            Code to analyze: {content}""",
            
            "domain_knowledge": """Analyze this PL/SQL code and extract domain-specific knowledge:
            1. Business rules and logic implemented
            2. Data model insights
            3. Key business processes
            4. Industry-specific patterns
            5. Technical architecture considerations
            
            Code to analyze: {content}""",
            
            "sme_conversation": """Create a Q&A style knowledge base from an SME perspective:
            1. Common questions about this code
            2. Troubleshooting scenarios
            3. Implementation considerations
            4. Performance optimization tips
            5. Maintenance and support guidance
            
            Code to analyze: {content}"""
        }
        
        # Process each type individually
        for analysis_type, prompt_template in prompts.items():
            try:
                logger.info(f"Generating {analysis_type} for {file_key}")
                
                body = json.dumps({
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 1000000,
                    "messages": [{"role": "user", "content": prompt_template.format(content=code_content)}]
                })
                
                response = call_bedrock_with_retry(bedrock_client, body)
                response_body = json.loads(response['body'].read())
                content = response_body['content'][0]['text']
                
                output_key = generate_output_key(file_key, analysis_type)
                s3_client.put_object(
                    Bucket=bucket_name,
                    Key=output_key,
                    Body=content.encode('utf-8')
                )
                logger.info(f"Successfully generated {analysis_type} at {output_key}")
                time.sleep(1)  # Add small delay between calls
                
            except Exception as e:
                logger.error(f"Error generating {analysis_type} for {file_key}: {str(e)}")
                continue

    except Exception as e:
        logger.error(f"Error processing PL/SQL file {file_key}: {str(e)}")
        raise

def process_readme_file(bucket_name: str, file_key: str) -> None:
    try:
        s3_client = boto3.client('s3')
        bedrock_client = boto3.client('bedrock-runtime')
        
        # Read the README file
        logger.info(f"Reading README file {file_key}")
        readme_content = read_file_content(s3_client, bucket_name, file_key)
        
        # Define prompts for README analysis with single content reference
        prompts = {
            "documentation": """Generate comprehensive documentation for this project:
            1. Project overview and objectives
            2. Key features and components
            3. System architecture and design
            4. Setup and configuration steps
            5. Usage guidelines
            6. Integration points and dependencies
            
            README content: {content}""",
            
            "domain_knowledge": """Extract domain-specific knowledge from this project:
            1. Business context and requirements
            2. Domain terminology and concepts
            3. Core business processes
            4. System boundaries and constraints
            5. Integration patterns and workflows
            
            README content: {content}""",
            
            "sme_conversation": """Create a Q&A knowledge base for this project:
            1. Frequently asked questions
            2. Common implementation challenges
            3. Best practices and recommendations
            4. Troubleshooting guide
            5. Maintenance and support guidelines
            
            README content: {content}"""
        }
        
        # Process each type individually
        for analysis_type, prompt_template in prompts.items():
            try:
                logger.info(f"Generating {analysis_type} for {file_key}")
                
                body = json.dumps({
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 1000000,
                    "messages": [{"role": "user", "content": prompt_template.format(content=readme_content)}]
                })
                
                response = call_bedrock_with_retry(bedrock_client, body)
                response_body = json.loads(response['body'].read())
                content = response_body['content'][0]['text']
                
                output_key = generate_output_key(file_key, f"readme_{analysis_type}")
                s3_client.put_object(
                    Bucket=bucket_name,
                    Key=output_key,
                    Body=content.encode('utf-8')
                )
                logger.info(f"Successfully generated {analysis_type} at {output_key}")
                time.sleep(1)  # Add small delay between calls
                
            except Exception as e:
                logger.error(f"Error generating {analysis_type} for {file_key}: {str(e)}")
                continue

    except Exception as e:
        logger.error(f"Error processing README file {file_key}: {str(e)}")
        raise

def main(bucket_name: str, source_prefix: str) -> None:
    try:
        logger.info(f"Starting knowledge base generation for files in {source_prefix}")
        
        # Get PL/SQL and README files separately
        plsql_files, readme_files = list_files_by_type(bucket_name, source_prefix)
        
        # Process PL/SQL files
        logger.info("Processing PL/SQL files...")
        for index, file_key in enumerate(plsql_files, 1):
            try:
                logger.info(f"Processing PL/SQL file {index}/{len(plsql_files)}: {file_key}")
                process_plsql_file(bucket_name, file_key)
                logger.info(f"Completed processing PL/SQL file {index}/{len(plsql_files)}")
            except Exception as e:
                logger.error(f"Failed to process PL/SQL file {file_key}: {str(e)}")
                continue
        
        # Process README files
        logger.info("Processing README files...")
        for index, file_key in enumerate(readme_files, 1):
            try:
                logger.info(f"Processing README file {index}/{len(readme_files)}: {file_key}")
                process_readme_file(bucket_name, file_key)
                logger.info(f"Completed processing README file {index}/{len(readme_files)}")
            except Exception as e:
                logger.error(f"Failed to process README file {file_key}: {str(e)}")
                continue
        
        logger.info("Knowledge base generation completed")
        
    except Exception as e:
        logger.error(f"Error in knowledge base generation process: {str(e)}")
        raise
    finally:
        upload_log_to_s3(bucket_name, log_filename)

if __name__ == "__main__":
    script_name = os.path.abspath(__file__)
    logger, log_filename = setup_logging(script_name)

    BUCKET_NAME = "s3-genai-coffee-and-innovate"
    SOURCE_PREFIX = "source/PL-SQL-Chess-master"
    
    try:
        main(BUCKET_NAME, SOURCE_PREFIX)
    except Exception as e:
        logger.error("Process failed with error:", exc_info=True)
        upload_log_to_s3(BUCKET_NAME, log_filename)
        exit(1)