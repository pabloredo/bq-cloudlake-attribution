output "billing_export_dataset_id" {
  description = "The ID of the billing export dataset."
  value       = module.bq_showback.billing_export_dataset_id
}

output "observability_dataset_id" {
  description = "The ID of the observability dataset."
  value       = module.bq_showback.observability_dataset_id
}

output "showback_dataset_id" {
  description = "The ID of the showback dataset."
  value       = module.bq_showback.showback_dataset_id
}

output "billing_table_id" {
  description = "Expected standard table ID for Detailed Billing Export (gcp_billing_export_resource_v1_<BILLING_ACCOUNT_ID>)."
  value       = module.bq_showback.billing_table_id
}


output "observability_table_id" {
  description = "Full table ID for client_io_aggregated_events."
  value       = module.bq_showback.observability_table_id
}

output "showback_table_id" {
  description = "Full table ID for showback_cost_attribution."
  value       = module.bq_showback.showback_table_id
}

output "billing_export_dataset_full_id" {
  description = "Fully qualified BigQuery dataset ID for Billing Export (project:dataset)."
  value       = module.bq_showback.billing_export_dataset_full_id
}

output "billing_export_console_url" {
  description = "Direct Google Cloud Console URL to enable/configure Billing Export to BigQuery."
  value       = module.bq_showback.billing_export_console_url
}

output "notebooks_bucket_name" {
  description = "Name of the GCS bucket storing notebooks."
  value       = module.bq_showback.notebooks_bucket_name
}

output "notebook_gcs_uri" {
  description = "GCS URI of the uploaded interactive data preparation notebook."
  value       = module.bq_showback.notebook_gcs_uri
}

output "notebook_storage_console_url" {
  description = "Direct Google Cloud Storage Console link to the uploaded notebook object."
  value       = module.bq_showback.notebook_storage_console_url
}

output "colab_enterprise_console_url" {
  description = "Google Cloud Console URL for Vertex AI Colab Enterprise."
  value       = module.bq_showback.colab_enterprise_console_url
}

output "bigquery_studio_console_url" {
  description = "Google Cloud Console URL for BigQuery Studio."
  value       = module.bq_showback.bigquery_studio_console_url
}


