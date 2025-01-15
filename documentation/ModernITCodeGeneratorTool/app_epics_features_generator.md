# AI-Powered Agile Requirements Generator

## Overview

This Python script automates the generation of comprehensive agile requirements documentation for Python projects stored in AWS S3. It leverages AWS Bedrock's Claude 3.5 Sonnet model to analyze Python code and create detailed, user-friendly requirements in Markdown format.

## Features

- Batch processing of Python files from a specified S3 bucket and prefix
- AI-powered requirements generation using AWS Bedrock
- Automatic upload of generated requirements back to S3
- Robust error handling and logging
- Exponential backoff retry mechanism for API calls

## Requirements

- Python 3.x
- boto3
- AWS account with access to S3 and Bedrock services

## Setup

1. Clone this repository:
   git clone https://github.com/your-username/ai-requirements-generator.git
   cd ai-requirements-generator



2. Install required dependencies:
   pip install boto3



3. Configure AWS credentials:
Ensure you have valid AWS credentials set up, either through environment variables, AWS CLI configuration, or an IAM role.

4. Update the following variables in the script:
- `BUCKET_NAME`: Your S3 bucket name
- `SOURCE_PREFIX`: The folder in your bucket containing Python files
- `EPIC_FOLDER`: The destination folder for generated requirements

## Usage

Run the script:
python requirements_generator.py



The script will:
1. List all Python files in the specified S3 bucket and prefix
2. Process each file to generate agile requirements
3. Upload the generated requirements back to S3
4. Log the entire process, with logs also uploaded to S3

## Generated Requirements Structure

For each Python file, the script generates a Markdown document with:

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
   - Story title
   - User story format: As a [role], I want [goal], so that [benefit]
   - Story points estimation
   - Priority (Must Have/Should Have/Could Have)
   - Acceptance Criteria (minimum 3 per story)

## Error Handling

- The script implements exponential backoff for retrying failed API calls
- Errors are logged, and the process continues with subsequent files in case of individual failures

## Logging

- Creates timestamped log files for each run
- Logs are stored locally and then uploaded to S3 upon completion

## Customization

- Modify the `generate_requirements` function to adjust the prompt or output format
- Adjust retry parameters in `call_bedrock_with_retry` for different backoff behaviors

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License



This app_epics_features_generator.md provides a comprehensive overview of the script, including its purpose, setup instructions, usage guidelines, and customization options. It's designed to help users quickly understand and start using the AI-powered requirements generator.
