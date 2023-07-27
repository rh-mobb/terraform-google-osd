terraform {
  backend "local" {}

  required_version = ">= 0.14"
  required_providers {
    shell = {
      source  = "scottwinkler/shell"
      version = "1.7.10"
    }
  }
}

provider "google" {
  region  = var.gcp_region
  project = var.gcp_project
}

resource "shell_script" "cluster_install" {
  count = var.only_deploy_infra_no_osd ? 0 : 1

  # As currently we do not have a osdongcp_redhatopenshift_cluster style resource, this handles
  # the installation of the cluster after terraform has finished. Improvement for the future!

  lifecycle_commands {
    create = templatefile(
      "${path.module}/templates/clusterinstall.tftpl",
      {
        cluster_name         = var.clustername
        vpc_name             = google_compute_network.vpc_network.name
        control_plane_subnet = google_compute_subnetwork.vpc_subnetwork_masters.name
        compute_subnet       = google_compute_subnetwork.vpc_subnetwork_workers.name
        gcp_region           = var.gcp_region
        gcp_sa_file_loc      = var.gcp_sa_file_loc
    })
    delete = templatefile(
      "${path.module}/templates/clusterdestroy.tftpl",
      {
        cluster_name         = var.clustername
        vpc_name             = google_compute_network.vpc_network.name
        control_plane_subnet = google_compute_subnetwork.vpc_subnetwork_masters.name
        compute_subnet       = google_compute_subnetwork.vpc_subnetwork_workers.name
        gcp_region           = var.gcp_region
        gcp_sa_file_loc      = var.gcp_sa_file_loc
    })
  }

  depends_on = [
    google_compute_router_nat.nat-master
  ]
}
