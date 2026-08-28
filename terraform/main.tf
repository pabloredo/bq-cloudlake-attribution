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
}

