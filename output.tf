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

output "psc_subnet" {
  value = var.osd_gcp_psc ? google_compute_subnetwork.psc_subnet[0].name : null
}

# output "psc_google_apis_ip" {
#  value = var.osd_gcp_psc ? google_compute_global_address.psc_google_apis[0].address : null
#  description = "IP address for PSC Google APIs endpoint"
#}

output "bastion_vm_name" {
  value = var.enable_osd_gcp_bastion ? google_compute_instance.bastion[0].name : null
}

output "bastion_ip_external" {
  value = var.enable_osd_gcp_bastion ? google_compute_instance.bastion[0].network_interface[0].access_config[0].nat_ip : null
}

output "bastion_ip_internal" {
  value = var.enable_osd_gcp_bastion ? google_compute_instance.bastion[0].network_interface[0].network_ip : null
}

# Cluster access (requires OCM cluster to exist; run 'terraform refresh' if empty after first apply)
data "external" "cluster_info" {
  count = var.only_deploy_infra_no_osd ? 0 : 1
  program = ["bash", "${path.module}/scripts/get-cluster-urls.sh"]
  query = {
    cluster_name = var.clustername
  }
  depends_on = [shell_script.cluster_install]
}

output "cluster_api_url" {
  description = "OpenShift API URL for the cluster"
  value       = var.only_deploy_infra_no_osd ? null : data.external.cluster_info[0].result.api_url
}

output "cluster_console_url" {
  description = "OpenShift web console URL"
  value       = var.only_deploy_infra_no_osd ? null : data.external.cluster_info[0].result.console_url
}

output "cluster_admin_password" {
  description = "Admin user password (htpasswd)"
  value       = var.only_deploy_infra_no_osd ? null : var.osd_admin_password
  sensitive   = true
}