# PL/SQL to Python Converter

This project is a Python script that converts PL/SQL chess engine code to equivalent Python code. It uses the AWS Bedrock service to perform the code conversion.

## Features

- Reads PL/SQL code (`.pks` and `.pkb` files) from an S3 bucket
- Converts the PL/SQL code to Python code using the AWS Bedrock service
- Writes the converted Python code back to the S3 bucket
- Handles chunking of large code files and retries in case of errors
- Maintains the same chess logic and functionality in the converted Python code
- Follows Pythonic patterns and best practices
- Includes appropriate Python docstrings and type hints
- Logs the conversion process and uploads the logs to the S3 bucket

## Prerequisites

- Python 3.7 or later
- AWS CLI configured with valid credentials
- Access to an S3 bucket and the AWS Bedrock service

## Installation

1. Clone the repository:
git clone https://github.com/your-username/plsql-to-python-converter.git

2. Install the required Python packages:
pip install boto3

## Usage

1. Set the following environment variables:
BUCKET_NAME=your-s3-bucket-name
SOURCE_PREFIX=source/PL-SQL-Chess-master/src
OUTPUT_PREFIX=target

2. Run the script:
python plsql_to_python_converter.py

The script will process all the PL/SQL files in the `SOURCE_PREFIX` directory, convert them to Python, and save the converted code in the `OUTPUT_PREFIX` directory within the specified S3 bucket.

## Logging

The script sets up logging to a log file and the console. The log file is uploaded to the S3 bucket after the conversion process is complete.

## Limitations and Assumptions

- The script assumes that the PL/SQL code follows a certain structure and naming convention (`.pks` and `.pkb` files).
- The script uses the AWS Bedrock service for the code conversion, which has limitations on the number of tokens and the maximum runtime.
- The script does not provide any error handling or fallback options if the Bedrock service is unavailable or the conversion fails.

## Future Improvements

- Add support for more flexible file naming and directory structure.
- Implement more robust error handling and fallback options.
- Provide an option to run the conversion locally without relying on the Bedrock service.
- Add unit tests and integration tests to ensure the correctness of the conversion process.

## Contributing

If you find any issues or have suggestions for improvements, feel free to open an issue or submit a pull request.

## License

This code is licensed under the [MIT License](LICENSE).
