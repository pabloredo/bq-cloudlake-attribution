variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "location" {
  description = "BigQuery Dataset Location"
  type        = string
  default     = "US"
}

variable "billing_account_id" {
  description = "GCP Billing Account ID (e.g. 01A2B3-C4D5E6-F78901) used to reference the standard Detailed Billing Export table"
  type        = string
  default     = "01A2B3-C4D5E6-F78901"
}

variable "billing_dataset_id" {
  description = "Dataset ID for GCP Detailed Billing Export (where Cloud Billing exports data or mock export is placed)"
  type        = string
}

variable "observability_dataset_id" {
  description = "Dataset ID for client-side GCS I/O telemetry"
  type        = string
}

variable "showback_dataset_id" {
  description = "Dataset ID for final cost showback attribution"
  type        = string
}

variable "enable_billing_export_dataset_iam" {
  description = "Whether to grant roles/bigquery.dataEditor on the billing export dataset to Google Cloud Billing service account (billing-export-bigquery@system.gserviceaccount.com)"
  type        = bool
  default     = true
}

