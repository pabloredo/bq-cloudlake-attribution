variable "gcp_project_id" {
  description = "The GCP Project ID where BigQuery datasets and tables will be deployed."
  type        = string
  default     = "my-gcp-project-id"
}

variable "gcp_region" {
  description = "The default GCP region / location for BigQuery datasets (e.g. US, EU, us-central1)."
  type        = string
  default     = "US"
}

variable "billing_account_id" {
  description = "The GCP Billing Account ID (format: 012345-56789A-ABCDEF). Used to reference or simulate the standard export table name (gcp_billing_export_resource_v1_<BILLING_ACCOUNT_ID>)."
  type        = string
  default     = "01A2B3-C4D5E6-F78901"
}

variable "billing_dataset_id" {
  description = "Dataset ID for GCP Detailed Billing Export (where Cloud Billing exports data or mock export is placed)."
  type        = string
  default     = "billing_export_sim"
}

variable "observability_dataset_id" {
  description = "Dataset ID for client-side aggregated GCS I/O telemetry."
  type        = string
  default     = "billing_observability_dataset"
}

variable "showback_dataset_id" {
  description = "Dataset ID for final cost showback attribution tables and views."
  type        = string
  default     = "billing_showback_dataset"
}

variable "enable_billing_export_dataset_iam" {
  description = "Whether to grant roles/bigquery.dataEditor on the billing export dataset to the Google Cloud Billing service account (billing-export-bigquery@system.gserviceaccount.com)."
  type        = bool
  default     = true
}

variable "create_attribution_view" {
  description = "Whether to create the dynamic showback view (vw_showback_cost_attribution). Set to true once the billing export table exists in BigQuery (via Cloud Billing export or synthetic data)."
  type        = bool
  default     = false
}

variable "upload_notebook" {
  description = "Whether to upload the interactive data preparation notebook to Google Cloud Storage."
  type        = bool
  default     = true
}

variable "notebooks_bucket_name" {
  description = "Custom GCS bucket name for notebooks (defaults to <project_id>-lakehouse-notebooks if empty)."
  type        = string
  default     = ""
}

variable "create_notebook_subnet" {
  description = "Whether to create a dedicated subnetwork for notebooks in the target region."
  type        = bool
  default     = true
}

variable "network_name" {
  description = "VPC network name to attach the notebook subnetwork to (e.g. pablito-vpc or default)."
  type        = string
  default     = "pablito-vpc"
}

variable "notebook_subnet_name" {
  description = "Name of the subnetwork for notebook runtimes."
  type        = string
  default     = "lakehouse-notebook-subnet"
}

variable "notebook_subnet_cidr" {
  description = "CIDR range for the notebook subnetwork."
  type        = string
  default     = "10.3.0.0/24"
}



