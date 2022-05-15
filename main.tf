terraform {
  backend "local" {}

  required_version = ">= 0.14"
}

provider "google" {
  region  = var.gcp_region
  project = var.gcp_project
}

resource "google_compute_network" "vpc_network" {
  project                 = var.gcp_project
  name                    = "${var.clustername}-vpc"
  auto_create_subnetworks = false
  routing_mode            = var.vpc_routing_mode
}

resource "google_compute_subnetwork" "vpc_subnetwork_masters" {
  project       = var.gcp_project
  name          = "${var.clustername}-master-subnet"
  ip_cidr_range = var.master_cidr_block
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
}
