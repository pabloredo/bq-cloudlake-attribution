terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

module "bq_showback" {
  source                            = "./modules/bq_showback"
  project_id                        = var.gcp_project_id
  location                          = var.gcp_region
  billing_account_id                = var.billing_account_id
  billing_dataset_id                = var.billing_dataset_id
  observability_dataset_id          = var.observability_dataset_id
  showback_dataset_id               = var.showback_dataset_id
  enable_billing_export_dataset_iam = var.enable_billing_export_dataset_iam
  create_attribution_view           = var.create_attribution_view
  upload_notebook                   = var.upload_notebook
  notebooks_bucket_name             = var.notebooks_bucket_name
  notebook_file_path                = "${path.module}/../notebooks/gcs_cost_showback_dataprep.ipynb"
  create_notebook_subnet            = var.create_notebook_subnet
  network_name                      = var.network_name
  notebook_subnet_name              = var.notebook_subnet_name
  notebook_subnet_cidr              = var.notebook_subnet_cidr
}

