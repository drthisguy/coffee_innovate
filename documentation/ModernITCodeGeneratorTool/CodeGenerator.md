# Application Development Automation Script

## Overview

This Bash script automates the execution of a series of Python scripts related to various aspects of application development. It ensures that all scripts are run sequentially and handles any errors that may occur during the process.

## Script Details

The script executes the following Python files in order:

1. `app_knowledge_base.py`
2. `app_src_code_generator.py`
3. `app_docs.py`
4. `app_epics_features_generator.py`
5. `app_gherkin_generator.py`
6. `app_unit_functional_code.py`

Each script is presumed to handle a specific aspect of the application development process, such as generating a knowledge base, source code, documentation, epics and features, Gherkin scenarios, and unit/functional test code.

## Features

- **Sequential Execution**: Runs each Python script in a predefined order.
- **Error Handling**: Checks for the existence of each script before execution and stops if a script is missing or fails.
- **Progress Tracking**: Displays the current script being executed and the overall progress.
- **Completion Report**: Provides a summary of completed scripts or details of any failure.

## Usage

To use this script:

1. Ensure all referenced Python scripts are in the same directory as this Bash script.
2. Make the Bash script executable:
    chmod +x CodeGenerator.sh
3. Run the script:
    .CodeGenerator.sh

## Requirements

- Bash shell
- Python 3.x installed and accessible via `python3` command

## Error Handling

- If a script file is missing, the execution will stop with an error message.
- If any Python script exits with a non-zero status, the execution will stop, and a failure message will be displayed.

## Output

The script provides real-time feedback on:
- Total number of scripts to be executed
- Start and completion of each script
- Overall progress (e.g., "Completed (3/6): script_name.py")
- Final success or failure message

## Customization

To modify the list of scripts or their execution order, edit the `scripts` array at the beginning of the Bash script.

This CodeGenerator.md provides a comprehensive description of the shell script, its purpose, functionality, usage instructions, and customization options. It's designed to give users a clear understanding of how to use and potentially modify the script for their needs.
