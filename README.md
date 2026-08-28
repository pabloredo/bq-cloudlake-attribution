# GCP Billing Export & GCS I/O Cost Showback Engine

An end-to-end demonstration joining **Google Cloud BigQuery Detailed Billing Exports** with **Client-Side GCS I/O Observability Telemetry** collected from multi-tenant compute workloads (Spark, Presto, Ray, Hive) running on Google Cloud.

This architecture bridges the visibility gap between bucket-level GCS billing SKUs (Storage, Class A/B Operations, Inter-Region Egress) and granular job/workload execution dimensions (`application_id`, `engine`, `ugi`, `team`, `dataset_path`).

---

## 🏗️ Architecture & Google Cloud Billing Export Pattern

### 1. Google Cloud Billing Export (Google-Managed)
Following Google Cloud best practices, the Cloud Billing service automatically creates and maintains the Detailed Usage Cost export table (`gcp_billing_export_resource_v1_<BILLING_ACCOUNT_ID>`) in BigQuery.
* **Dataset**: Provisioned via Terraform (`google_bigquery_dataset.billing_export`).
* **Table & Schema**: Managed automatically by Google Cloud Billing upon enabling export in the Cloud Billing Console. Schema evolution (e.g. new SKU metadata, `cost_at_list`, `tags`) is handled by Google without manual schema drift.

### 2. Custom Observability & Showback (User-Managed)
* **Observability Dataset & Table** (`observability_dataset.client_io_aggregated_events`): Hourly reduced GCS I/O telemetry emitted by filesystem stream clients.
* **Showback Dataset & Attribution View/Table** (`showback_dataset.showback_cost_attribution` & `vw_showback_cost_attribution`): Joins bucket SKU hourly totals with client-side byte/operation ratios to allocate exact SKU dollars per workload and dataset path.

---

## 📁 Repository Structure

```text
bq-cloudlake-attribution/
├── terraform/                      # Infrastructure as Code (Terraform)
│   ├── main.tf                     # Root Terraform entry point & provider config
│   ├── variables.tf                # Input variables (project_id, billing_account_id, datasets)
│   ├── outputs.tf                  # BigQuery dataset & table outputs
│   ├── terraform.tfvars.example    # Example tfvars input file
│   └── modules/
│       └── bq_showback/            # Module provisioning BigQuery datasets, tables & views
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── scripts/                        # Automation & Synthetic Generator
│   ├── setup_billing_export.sh     # CLI automation to verify/setup GCP Billing Export & BigQuery dataset
│   ├── generate_synthetic_data.py  # Dual-mode synthetic data generator
│   ├── synthetic_data_inserts.sql  # Generated SQL inserts for sandbox/offline use
│   └── run_attribution_transformation.sql # BigQuery SQL attribution transformation pipeline
└── README.md                       # Documentation & Deployment Guide
```

---

## 📊 Datasets & Tables

| Dataset ID | Table / View ID | Type | Managed By | Description |
| :--- | :--- | :--- | :--- | :--- |
| `billing_export_sim` | `gcp_billing_export_resource_v1_<ACCOUNT_ID>` | Table | Google Cloud Billing / Mock | Standard Detailed Billing Export containing resource-level GCS SKUs. |
| `observability_dataset` | `client_io_aggregated_events` | Table | Terraform & Telemetry Stream | Hourly reduced GCS I/O telemetry (Spark, Presto, Ray, Hive). |
| `showback_dataset` | `showback_cost_attribution` | Table | Terraform & Pipeline | Persisted showback table allocating costs per `application_id`, user, and dataset path. |
| `showback_dataset` | `vw_showback_cost_attribution` | View | Terraform | Dynamic view computing showback attribution on-the-fly. |

---

## 🚀 Deployment & Usage

### Step 1: Deploy Infrastructure with Terraform

1. Create your `terraform.tfvars`:
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   ```
2. Update `gcp_project_id` and `billing_account_id` with your GCP values.
3. Initialize and apply Terraform:
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```
   *Terraform automatically provisions the BigQuery datasets and configures IAM permissions for the Cloud Billing system service account (`billing-export-bigquery@system.gserviceaccount.com`).*

---

### Step 2: Configure & Verify Billing Export

You can use the helper CLI script or follow the Cloud Console direct link:

#### Using Google Cloud CLI Helper Script
Run `scripts/setup_billing_export.sh` to auto-detect your project/billing account, verify dataset IAM bindings, and check if export tables are populated:
```bash
./scripts/setup_billing_export.sh
```
*To directly open the GCP Billing Export Console in your browser:*
```bash
./scripts/setup_billing_export.sh --open-console
```

> **Why a 1-time Console step is required:** Google Cloud does not provide a public API/gcloud command to toggle billing account exports for security and governance reasons. The script provisions datasets, sets IAM permissions, and gives you the exact direct URL:
> `https://console.cloud.google.com/billing/<BILLING_ACCOUNT_ID>/export/bigquery?project=<PROJECT_ID>`
> Under **Detailed usage cost**, select your project and dataset (`billing_export_sim`), and click **Save**.

---

### Step 3: Ingest Telemetry Data (or Run Sandbox Simulation)

Depending on your environment, choose **Option A** or **Option B**:

#### Option A: Production Setup with Real GCP Billing Export
Once Google Cloud Billing begins delivering records into BigQuery:
1. Generate **telemetry data only** to simulate multi-tenant workloads interacting with your GCS buckets:
   ```bash
   python3 scripts/generate_synthetic_data.py \
     --mode telemetry-only \
     --project-id YOUR_GCP_PROJECT_ID \
     --output-sql scripts/synthetic_data_inserts.sql
   ```
2. Load the telemetry data into BigQuery:
   ```bash
   bq query --use_legacy_sql=false < scripts/synthetic_data_inserts.sql
   ```

#### Option B: Standalone Demo / Sandbox Simulation
If running in a sandbox without an active GCP billing export:
1. Generate **both** mock standard billing export records and client telemetry:
   ```bash
   python3 scripts/generate_synthetic_data.py \
     --mode all \
     --project-id YOUR_GCP_PROJECT_ID \
     --billing-account-id 01A2B3-C4D5E6-F78901 \
     --output-sql scripts/synthetic_data_inserts.sql
   ```
2. Execute the generated SQL in BigQuery to create the partitioned mock billing export table and load all records:
   ```bash
   bq query --use_legacy_sql=false < scripts/synthetic_data_inserts.sql
   ```

---

### Step 4: Run Cost Showback Transformation

Execute the attribution transformation script to allocate costs:

```bash
bq query --use_legacy_sql=false < scripts/run_attribution_transformation.sql
```

Alternatively, query the dynamic view `showback_dataset.vw_showback_cost_attribution` for real-time calculation.

---

## 💡 Example Analytical Queries

### Query 1: Top 5 Expensive Applications by GCS Cost
```sql
SELECT
  application_id,
  engine,
  team,
  SUM(allocated_cost_usd) AS total_allocated_cost_usd,
  ROUND(SUM(app_bytes) / 1e9, 2) AS total_gb_transferred
FROM
  `showback_dataset.showback_cost_attribution`
GROUP BY
  1, 2, 3
ORDER BY
  total_allocated_cost_usd DESC
LIMIT 5;
```

### Query 2: Cost Breakdown by Dataset Path & Team
```sql
SELECT
  team,
  dataset_path,
  sku_description,
  SUM(allocated_cost_usd) AS cost_usd
FROM
  `showback_dataset.showback_cost_attribution`
GROUP BY
  1, 2, 3
ORDER BY
  cost_usd DESC;
```
