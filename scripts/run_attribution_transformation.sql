-- ============================================================================
-- GCS Cost Showback Attribution Pipeline
-- ============================================================================
-- Correlates bucket-level GCS SKU costs (Storage, Class A/B Ops, Egress) from
-- Google Cloud Detailed Billing Export with client-side I/O telemetry to attribute
-- costs to application_id, engine, ugi, team, and dataset path.
-- ============================================================================

-- If using non-default dataset IDs or billing accounts, adjust table names below:
-- Billing table format: `<project_id>.<billing_dataset>.gcp_billing_export_resource_v1_<BILLING_ACCOUNT_ID_WITH_UNDERSCORES>`

INSERT INTO `billing_showback_dataset.showback_cost_attribution` (
  usage_timestamp,
  application_id,
  engine,
  ugi,
  team,
  dataset_path,
  destination_bucket,
  sku_description,
  total_sku_cost,
  app_bytes,
  bucket_total_bytes,
  byte_ratio,
  app_ops,
  bucket_total_ops,
  op_ratio,
  allocated_cost_usd
)
WITH hourly_gcp_billing AS (
  SELECT
    sku.id AS sku_id,
    sku.description AS sku_description,
    resource.name AS bucket_name,
    TIMESTAMP_TRUNC(usage_start_time, HOUR) AS billing_hour,
    SUM(cost) AS total_sku_cost,
    SUM(usage.amount) AS total_sku_usage
  FROM
    `billing_export_sim.gcp_billing_export_resource_v1_01A2B3_C4D5E6_F78901`
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
    `billing_observability_dataset.client_io_aggregated_events`
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
  ON io.bucket_name = b.bucket_name AND io.io_hour = b.billing_hour;
