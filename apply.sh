#!/bin/bash
# Apply Vynix Panel updates
# Run this from the root of the Jtg / Vynix Panel repository

set -e

echo "Applying Vynix Panel rebrand + Purpur/NeoForge support..."

cp -v CreateServer.tsx src/pages/CreateServer.tsx
cp -v Dashboard.tsx src/pages/Dashboard.tsx
cp -v Layout.tsx src/components/Layout.tsx
cp -v jarDownloader.ts src/server/services/jarDownloader.ts
cp -v system.ts src/server/routes/system.ts
cp -v api.ts src/server/routes/api.ts

echo ""
echo "Done. Now rebuild:"
echo "  npm run build"
echo "  pm2 restart all"
echo ""
echo "The panel will show as Vynix Panel and include Purpur + NeoForge."
