# AWS Lambda Function - Test Generation
This AWS Lambda function generates unit and functional tests for Python code stored in an S3 bucket.

## Description
The script performs the following actions:

- Sets up logging with a timestamped log file that is uploaded to the specified S3 bucket.
- Lists all Python files in the specified S3 bucket and prefix.
- For each Python file, it:
   - Reads the file content from S3.
   - Generates unit tests using the Anthropic Bedrock API.
   - Generates functional tests using the Anthropic Bedrock API.
   - Writes the generated tests to the specified S3 bucket and prefix.
The script uses the AWS SDK for Python (Boto3) to interact with various AWS services, including S3, Bedrock, and Cloudwatch Logs.

## Prerequisites
- Python 3.7 or higher
- AWS CLI configured with appropriate permissions
- S3 bucket for storing the source code and generated tests

## Configuration
The following variables need to be set in the script:

- BUCKET_NAME: The name of the S3 bucket to use.
- SOURCE_PREFIX: The prefix in the S3 bucket where the source Python files are located.
- DOCS_FOLDER: The prefix in the S3 bucket where the generated tests will be stored.

## Usage
1. Ensure the necessary AWS credentials are configured on the system running the script.
2. Run the script using the following command:
     python script_name.py
The script will process all Python files in the specified S3 bucket and prefix, generate unit and functional tests, and upload the tests to the specified S3 bucket and prefix.

## Error Handling
The script includes error handling for various scenarios, such as:

- Errors when listing or reading files from S3
- Errors when calling the Anthropic Bedrock API
- Unexpected errors during the test generation process
If an error occurs, the script will log the error and continue processing the next file. The log file is uploaded to the specified S3 bucket at the end of the script.

## Deployment
To deploy this script as an AWS Lambda function, you can follow these steps:

1. Create a new Lambda function in the AWS Console, or use the AWS CLI.
2. Configure the function's runtime to use Python 3.7 or higher.
3. Add the necessary AWS permissions to the Lambda function's execution role, such as s3:GetObject, s3:PutObject, and bedrock-runtime:InvokeModel.
4. Upload the script as the Lambda function's code, either by providing the script file or by creating a deployment package (ZIP file).
5. Set the appropriate environment variables for BUCKET_NAME, SOURCE_PREFIX, and DOCS_FOLDER.
6. Configure the Lambda function's trigger, such as an S3 event or a scheduled CloudWatch event, to invoke the function as needed.
Once the Lambda function is deployed, it will automatically process the Python files in the specified S3 bucket and generate the corresponding unit and functional tests.



