#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Billing Export Setup & Verification CLI
# ==============================================================================
# Sets up prerequisites, BigQuery dataset, IAM permissions, and verifies
# the Cloud Billing Detailed Usage Cost export into BigQuery.
# ==============================================================================

set -euo pipefail

# Default Configurations
PROJECT_ID=""
BILLING_ACCOUNT_ID=""
DATASET_ID="billing_export_sim"
REGION="US"
GRANT_IAM=true
CHECK_ONLY=false
OPEN_CONSOLE=false

# Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { printf "${BLUE}%s${NC}\n" "$*"; }
success() { printf "${GREEN}%s${NC}\n" "$*"; }
warn()    { printf "${YELLOW}%s${NC}\n" "$*"; }
err()     { printf "${RED}%s${NC}\n" "$*"; }
header()  { printf "${BOLD}${CYAN}%s${NC}\n" "$*"; }

usage() {
  printf "%bUsage:%b %s [OPTIONS]\n\n" "${BOLD}" "${NC}" "$0"
  printf "%bOptions:%b\n" "${BOLD}" "${NC}"
  printf "  -p, --project-id <PROJECT_ID>          GCP Project ID (defaults to active gcloud config)\n"
  printf "  -b, --billing-account-id <ACCOUNT_ID>  GCP Billing Account ID (e.g., 01A2B3-C4D5E6-F78901)\n"
  printf "  -d, --dataset-id <DATASET_ID>          BigQuery Dataset ID for billing export (default: billing_export_sim)\n"
  printf "  -r, --region <REGION>                  BigQuery Dataset location (default: US)\n"
  printf "      --no-iam                           Skip granting dataset IAM permission to Cloud Billing service account\n"
  printf "      --check-only                       Only check existing status without creating resources\n"
  printf "      --open-console                     Open Google Cloud Billing Export console in default browser\n"
  printf "  -h, --help                             Display this help message\n\n"
  printf "%bExamples:%b\n" "${BOLD}" "${NC}"
  printf "  # Interactive / Auto-detected setup\n"
  printf "  %s\n\n" "$0"
  printf "  # Specific project and billing account\n"
  printf "  %s -p my-project -b 01A2B3-C4D5E6-F78901 -d billing_export_prod -r US\n\n" "$0"
  printf "  # Verify existing configuration only\n"
  printf "  %s -p my-project -b 01A2B3-C4D5E6-F78901 --check-only\n" "$0"
  exit 0
}

# Parse Command Line Arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    -b|--billing-account-id)
      BILLING_ACCOUNT_ID="$2"
      shift 2
      ;;
    -d|--dataset-id)
      DATASET_ID="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    --no-iam)
      GRANT_IAM=false
      shift
      ;;
    --check-only)
      CHECK_ONLY=true
      shift
      ;;
    --open-console)
      OPEN_CONSOLE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      usage
      ;;
  esac
done

header "=============================================================================="
header " 🚀 GCP Detailed Billing Export to BigQuery Setup & Verification"
header "=============================================================================="
printf "\n"

# ------------------------------------------------------------------------------
# 1. Dependency & Auth Verification
# ------------------------------------------------------------------------------
info "[1/5] Checking CLI dependencies & authentication..."

if ! command -v gcloud &> /dev/null; then
  err "❌ Error: 'gcloud' CLI is not installed or not in PATH."
  printf "Please install Google Cloud SDK: https://cloud.google.com/sdk/docs/install\n"
  exit 1
fi

if ! command -v bq &> /dev/null; then
  err "❌ Error: 'bq' CLI is not installed or not in PATH."
  printf "Please install BigQuery CLI via: gcloud components install bq\n"
  exit 1
fi

