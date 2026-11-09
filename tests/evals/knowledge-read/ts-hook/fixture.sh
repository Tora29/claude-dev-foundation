#!/bin/bash
. "$(dirname "$0")/../common.sh"
mkdir -p src
echo "export const version = 1" > src/math.ts
