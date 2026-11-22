#!/usr/bin/env bash
# Rebuild Galio's recommendation data for the latest patch and publish it (commit + push) if it changed.
# Run on the VPS, e.g. from cron:  17 6 * * *  cd /home/ubuntu/Github/galio && tools/update_data.sh >> tools/.cache/update.log 2>&1
# Match-v5 aggregation runs when a Riot key is available: RIOT_API_KEY, or the file
# ~/.hermes/secrets/riot_api_key (never in the repo). GALIO_AGG_MINUTES bounds the run (default 30).
set -euo pipefail
cd "$(dirname "$0")/.."
git pull -q --rebase origin main
python3 tools/build_data.py --bundle
if [ -n "${RIOT_API_KEY:-}" ] || [ -s "$HOME/.hermes/secrets/riot_api_key" ]; then
  python3 tools/aggregate_matches.py --budget-minutes "${GALIO_AGG_MINUTES:-30}"
else
  python3 tools/aggregate_matches.py --derive-only   # re-derive from the committed counts
fi
python3 tools/build_data.py --bundle   # merge aggregates.json
if git diff --quiet -- data Galio/Resources/BundledData && [ -z "$(git ls-files --others --exclude-standard data)" ]; then
  echo "data unchanged"
  exit 0
fi
PATCH=$(python3 -c 'import json;print(json.load(open("data/manifest.json"))["latest"])')
git add data Galio/Resources/BundledData
git commit -qm "Data: rebuild recommendation data for patch ${PATCH}"
git push -q origin main
echo "published data for ${PATCH}"
