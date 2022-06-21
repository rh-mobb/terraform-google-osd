output "bastion_vm_name" {
  value = google_compute_instance.bastion[0].name
}

output "bastion_ip_external" {
  value = google_compute_instance.bastion[0].network_interface.0.access_config.0.nat_ip
}

output "bastion_ip_internal" {
  value = google_compute_instance.bastion[0].network_interface.0.network_ip
}



