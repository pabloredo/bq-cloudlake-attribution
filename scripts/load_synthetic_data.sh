#!/usr/bin/env bash
# ==============================================================================
# Helper to execute synthetic data insert scripts into BigQuery
# ==============================================================================
# Automatically detects and executes split SQL part files (or single SQL files)
# within BigQuery's 1024 KB standard SQL query size limit.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Find split parts or single insert script
shopt -s nullglob
PART_FILES=(scripts/synthetic_data_inserts_part*.sql)
shopt -u nullglob

if [ ${#PART_FILES[@]} -gt 0 ]; then
  FILES=("${PART_FILES[@]}")
elif [ -f "scripts/synthetic_data_inserts.sql" ]; then
  FILES=("scripts/synthetic_data_inserts.sql")
else
  echo "❌ Error: No synthetic data insert SQL files found in scripts/."
  echo "Please generate them first by running:"
  echo "  python3 scripts/generate_synthetic_data.py --mode all --project-id <PROJECT_ID> --billing-account-id <BILLING_ACCOUNT_ID>"
  exit 1
fi

echo "🚀 Loading synthetic data into BigQuery (${#FILES[@]} file(s))..."
for file in "${FILES[@]}"; do
  echo "  ▶ Executing ${file}..."
  bq query --use_legacy_sql=false --label datacloud:ai-agent < "${file}"
done

echo "🎉 All synthetic data loaded into BigQuery successfully!"
