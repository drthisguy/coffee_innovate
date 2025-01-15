# Test to Gherkin Converter

## Overview

This Python script automates the conversion of unit and functional tests into Gherkin feature files. It processes Python test files stored in an AWS S3 bucket, extracts test information, and generates corresponding Gherkin scenarios.

## Features

- Automatically pairs unit tests with their corresponding functional tests
- Extracts test case information from Python test files
- Generates Gherkin feature files with scenarios based on unit and functional tests
- Uploads generated Gherkin files back to S3
- Comprehensive logging with S3 upload functionality

## Requirements

- Python 3.x
- boto3 library
- AWS account with access to S3

## Setup

1. Clone this repository:
   git clone https://github.com/your-username/test-to-gherkin-converter.git
   cd test-to-gherkin-converter


2. Install required dependencies:
   pip install boto3


3. Configure AWS credentials:
Ensure you have valid AWS credentials set up, either through environment variables, AWS CLI configuration, or an IAM role.

4. Update the following variables in the script:
- `BUCKET_NAME`: Your S3 bucket name
- `TEST_FOLDER`: The folder in your bucket containing test files

## Usage

Run the script:
python test_to_gherkin_converter.py


The script will:
1. List all Python test files in the specified S3 bucket and folder
2. Pair unit tests with their corresponding functional tests
3. Process each pair to extract test information
4. Generate Gherkin feature files based on the extracted information
5. Upload the generated Gherkin files back to S3
6. Log the entire process, with logs also uploaded to S3

## File Naming Conventions

- Unit test files should be named `test_*.py`
- Functional test files should be named `test_*_functional.py`
- Generated Gherkin files will be named `*.feature` and stored in the `target/gherkin/` folder in S3

## Generated Gherkin Structure

For each test pair, the script generates a Gherkin feature file with:

1. Feature name and description
2. Unit test scenarios
3. Functional test scenarios

Each scenario includes:
- A descriptive name based on the test method
- Given, When, Then steps reflecting the nature of the test

## Error Handling

- The script implements error handling for individual test pair processing
- Errors are logged, and the process continues with subsequent test pairs in case of individual failures

## Logging

- Creates timestamped log files for each run
- Logs are stored locally and then uploaded to S3 upon completion

## Customization

- Modify the `extract_test_info` function to adjust how test information is extracted
- Adjust the `generate_gherkin_feature` function to change the structure of generated Gherkin features

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License



This app_gherkin_generator.md provides a comprehensive overview of the script, including its purpose, setup instructions, usage guidelines, and customization options. It's designed to help users quickly understand and start using the test to Gherkin converter.
