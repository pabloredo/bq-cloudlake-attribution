# BigQuery Datasets

resource "google_bigquery_dataset" "billing_export" {
  project                    = var.project_id
  dataset_id                 = var.billing_dataset_id
  friendly_name              = "GCP Detailed Billing Export"
  description                = "Contains GCP BigQuery Detailed Billing Export tables for GCS SKUs."
  location                   = var.location
  delete_contents_on_destroy = true
}

# Grant Cloud Billing export service account permission to write to this dataset
resource "google_bigquery_dataset_iam_member" "billing_export_writer" {
  count      = var.enable_billing_export_dataset_iam ? 1 : 0
  project    = var.project_id
  dataset_id = google_bigquery_dataset.billing_export.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:billing-export-bigquery@system.gserviceaccount.com"
}

resource "google_bigquery_dataset" "observability" {
  project                    = var.project_id
  dataset_id                 = var.observability_dataset_id
  friendly_name              = "Client-Side GCS I/O Observability Telemetry"
  description                = "Contains hourly aggregated client-side filesystem I/O metrics across compute workloads."
  location                   = var.location
  delete_contents_on_destroy = true
}

resource "google_bigquery_dataset" "showback" {
  project                    = var.project_id
  dataset_id                 = var.showback_dataset_id
  friendly_name              = "GCS Cost Showback Attribution"
  description                = "Contains attributed cost showback tables and views linking GCP GCS SKU costs to workloads, users, teams, and dataset paths."
  location                   = var.location
  delete_contents_on_destroy = true
}

# Note on Google Cloud Billing Export:
# Following Google Cloud's recommended architecture, the Detailed Billing Export table
# (gcp_billing_export_resource_v1_<BILLING_ACCOUNT_ID>) is automatically created and maintained
# by Google Cloud Billing once BigQuery export is enabled in the Cloud Billing settings.
# Therefore, we do not manually manage its schema via Terraform to prevent schema drift.

resource "google_bigquery_table" "client_io_aggregated_events" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.observability.dataset_id
  table_id            = "client_io_aggregated_events"
  description         = "Hourly reduced GCS I/O telemetry emitted by Java FS stream clients."
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "event_timestamp"
  }

  clustering = ["destination_bucket", "application_id", "parent_directory"]

  schema = <<EOF
[
  {
    "name": "application_id",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Unique runtime ID e.g. Spark App ID, Presto Query ID"
  },
  {
    "name": "engine",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Execution framework e.g. Spark, Presto, Ray, Hive"
  },
  {
    "name": "ugi",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "User or service account submitting workload"
  },
  {
    "name": "parent_directory",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Dataset partition path e.g. /data/warehouse/sales/year=2026"
  },
  {
    "name": "operation_type",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Operation category e.g. READ, WRITE, LIST, DELETE"
  },
  {
    "name": "bytes_transferred",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "Total bytes read/written to GCS"
  },
  {
    "name": "operation_count",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "Total count of GCS operational calls"
  },
  {
    "name": "source_zone",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "GCP Availability Zone of compute node e.g. us-central1-a"
  },
  {
    "name": "destination_bucket",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Target GCS Bucket Name"
  },
  {
    "name": "event_timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED",
    "description": "Start timestamp of aggregation window"
  }
]
EOF
}

# 3. Cost Showback Attribution Table
resource "google_bigquery_table" "showback_cost_attribution" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.showback.dataset_id
  table_id            = "showback_cost_attribution"
  description         = "Final showback table allocating GCS SKU costs per application_id, user, team, and dataset path."
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "usage_timestamp"
  }

  clustering = ["application_id", "ugi", "dataset_path"]

  schema = <<EOF
[
  {
    "name": "usage_timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED"
  },
  {
    "name": "application_id",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "engine",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "ugi",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "team",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "dataset_path",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "destination_bucket",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "sku_description",
    "type": "STRING",
    "mode": "NULLABLE"
  },
  {
    "name": "total_sku_cost",
    "type": "NUMERIC",
    "mode": "NULLABLE"
  },
  {
    "name": "app_bytes",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "bucket_total_bytes",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "byte_ratio",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "app_ops",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "bucket_total_ops",
    "type": "INTEGER",
    "mode": "NULLABLE"
  },
  {
    "name": "op_ratio",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "allocated_cost_usd",
    "type": "NUMERIC",
    "mode": "NULLABLE"
  }
]
EOF
}

