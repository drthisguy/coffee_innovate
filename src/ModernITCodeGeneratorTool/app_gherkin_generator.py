import boto3
import json
import time
from botocore.exceptions import ClientError
import logging
from typing import Optional, List, Tuple
import random
import os
from datetime import datetime
import re

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

def list_test_files(bucket_name: str, test_folder: str) -> List[Tuple[str, str]]:
    """Returns list of tuples containing (unit_test_file, functional_test_file)"""
    try:
        s3_client = boto3.client('s3')
        paginator = s3_client.get_paginator('list_objects_v2')
        
        # Get all Python files
        all_files = []
        for page in paginator.paginate(Bucket=bucket_name, Prefix=test_folder):
            if 'Contents' in page:
                for obj in page['Contents']:
                    if obj['Key'].endswith('.py'):
                        all_files.append(obj['Key'])
        
        logger.info(f"Found {len(all_files)} Python files")
        for file in all_files:
            logger.info(f"Found file: {file}")
        
        # Separate unit and functional tests
        unit_tests = [f for f in all_files if f.endswith('.py') and not f.endswith('_functional.py')]
        functional_tests = [f for f in all_files if f.endswith('_functional.py')]
        
        logger.info(f"Found {len(unit_tests)} unit tests and {len(functional_tests)} functional tests")
        
        # Match pairs
        test_pairs = []
        for unit_test in unit_tests:
            base_name = unit_test.replace('.py', '')
            functional_test = f"{base_name}_functional.py"
            if functional_test in functional_tests:
                test_pairs.append((unit_test, functional_test))
                logger.info(f"Matched pair: {unit_test} - {functional_test}")
        
        logger.info(f"Successfully matched {len(test_pairs)} test pairs")
        return test_pairs
    
    except Exception as e:
        logger.error(f"Error in list_test_files: {str(e)}")
        raise

def read_file_from_s3(bucket_name: str, file_key: str) -> str:
    try:
        s3_client = boto3.client('s3')
        response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
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
        logger.info(f"Successfully wrote to S3: {file_key}")
    except ClientError as e:
        logger.error(f"Error writing to S3: {e.response['Error']}")
        raise

def extract_test_info(test_content: str) -> List[dict]:
    """Extract test cases and their docstrings/comments"""
    test_cases = []
    
    # Pattern to match test methods and their docstrings
    pattern = re.compile(r'def\s+(test_[^(]+)\([^)]*\):\s*(?:"""([^"]*)""")?', re.DOTALL)
    matches = pattern.finditer(test_content)
    
    for match in matches:
        test_name = match.group(1)
        description = match.group(2).strip() if match.group(2) else test_name.replace('test_', '').replace('_', ' ')
        test_cases.append({
            'name': test_name,
            'description': description
        })
        logger.info(f"Extracted test case: {test_name}")
    
    return test_cases

def generate_gherkin_feature(unit_tests: List[dict], functional_tests: List[dict], feature_name: str) -> str:
    """Generate Gherkin feature file content"""
    feature_name = feature_name.replace('test_', '').replace('_', ' ').title()
    
    gherkin_content = [
        f"Feature: {feature_name}",
        "  As a system user",
        "  I want to ensure all functionalities work as expected",
        "  So that the system remains reliable and maintainable\n"
    ]
    
    # Add unit test scenarios
    if unit_tests:
        gherkin_content.append("  # Unit Test Scenarios")
        for test in unit_tests:
            scenario_name = test['description'].capitalize()
            gherkin_content.extend([
                f"  Scenario: {scenario_name}",
                "    Given the system is properly configured",
                f"    When executing unit test '{test['name']}'",
                "    Then the test should pass successfully\n"
            ])
    
    # Add functional test scenarios
    if functional_tests:
        gherkin_content.append("  # Functional Test Scenarios")
        for test in functional_tests:
            scenario_name = test['description'].capitalize()
            gherkin_content.extend([
                f"  Scenario: {scenario_name}",
                "    Given the system is in a production-like environment",
                f"    When performing functional test '{test['name']}'",
                "    Then the system should behave as expected",
                "    And all acceptance criteria should be met\n"
            ])
    
    return "\n".join(gherkin_content)

def get_gherkin_filename(test_file_path: str) -> str:
    """Generate Gherkin feature file name from test file path"""
    base_name = os.path.basename(test_file_path)
    base_name = re.sub(r'^test_', '', base_name)
    base_name = re.sub(r'(_functional)?\.py$', '', base_name)
    return f"target/gherkin/{base_name}.feature"

def process_test_pair(bucket_name: str, unit_test_file: str, functional_test_file: str) -> None:
    try:
        logger.info(f"Processing test pair: {unit_test_file} and {functional_test_file}")
        
        # Read test files
        unit_test_content = read_file_from_s3(bucket_name, unit_test_file)
        functional_test_content = read_file_from_s3(bucket_name, functional_test_file)
        
        # Extract test information
        unit_tests = extract_test_info(unit_test_content)
        functional_tests = extract_test_info(functional_test_content)
        
        # Generate feature name from the file name
        feature_name = os.path.basename(unit_test_file).replace('test_', '').replace('.py', '')
        
        # Generate Gherkin content
        gherkin_content = generate_gherkin_feature(unit_tests, functional_tests, feature_name)
        
        # Generate output file path
        gherkin_file_path = get_gherkin_filename(unit_test_file)
        
        # Write to S3
        write_to_s3(bucket_name, gherkin_file_path, gherkin_content)
        logger.info(f"Generated Gherkin feature file: {gherkin_file_path}")
        
    except Exception as e:
        logger.error(f"Error processing test pair: {str(e)}")
        raise

def main(bucket_name: str, test_folder: str) -> None:
    try:
        logger.info("Starting test to Gherkin conversion process")
        
        # Get test file pairs
        test_pairs = list_test_files(bucket_name, test_folder)
        total_pairs = len(test_pairs)
        
        logger.info(f"Found {total_pairs} test pairs to process")
        
        for index, (unit_file, functional_file) in enumerate(test_pairs, 1):
            try:
                logger.info(f"Processing pair {index}/{total_pairs}")
                process_test_pair(bucket_name, unit_file, functional_file)
                logger.info(f"Completed processing pair {index}/{total_pairs}")
            except Exception as e:
                logger.error(f"Failed to process test pair: {str(e)}")
                logger.info("Continuing with next pair...")
                continue
        
        logger.info("Gherkin conversion process completed")
        
    except Exception as e:
        logger.error(f"Error in conversion process: {str(e)}")
        raise
    finally:
        upload_log_to_s3(bucket_name, log_filename)

if __name__ == "__main__":
    try:
        script_name = os.path.abspath(__file__)
        logger, log_filename = setup_logging(script_name)
        
        BUCKET_NAME = "s3-genai-coffee-and-innovate"
        TEST_FOLDER = "target/test"
        
        main(BUCKET_NAME, TEST_FOLDER)
    except Exception as e:
        logger.error("Process failed with error:", exc_info=True)
        upload_log_to_s3(BUCKET_NAME, log_filename)
        exit(1)