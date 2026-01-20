#!/bin/bash
# Hook: Block file edits if required skill not invoked
# Exit 0 = allow, Exit 2 = block

# Read JSON from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Check terraform files -> require permission (Red zone)
if [[ "$FILE_PATH" == *.tf ]]; then
    if [[ ! -f "/tmp/claude_infra_approved" ]]; then
        echo "WARNING: Terraform changes require explicit approval (Red zone)" >&2
        # Don't block, just warn
    fi
fi

exit 0
