resource "google_compute_network" "vpc_network" {
  count                   = var.osd_gcp_private ? 1 : 0
  project                 = var.gcp_project
  name                    = "${var.clustername}-bastion-vpc"
  auto_create_subnetworks = false
  routing_mode            = var.vpc_routing_mode
}

resource "google_compute_subnetwork" "vpc_subnetwork_masters" {
  count         = var.osd_gcp_private ? 1 : 0
  project       = var.gcp_project
  name          = "${var.clustername}-bastion-subnet"
  ip_cidr_range = var.master_cidr_block
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

# TODO Peerings and SSH