ACTIVE_ACCOUNT=$(CLOUDSDK_METRICS_ENVIRONMENT=datacloud.ai-agent gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
if [ -z "$ACTIVE_ACCOUNT" ]; then
  err "❌ Error: No active gcloud authentication found."
  printf "Please run: gcloud auth login && gcloud auth application-default login\n"
  exit 1
fi
printf "  ✅ Authenticated as: %b%s%b\n" "${GREEN}" "${ACTIVE_ACCOUNT}" "${NC}"

# Resolve Project ID
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(CLOUDSDK_METRICS_ENVIRONMENT=datacloud.ai-agent gcloud config get-value project 2>/dev/null || true)
  if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    err "❌ Error: Project ID is not specified and could not be detected."
    printf "Use --project-id <PROJECT_ID> or run: gcloud config set project <PROJECT_ID>\n"
    exit 1
  fi
fi
printf "  ✅ Target GCP Project: %b%s%b\n" "${GREEN}" "${PROJECT_ID}" "${NC}"

# Resolve Billing Account ID
if [ -z "$BILLING_ACCOUNT_ID" ]; then
  printf "  🔍 Detecting accessible Cloud Billing Accounts...\n"
  BILLING_ACCOUNTS=$(CLOUDSDK_METRICS_ENVIRONMENT=datacloud.ai-agent gcloud billing accounts list --format="value(name,displayName,open)" 2>/dev/null || true)
  
  if [ -n "$BILLING_ACCOUNTS" ]; then
    # Grab the first active billing account
    BILLING_ACCOUNT_ID=$(echo "$BILLING_ACCOUNTS" | grep "True" | head -n 1 | awk '{print $1}' || true)
  fi

  if [ -z "$BILLING_ACCOUNT_ID" ]; then
    # Fallback to default placeholder if detection yields nothing
    BILLING_ACCOUNT_ID="01A2B3-C4D5E6-F78901"
    warn "  ⚠️  Could not automatically discover active billing account. Using: ${BILLING_ACCOUNT_ID}"
  else
    printf "  ✅ Detected Billing Account: %b%s%b\n" "${GREEN}" "${BILLING_ACCOUNT_ID}" "${NC}"
  fi
else
  printf "  ✅ Specified Billing Account: %b%s%b\n" "${GREEN}" "${BILLING_ACCOUNT_ID}" "${NC}"
fi

CLEAN_BILLING_ID=$(echo "${BILLING_ACCOUNT_ID}" | tr '-' '_')
EXPECTED_TABLE="gcp_billing_export_resource_v1_${CLEAN_BILLING_ID}"

printf "\n"

# ------------------------------------------------------------------------------
# 2. BigQuery Dataset Setup / Verification
# ------------------------------------------------------------------------------
info "[2/5] Verifying BigQuery dataset '${DATASET_ID}' in location '${REGION}'..."

if bq show --dataset "${PROJECT_ID}:${DATASET_ID}" &>/dev/null; then
  printf "  ✅ Dataset %b%s:%s%b already exists.\n" "${GREEN}" "${PROJECT_ID}" "${DATASET_ID}" "${NC}"
else
  if [ "$CHECK_ONLY" = true ]; then
    warn "  ⚠️  Dataset '${DATASET_ID}' does not exist in project '${PROJECT_ID}'."
  else
    printf "  Creating dataset %b%s:%s%b (location: %s)...\n" "${CYAN}" "${PROJECT_ID}" "${DATASET_ID}" "${NC}" "${REGION}"
    bq --location="${REGION}" mk \
      --dataset \
      --label datacloud:ai-agent \
      --description "Contains GCP BigQuery Detailed Billing Export tables for GCS SKUs" \
      "${PROJECT_ID}:${DATASET_ID}"
    success "  ✅ Dataset created successfully."
  fi
fi

printf "\n"

# ------------------------------------------------------------------------------
# 3. IAM Permission Setup
# ------------------------------------------------------------------------------
info "[3/5] Verifying Cloud Billing Service Account IAM permissions..."

BILLING_SA="billing-export-bigquery@system.gserviceaccount.com"

if [ "$GRANT_IAM" = true ] && [ "$CHECK_ONLY" = false ]; then
  printf "  Granting %broles/bigquery.dataEditor%b to %b%s%b on dataset...\n" "${CYAN}" "${NC}" "${CYAN}" "${BILLING_SA}" "${NC}"
  if bq add-iam-policy-binding \
      --member="serviceAccount:${BILLING_SA}" \
      --role="roles/bigquery.dataEditor" \
      "${PROJECT_ID}:${DATASET_ID}" &>/dev/null; then
    success "  ✅ Successfully configured BigQuery Data Editor IAM role on dataset."
  else
    printf "  %bℹ️  IAM binding via 'bq' CLI skipped (or already configured). Permissions will also be applied when enabling export in Cloud Console.%b\n" "${YELLOW}" "${NC}"
  fi
else
  printf "  ⏭️  IAM configuration step skipped (--no-iam or --check-only).\n"
fi

printf "\n"

# ------------------------------------------------------------------------------
# 4. Detailed Billing Export Table Verification
# ------------------------------------------------------------------------------
info "[4/5] Checking Detailed Billing Export Table '${EXPECTED_TABLE}'..."

TABLE_EXISTS=false
if bq show "${PROJECT_ID}:${DATASET_ID}.${EXPECTED_TABLE}" &>/dev/null; then
  TABLE_EXISTS=true
  printf "  ✅ Billing export table %b%s:%s.%s%b found!\n" "${GREEN}" "${PROJECT_ID}" "${DATASET_ID}" "${EXPECTED_TABLE}" "${NC}"
  
  info "  🔍 Running data sanity check for Google Cloud Storage SKU records..."
  CHECK_QUERY="
    SELECT
      COUNT(*) AS total_records,
      COUNTIF(service.description = 'Google Cloud Storage') AS gcs_records,
      CAST(MIN(usage_start_time) AS STRING) AS earliest_usage,
      CAST(MAX(usage_start_time) AS STRING) AS latest_usage
    FROM
      \`${PROJECT_ID}.${DATASET_ID}.${EXPECTED_TABLE}\`
  "
  
  QUERY_RESULT=$(bq query --use_legacy_sql=false --format=prettyjson --label datacloud:ai-agent "${CHECK_QUERY}" 2>/dev/null || true)
  
  if [ -n "$QUERY_RESULT" ]; then
    printf "  📊 Current Table Summary:\n"
    echo "$QUERY_RESULT" | grep -E '(total_records|gcs_records|earliest_usage|latest_usage)' || echo "$QUERY_RESULT"
  fi
else
  warn "  ⚠️  Table '${EXPECTED_TABLE}' does not exist in dataset '${DATASET_ID}' yet."
  printf "  %bNote:%b Google Cloud Billing creates this table automatically once the export is enabled in Cloud Console.\n" "${CYAN}" "${NC}"
fi

printf "\n"

# ------------------------------------------------------------------------------
# 5. Cloud Console Instructions & URL
# ------------------------------------------------------------------------------
CONSOLE_URL="https://console.cloud.google.com/billing/${BILLING_ACCOUNT_ID}/export/bigquery?project=${PROJECT_ID}"

printf "%b%b[5/5] Google Cloud Billing Export Activation & Next Steps%b\n" "${BOLD}" "${BLUE}" "${NC}"
printf -- "------------------------------------------------------------------------------\n"

if [ "$TABLE_EXISTS" = true ]; then
  printf "%b🎉 Detailed Billing Export is already active and available in BigQuery!%b\n\n" "${GREEN}" "${NC}"
  printf "You can now run the Cost Showback Transformation pipeline:\n"
  printf "  %bbq query --use_legacy_sql=false < scripts/run_attribution_transformation.sql%b\n" "${BOLD}" "${NC}"
else
  printf "Google Cloud requires enabling Billing Export to BigQuery via the Cloud Console.\n"
  printf "\n%bFollow these 3 quick steps to enable it:%b\n" "${BOLD}" "${NC}"
  printf "  1. Open the Cloud Billing Export Console URL:\n"
  printf "     %b%b%s%b\n" "${BOLD}" "${CYAN}" "${CONSOLE_URL}" "${NC}"
  printf "  2. Under %b'Detailed usage cost'%b, click %b'Edit Settings'%b (or 'Enable Export').\n" "${BOLD}" "${NC}" "${BOLD}" "${NC}"
  printf "  3. Configure:\n"
  printf "     - %bProject:%b %b%s%b\n" "${BOLD}" "${NC}" "${GREEN}" "${PROJECT_ID}" "${NC}"
  printf "     - %bBigQuery dataset:%b %b%s%b\n" "${BOLD}" "${NC}" "${GREEN}" "${DATASET_ID}" "${NC}"
  printf "     - Click %b'Save'%b.\n" "${BOLD}" "${NC}"
  printf "\n%b⏳ Note on Data Availability:%b\n" "${YELLOW}" "${NC}"
  printf "Google Cloud typically begins delivering billing export records within a few hours.\n"
  printf "For Multi-region US/EU datasets, Google includes retroactive data for the current month.\n"
  
  printf "\n%b🧪 Sandbox / Offline Testing Alternative:%b\n" "${BOLD}" "${NC}"
  printf "To test immediately without waiting for production billing export data, generate mock data:\n"
  printf "  %bpython3 scripts/generate_synthetic_data.py --mode all --project-id %s --billing-account-id %s%b\n" "${BOLD}" "${PROJECT_ID}" "${BILLING_ACCOUNT_ID}" "${NC}"
  printf "  %bbq query --use_legacy_sql=false < scripts/synthetic_data_inserts.sql%b\n" "${BOLD}" "${NC}"
fi

printf -- "------------------------------------------------------------------------------\n\n"

# Open in browser if requested
if [ "$OPEN_CONSOLE" = true ]; then
  printf "🌐 Opening Cloud Console in your browser...\n"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$CONSOLE_URL"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    xdg-open "$CONSOLE_URL" &>/dev/null || true
  fi
fi

success "✅ Script execution completed."
