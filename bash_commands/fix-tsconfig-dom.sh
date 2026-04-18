#!/bin/bash
set -e

echo "🔧 Adding 'dom' to TypeScript lib to recognize browser APIs..."

# Backup tsconfig.json
cp tsconfig.json tsconfig.json.bak

# Use sed to add "dom" to the lib array if not present
if grep -q '"lib"' tsconfig.json; then
    # If lib exists, add "dom" if not already there
    sed -i '' 's/"lib": \[\(.*\)\]/"lib": [\1, "dom"]/g' tsconfig.json
else
    # If lib doesn't exist, add it under compilerOptions
    sed -i '' '/"compilerOptions": {/a\
    "lib": ["ES2020", "dom"],
' tsconfig.json
fi

# Recompile
npm run compile

echo ""
echo "✅ tsconfig.json updated. 'dom' lib added."
echo "   Now rerun the response pipeline fix script."