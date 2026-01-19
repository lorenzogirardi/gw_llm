#!/usr/bin/env python3
"""Hook: Add checklist reminder before commits."""
import json
import sys
import re

try:
    data = json.load(sys.stdin)
    prompt = data.get('prompt', '')

    # Check if user is asking about git commit
    if re.search(r'\b(commit|push|git add)\b', prompt, re.I):
        context = """
COMMIT CHECKLIST (from CLAUDE.md):
- [ ] Tests written? (TDD: Red -> Green -> Refactor)
- [ ] Documentation updated? (docs/plugins/, docs/architecture/)
- [ ] No secrets in code?
- [ ] Conventional Commit format? (feat/fix/docs/chore)
- [ ] Skills invoked? (/lua for .lua, /aws-bedrock for Bedrock)
"""
        output = {
            'hookSpecificOutput': {
                'hookEventName': 'UserPromptSubmit',
                'additionalContext': context
            }
        }
        print(json.dumps(output))

    sys.exit(0)
except Exception as e:
    # Don't block on errors, just log
    print(f"Hook warning: {e}", file=sys.stderr)
    sys.exit(0)
