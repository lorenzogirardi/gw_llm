#!/bin/bash
# Hook: Block file edits if required skill not invoked
# Exit 0 = allow, Exit 2 = block

# Read JSON from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)

# Check .lua files -> require /lua skill
if [[ "$FILE_PATH" == *.lua ]]; then
    if [[ ! -f "/tmp/claude_skill_lua" ]]; then
        echo "BLOCKED: Invoke /lua skill before editing Lua files" >&2
        exit 2
    fi
fi

# Check bedrock/IAM files -> require /aws-bedrock skill
if [[ "$FILE_PATH" == *bedrock* ]] || [[ "$FILE_PATH" == *iam* ]] || [[ "$FILE_PATH" == *IAM* ]]; then
    if [[ ! -f "/tmp/claude_skill_aws_bedrock" ]]; then
        echo "BLOCKED: Invoke /aws-bedrock skill before editing Bedrock/IAM files" >&2
        exit 2
    fi
fi

# Check terraform files -> require permission (Red zone)
if [[ "$FILE_PATH" == *.tf ]]; then
    if [[ ! -f "/tmp/claude_infra_approved" ]]; then
        echo "WARNING: Terraform changes require explicit approval (Red zone)" >&2
        # Don't block, just warn
    fi
fi

exit 0
