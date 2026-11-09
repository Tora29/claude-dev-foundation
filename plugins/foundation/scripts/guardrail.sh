#!/bin/bash
here=$(cd "$(dirname "$0")" && pwd) || exit 2
exec jq -c -L "$here" --slurpfile rules "$here/guardrail-rules.json" 'include "guardrail"; decide($rules[0])'