# 4. Cost Showback View for Dynamic On-the-Fly Querying
# Note: BigQuery validates the query at creation time. This requires the billing export table
# to exist first (via Cloud Billing export or synthetic data). Enabled via create_attribution_view.
resource "google_bigquery_table" "vw_showback_cost_attribution" {
  count               = var.create_attribution_view ? 1 : 0
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.showback.dataset_id
  table_id            = "vw_showback_cost_attribution"
  description         = "Dynamic view for real-time GCS cost showback attribution across applications, teams, and dataset paths."
  deletion_protection = false

  view {
    query = <<EOF
WITH hourly_gcp_billing AS (
  SELECT
    sku.id AS sku_id,
    sku.description AS sku_description,
    resource.name AS bucket_name,
    TIMESTAMP_TRUNC(usage_start_time, HOUR) AS billing_hour,
    SUM(cost) AS total_sku_cost,
    SUM(usage.amount) AS total_sku_usage
  FROM
    `${var.project_id}.${var.billing_dataset_id}.gcp_billing_export_resource_v1_${replace(var.billing_account_id, "-", "_")}`
  WHERE
    service.description = 'Google Cloud Storage'
  GROUP BY
    1, 2, 3, 4
),

hourly_client_io AS (
  SELECT
    destination_bucket AS bucket_name,
    application_id,
    engine,
    ugi,
    parent_directory,
    TIMESTAMP_TRUNC(event_timestamp, HOUR) AS io_hour,
    SUM(bytes_transferred) AS app_bytes,
    SUM(operation_count) AS app_ops
  FROM
    `${var.project_id}.${var.observability_dataset_id}.client_io_aggregated_events`
  GROUP BY
    1, 2, 3, 4, 5, 6
),

bucket_hourly_totals AS (
  SELECT
    bucket_name,
    io_hour,
    SUM(app_bytes) AS bucket_total_bytes,
    SUM(app_ops) AS bucket_total_ops
  FROM
    hourly_client_io
  GROUP BY
    1, 2
)

SELECT
  io.io_hour AS usage_timestamp,
  io.application_id,
  io.engine,
  io.ugi,
  SPLIT(io.ugi, '@')[SAFE_OFFSET(0)] AS team,
  io.parent_directory AS dataset_path,
  io.bucket_name AS destination_bucket,
  b.sku_description,
  b.total_sku_cost,
  io.app_bytes,
  bt.bucket_total_bytes,
  SAFE_DIVIDE(io.app_bytes, bt.bucket_total_bytes) AS byte_ratio,
  io.app_ops,
  bt.bucket_total_ops,
  SAFE_DIVIDE(io.app_ops, bt.bucket_total_ops) AS op_ratio,
  ROUND(
    b.total_sku_cost * CASE
      WHEN b.sku_description LIKE '%Operations%' THEN SAFE_DIVIDE(io.app_ops, bt.bucket_total_ops)
      ELSE SAFE_DIVIDE(io.app_bytes, bt.bucket_total_bytes)
    END, 4
  ) AS allocated_cost_usd
FROM
  hourly_client_io io
JOIN
  bucket_hourly_totals bt
  ON io.bucket_name = bt.bucket_name AND io.io_hour = bt.io_hour
JOIN
  hourly_gcp_billing b
  ON io.bucket_name = b.bucket_name AND io.io_hour = b.billing_hour
EOF
    use_legacy_sql = false
  }
}

# ------------------------------------------------------------------------------
# 5. Interactive Notebook GCS Bucket & Object
# ------------------------------------------------------------------------------

locals {
  notebook_bucket_name = var.notebooks_bucket_name != "" ? var.notebooks_bucket_name : "${var.project_id}-lakehouse-notebooks"
  notebook_source_path = var.notebook_file_path != "" ? var.notebook_file_path : "${path.module}/../../../notebooks/gcs_cost_showback_dataprep.ipynb"
}

resource "google_storage_bucket" "notebooks" {
  count                       = var.upload_notebook ? 1 : 0
  name                        = local.notebook_bucket_name
  project                     = var.project_id
  location                    = var.location
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket_object" "showback_notebook" {
  count        = var.upload_notebook ? 1 : 0
  name         = "notebooks/gcs_cost_showback_dataprep.ipynb"
  bucket       = google_storage_bucket.notebooks[0].name
  content      = replace(
    replace(
      file(local.notebook_source_path),
      "YOUR_PROJECT_ID", var.project_id
    ),
    "01A2B3-C4D5E6-F78901", var.billing_account_id
  )
  content_type = "application/x-ipynb+json"
}

