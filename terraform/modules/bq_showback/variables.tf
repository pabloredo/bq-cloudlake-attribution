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
  default     = "billing_export_sim"
}

variable "observability_dataset_id" {
  description = "Dataset ID for client-side GCS I/O telemetry"
  type        = string
  default     = "billing_observability_dataset"
}

variable "showback_dataset_id" {
  description = "Dataset ID for final cost showback attribution"
  type        = string
  default     = "billing_showback_dataset"
}

variable "enable_billing_export_dataset_iam" {
  description = "Whether to grant roles/bigquery.dataEditor on the billing export dataset to Google Cloud Billing service account (billing-export-bigquery@system.gserviceaccount.com)"
  type        = bool
  default     = true
}

variable "create_attribution_view" {
  description = "Whether to create the dynamic showback view (vw_showback_cost_attribution). Set to true once the billing export table exists in BigQuery."
  type        = bool
  default     = false
}

variable "upload_notebook" {
  description = "Whether to upload the interactive data preparation notebook to GCS"
  type        = bool
  default     = true
}

variable "notebooks_bucket_name" {
  description = "Custom GCS bucket name for notebooks (defaults to <project_id>-lakehouse-notebooks if empty)"
  type        = string
  default     = ""
}

variable "notebook_file_path" {
  description = "Local path to the .ipynb notebook file to upload"
  type        = string
  default     = ""
}

variable "create_notebook_subnet" {
  description = "Whether to create a dedicated subnetwork for notebooks in the target region"
  type        = bool
  default     = true
}

variable "network_name" {
  description = "VPC network name to attach the subnetwork to (e.g. pablito-vpc or default)"
  type        = string
  default     = "default"
}

variable "notebook_subnet_name" {
  description = "Name of the subnetwork for notebook runtimes"
  type        = string
  default     = "lakehouse-notebook-subnet"
}

variable "notebook_subnet_cidr" {
  description = "CIDR range for the notebook subnetwork"
  type        = string
  default     = "10.3.0.0/24"
}


