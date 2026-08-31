output "billing_export_dataset_id" {
  value = google_bigquery_dataset.billing_export.dataset_id
}

output "observability_dataset_id" {
  value = google_bigquery_dataset.observability.dataset_id
}

output "showback_dataset_id" {
  value = google_bigquery_dataset.showback.dataset_id
}

output "billing_table_id" {
  value = "${google_bigquery_dataset.billing_export.dataset_id}.gcp_billing_export_resource_v1_${replace(var.billing_account_id, "-", "_")}"
}


output "observability_table_id" {
  value = "${google_bigquery_dataset.observability.dataset_id}.${google_bigquery_table.client_io_aggregated_events.table_id}"
}

output "showback_table_id" {
  value = "${google_bigquery_dataset.showback.dataset_id}.${google_bigquery_table.showback_cost_attribution.table_id}"
}

output "billing_export_dataset_full_id" {
  description = "Fully qualified BigQuery dataset ID for Billing Export"
  value       = "${var.project_id}:${google_bigquery_dataset.billing_export.dataset_id}"
}

output "billing_export_console_url" {
  description = "Direct Google Cloud Console URL to enable Billing Export to BigQuery"
  value       = "https://console.cloud.google.com/billing/${var.billing_account_id}/export/bigquery?project=${var.project_id}"
}

output "notebooks_bucket_name" {
  description = "Name of the GCS bucket storing notebooks"
  value       = var.upload_notebook ? google_storage_bucket.notebooks[0].name : ""
}

output "notebook_gcs_uri" {
  description = "GCS URI of the uploaded interactive data preparation notebook"
  value       = var.upload_notebook ? "gs://${google_storage_bucket.notebooks[0].name}/${google_storage_bucket_object.showback_notebook[0].name}" : ""
}

output "notebook_storage_console_url" {
  description = "Direct Google Cloud Storage Console link to the uploaded notebook object"
  value       = var.upload_notebook ? "https://console.cloud.google.com/storage/browser/_details/${google_storage_bucket.notebooks[0].name}/${google_storage_bucket_object.showback_notebook[0].name}?project=${var.project_id}" : ""
}

output "colab_enterprise_console_url" {
  description = "Google Cloud Console URL for Vertex AI Colab Enterprise"
  value       = "https://console.cloud.google.com/agent-platform/colab/notebooks?project=${var.project_id}"
}

output "bigquery_studio_console_url" {
  description = "Google Cloud Console URL for BigQuery Studio"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
}

output "notebook_subnet_id" {
  description = "ID of the subnetwork for notebook runtimes"
  value       = var.create_notebook_subnet ? google_compute_subnetwork.notebook_subnet[0].id : ""
}

output "notebook_subnet_name" {
  description = "Name of the subnetwork for notebook runtimes"
  value       = var.create_notebook_subnet ? google_compute_subnetwork.notebook_subnet[0].name : ""
}



