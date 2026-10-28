#!/usr/bin/env bash
set -euo pipefail
KEYBRIDGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN in the environment}"
: "${CLOUDFLARE_ACCOUNT_ID:?Set CLOUDFLARE_ACCOUNT_ID in the environment}"
cd "$KEYBRIDGE_ROOT"
npx --yes wrangler@4.154.0 pages deploy site --project-name keybridge --branch main --commit-dirty=true
