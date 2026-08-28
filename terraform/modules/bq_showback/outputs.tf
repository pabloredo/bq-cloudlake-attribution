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
