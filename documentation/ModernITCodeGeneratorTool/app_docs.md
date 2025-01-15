# AI-Powered Documentation Generator

## Overview

This Python script automates the process of generating comprehensive documentation for Python files stored in an AWS S3 bucket. It utilizes AWS Bedrock's Claude 3.5 Sonnet model to analyze Python code and create detailed, user-friendly documentation.

## Features

- Batch processing of Python files from a specified S3 bucket and prefix
- AI-powered documentation generation using AWS Bedrock
- Automatic upload of generated documentation back to S3
- Robust error handling and logging
- Exponential backoff retry mechanism for API calls

## Requirements

- Python 3.x
- boto3
- AWS account with access to S3 and Bedrock services

## Configuration

Set the following variables in the script:

- `BUCKET_NAME`: The S3 bucket containing your Python files
- `SOURCE_PREFIX`: The prefix (folder) within the bucket where Python files are located
- `DOCS_FOLDER`: The destination folder for generated documentation

## Usage

1. Ensure you have the necessary AWS credentials configured.
2. Install required dependencies:
   pip install boto3

text
Copy
3. Run the script:
   python script_name.py

text
Copy

## Functionality

1. **File Discovery**: Lists all Python files in the specified S3 bucket and prefix.
2. **Code Retrieval**: Reads the content of each Python file from S3.
3. **Documentation Generation**: Uses AWS Bedrock to analyze the code and generate comprehensive documentation.
4. **Documentation Storage**: Writes the generated documentation back to S3 in Markdown format.
5. **Logging**: Maintains detailed logs of the process, which are also uploaded to S3.

## Error Handling

- Implements exponential backoff for retrying failed API calls.
- Catches and logs various exceptions, allowing the process to continue with subsequent files in case of individual failures.

## Logging

- Creates timestamped log files for each run.
- Logs are stored locally and then uploaded to S3 upon completion.

## Customization

- Modify the `generate_documentation` function to adjust the prompt or output format.
- Adjust retry parameters in `call_bedrock_with_retry` for different backoff behaviors.

## Contributing

Contributions to improve the script or extend its functionality are welcome. Please submit a pull request with your proposed changes.

## License




This app_docs.md provides a comprehensive description of the script, its purpose, functionality, setup instructions, and customization options. It's designed to give users and potential contributors a clear understanding of the project and how to use or modify it.
