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
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "vpc_subnetwork_workers" {
  project       = var.gcp_project
  name          = "${var.clustername}-worker-subnet"
  ip_cidr_range = var.worker_cidr_block
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_router" "router" {
  project = var.gcp_project
  name    = "${var.clustername}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc_network.id

}

resource "google_compute_router_nat" "nat-master" {
  name                               = "${var.clustername}-nat-master"
  router                             = google_compute_router.router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.vpc_subnetwork_masters.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  min_ports_per_vm                    = "7168"
  enable_endpoint_independent_mapping = false

}

resource "google_compute_router_nat" "nat-worker" {
  name                               = "${var.clustername}-nat-worker"
  router                             = google_compute_router.router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.vpc_subnetwork_workers.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  min_ports_per_vm                    = "4096"
  enable_endpoint_independent_mapping = false

}
