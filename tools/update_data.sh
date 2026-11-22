#!/usr/bin/env bash
# Rebuild Galio's recommendation data for the latest patch and publish it (commit + push) if it changed.
# Run on the VPS, e.g. from cron:  17 6 * * *  cd /home/ubuntu/Github/galio && tools/update_data.sh >> tools/.cache/update.log 2>&1
# Optional: export RIOT_API_KEY in the environment (never in the repo) to add Match-v5 aggregates.
set -euo pipefail
cd "$(dirname "$0")/.."
git pull -q --rebase origin main
python3 tools/build_data.py --bundle
if [ -n "${RIOT_API_KEY:-}" ]; then
  python3 tools/aggregate_matches.py
  python3 tools/build_data.py --bundle   # merge aggregates.json
fi
if git diff --quiet -- data Galio/Resources/BundledData && [ -z "$(git ls-files --others --exclude-standard data)" ]; then
  echo "data unchanged"
  exit 0
fi
PATCH=$(python3 -c 'import json;print(json.load(open("data/manifest.json"))["latest"])')
git add data Galio/Resources/BundledData
git commit -qm "Data: rebuild recommendation data for patch ${PATCH}"
git push -q origin main
echo "published data for ${PATCH}"
