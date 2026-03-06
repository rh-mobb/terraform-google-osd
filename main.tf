terraform {
  backend "local" {}

  required_version = ">= 0.14"
  required_providers {
    shell = {
      source  = "Ninlives/shell"
      version = "~> 1.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.2"
    }
  }
}

provider "google" {
  region  = var.gcp_region
  project = var.gcp_project
}

resource "shell_script" "cluster_install" {
  count = var.only_deploy_infra_no_osd ? 0 : 1

  lifecycle_commands {
    create = file("${path.module}/scripts/clusterinstall.sh")
    delete = file("${path.module}/scripts/clusterdestroy.sh")
  }

  environment = {
    CLUSTER_NAME             = var.clustername
    OSD_VERSION              = var.osd_version
    VPC_NAME                 = google_compute_network.vpc_network.name
    CONTROL_PLANE_SUBNET     = google_compute_subnetwork.vpc_subnetwork_masters.name
    COMPUTE_SUBNET           = google_compute_subnetwork.vpc_subnetwork_workers.name
    GCP_REGION               = var.gcp_region
    GCP_ZONE                 = var.gcp_zone
    GCP_PROJECT              = var.gcp_project
    GCP_SA_FILE_LOC          = var.gcp_sa_file_loc
    GCP_AUTHENTICATION_TYPE  = var.gcp_authentication_type
    WIF_CONFIG_NAME          = "${var.clustername}-wif"
    OSD_GCP_PRIVATE          = tostring(var.osd_gcp_private)
    OSD_GCP_PSC              = tostring(var.osd_gcp_psc)
    PSC_SUBNET_NAME          = var.osd_gcp_psc ? google_compute_subnetwork.psc_subnet[0].name : ""
    COMPUTE_MACHINE_TYPE     = local.effective_compute_machine_type
  }

  working_directory = path.module
  interpreter       = ["/bin/bash", "-c"]

  depends_on = [
    google_compute_router_nat.nat-master,
    shell_script.wif_create,
    google_compute_global_forwarding_rule.psc_google_apis,
    google_dns_record_set.psc_googleapis_a
  ]
}

resource "shell_script" "htpasswd_admin" {
  count = var.only_deploy_infra_no_osd ? 0 : 1

  lifecycle_commands {
    create = file("${path.module}/scripts/create-htpasswd-admin.sh")
    delete = file("${path.module}/scripts/htpasswd-destroy-noop.sh")
  }

  environment = {
    CLUSTER_NAME = var.clustername
  }

  sensitive_environment = {
    OSD_ADMIN_PASSWORD = var.osd_admin_password
  }

  working_directory = path.module
  interpreter       = ["/bin/bash", "-c"]

  depends_on = [shell_script.cluster_install]
}

resource "shell_script" "oc_login" {
  count = var.only_deploy_infra_no_osd ? 0 : 1

  lifecycle_commands {
    create = file("${path.module}/scripts/oc-login-admin.sh")
    delete = file("${path.module}/scripts/htpasswd-destroy-noop.sh")
  }

  environment = {
    CLUSTER_NAME = var.clustername
  }

  sensitive_environment = {
    OSD_ADMIN_PASSWORD = var.osd_admin_password
  }

  working_directory = path.module
  interpreter       = ["/bin/bash", "-c"]

  depends_on = [shell_script.htpasswd_admin]
}

resource "shell_script" "install_openshift_virt" {
  count = var.only_deploy_infra_no_osd || !var.enable_openshift_virt ? 0 : 1

  lifecycle_commands {
    create = file("${path.module}/scripts/install-openshift-virt.sh")
    delete = file("${path.module}/scripts/htpasswd-destroy-noop.sh")
  }

  working_directory = path.module
  interpreter       = ["/bin/bash", "-c"]

  depends_on = [shell_script.oc_login, shell_script.install_hyperdisk_storageclass]
}

resource "shell_script" "install_hyperdisk_storageclass" {
  count = var.only_deploy_infra_no_osd || !var.enable_openshift_virt ? 0 : 1

  lifecycle_commands {
    create = file("${path.module}/scripts/install-hyperdisk-storageclass.sh")
    delete = file("${path.module}/scripts/htpasswd-destroy-noop.sh")
  }

  environment = {
    STORAGE_POOL_PATH = "projects/${var.gcp_project}/zones/${var.gcp_zone}/storagePools/${var.clustername}-virt-pool"
  }

  working_directory = path.module
  interpreter       = ["/bin/bash", "-c"]

  depends_on = [shell_script.oc_login, google_compute_storage_pool.hyperdisk_balanced]
}

resource "shell_script" "wif_create" {
  count = var.gcp_authentication_type == "workload_identity_federation" ? 1 : 0

  lifecycle_commands {
    create = file("${path.module}/scripts/wifcreate.sh")
    delete = file("${path.module}/scripts/wifdelete.sh")
    read   = file("${path.module}/scripts/wifread.sh")
  }

  environment = {
    WIF_CONFIG_NAME = "${var.clustername}-wif"
    GCP_PROJECT     = var.gcp_project
  }

  working_directory = path.module
  interpreter       = ["/bin/bash", "-c"]
}
