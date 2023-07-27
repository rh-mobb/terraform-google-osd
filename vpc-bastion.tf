resource "google_compute_network" "vpc_network_bastion" {
  count                   = var.osd_gcp_private ? 1 : 0
  project                 = var.gcp_project
  name                    = "${var.clustername}-bastion-vpc"
  auto_create_subnetworks = false
  routing_mode            = var.vpc_routing_mode
}

resource "google_compute_subnetwork" "vpc_subnetwork_bastion" {
  count         = var.osd_gcp_private ? 1 : 0
  project       = var.gcp_project
  name          = "${var.clustername}-bastion-subnet"
  ip_cidr_range = var.bastion_cidr_block
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_network_peering" "peering_osd_to_bastion" {
  count                               = var.osd_gcp_private ? 1 : 0
  name                                = "${var.clustername}-peering-osd-to-bastion"
  network                             = google_compute_network.vpc_network.self_link
  peer_network                        = google_compute_network.vpc_network_bastion[0].self_link
  export_custom_routes                = true
  import_custom_routes                = true
  export_subnet_routes_with_public_ip = true
  import_subnet_routes_with_public_ip = true
}

resource "google_compute_network_peering" "peering_bastion_to_osd" {
  count                               = var.osd_gcp_private ? 1 : 0
  name                                = "${var.clustername}-peering-bastion-to-bastion"
  network                             = google_compute_network.vpc_network_bastion[0].self_link
  peer_network                        = google_compute_network.vpc_network.self_link
  export_custom_routes                = true
  import_custom_routes                = true
  export_subnet_routes_with_public_ip = true
  import_subnet_routes_with_public_ip = true
}
