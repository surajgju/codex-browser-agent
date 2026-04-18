#!/bin/bash
set -e

echo "🔧 Fixing Logger calls in SyncEngine.ts..."

# Backup
cp src/sync/SyncEngine.ts src/sync/SyncEngine.ts.bak2

# Replace the problematic lines using sed
sed -i '' "s/Logger.error('applyResponse received invalid data:', responseData);/Logger.error('applyResponse received invalid data: ' + JSON.stringify(responseData));/g" src/sync/SyncEngine.ts
sed -i '' "s/Logger.info('Response text was:', responseText.substring(0, 500));/Logger.info('Response text was: ' + responseText.substring(0, 500));/g" src/sync/SyncEngine.ts

# Recompile
npm run compile

echo ""
echo "✅ Logger calls fixed. Restart extension host (F5)."