output "bastion_vm_name" {
  value = var.osd_gcp_private ? google_compute_instance.bastion[0].name : null
}

output "bastion_ip_external" {
  value = var.osd_gcp_private ? google_compute_instance.bastion[0].network_interface.0.access_config.0.nat_ip : null
}

output "bastion_ip_internal" {
  value = var.osd_gcp_private ? google_compute_instance.bastion[0].network_interface.0.network_ip : null
}

output "vpc_name" {
  value = google_compute_network.vpc_network.name
}

output "control_plane_subnet" {
  value = google_compute_subnetwork.vpc_subnetwork_masters.name
}

output "compute_subnet" {
  value = google_compute_subnetwork.vpc_subnetwork_workers.name
}

output "gcp_region" {
  value = var.gcp_region
}
