terraform {
  backend "local" {}

  required_version = ">= 0.14"
}

provider "google" {
  region  = var.gcp_region
  project = var.gcp_project
}
