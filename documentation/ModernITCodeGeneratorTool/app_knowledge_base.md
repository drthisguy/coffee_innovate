# PL/SQL and README Knowledge Base Generator

## Overview

This Python script automates the process of generating a comprehensive knowledge base from PL/SQL code files and README documents stored in an AWS S3 bucket. It uses Amazon Bedrock's Claude 3.5 Sonnet model to analyze the content and create detailed documentation, domain knowledge, and SME-style Q&A for each file.

## Features

- Processes both PL/SQL and README files
- Generates three types of knowledge base content:
  - Documentation
  - Domain Knowledge
  - SME Conversation (Q&A style)
- Handles various file encodings
- Implements robust error handling and retry logic
- Uploads generated content and logs to S3

## Prerequisites

- Python 3.7+
- AWS account with access to S3 and Bedrock
- Required Python packages: `boto3`

## Setup

1. Clone the repository:


3. Install required packages:
   pip install boto3

4. Configure AWS credentials:
Ensure you have valid AWS credentials set up with access to S3 and Bedrock.

5. Update the following variables in the script:
- `BUCKET_NAME`: Your S3 bucket name
- `SOURCE_PREFIX`: The folder in your bucket containing the source files

## Usage

Run the script:
python knowledge_base_generator.py

The script will:
1. List all PL/SQL and README files in the specified S3 bucket and folder
2. Process each file to generate documentation, domain knowledge, and SME conversation content
3. Upload the generated content back to S3 in the `target/knowledge_base/` folder
4. Log the entire process, with logs also uploaded to S3

## File Processing

- PL/SQL files: Processes files with extensions .sql, .pls, .plsql, .pck, .pkb, .pks
- README files: Processes files named README.txt or README.md

## Generated Content Structure

For each processed file, the script generates:

1. Documentation (overview, descriptions, parameters, usage examples)
2. Domain Knowledge (business rules, data model insights, key processes)
3. SME Conversation (Q&A style knowledge base)

## Error Handling and Logging

- Implements comprehensive error handling for individual file processing
- Uses a retry mechanism for API calls to handle transient errors
- Creates detailed logs for each run, which are uploaded to S3

## Customization

- Modify the `prompts` dictionary in `process_plsql_file` and `process_readme_file` functions to adjust the content generation prompts
- Update the `is_plsql_file` function to include or exclude specific file types

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License



## Disclaimer

This script interacts with AWS services and may incur costs. Please review the AWS pricing for S3 and Bedrock before running this script at scale.
