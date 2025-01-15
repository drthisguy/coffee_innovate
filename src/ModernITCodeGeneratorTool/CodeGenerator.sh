#!/bin/bash

scripts=(
    "app_knowledge_base.py"
    "app_src_code_generator.py"
    "app_docs.py"
    "app_epics_features_generator.py"
    "app_gherkin_generator.py"
    "app_unit_functional_code.py"
)

total_scripts=${#scripts[@]}
echo "Total number of scripts to run: $total_scripts"
echo "----------------------------------------"

completed=0

for script in "${scripts[@]}"; do
    echo "Starting: $script"
    
    # Check if file exists
    if [ ! -f "$script" ]; then
        echo "Error: $script does not exist!"
        exit 1
    }
    
    python3 "$script"
    
    if [ $? -eq 0 ]; then
        ((completed++))
        echo "Completed ($completed/$total_scripts): $script"
        echo "----------------------------------------"
    else
        echo "Failed: $script"
        echo "Execution stopped due to error. $completed out of $total_scripts scripts completed."
        exit 1
    fi
done

echo "All $total_scripts scripts completed successfully!"
exit 0

