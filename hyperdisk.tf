# Hyperdisk Balanced storage pool for OpenShift Virtualization VM disk images.
# Must be in the same zone as C3 metal compute nodes. RWX across zones is not supported.
#
# The pool is used by an OpenShift StorageClass (see scripts/install-hyperdisk-storageclass.sh)
# that provisions volumes for VM disks via pd.csi.storage.gke.io.

locals {
  effective_compute_machine_type = (
    var.compute_machine_type != "" ? var.compute_machine_type :
    var.enable_openshift_virt ? "c3-standard-192-metal" : ""
  )
}

variable "enable_openshift_virt" {
  description = "Enable OpenShift Virtualization - creates Hyperdisk Balanced storage pool for VM disk images"
  type        = bool
  default     = false
}

variable "hyperdisk_pool_capacity_gb" {
  description = "Provisioned capacity for Hyperdisk Balanced storage pool (GiB). GCP minimum is 10240 (10 TiB)."
  type        = number
  default     = 10240

  validation {
    condition     = var.hyperdisk_pool_capacity_gb >= 10240
    error_message = "hyperdisk_pool_capacity_gb must be at least 10240 GiB (10 TiB) per GCP requirements."
  }
}

variable "hyperdisk_pool_iops" {
  description = "Provisioned IOPS for Hyperdisk Balanced storage pool"
  type        = number
  default     = 10000
}

variable "hyperdisk_pool_throughput_mbps" {
  description = "Provisioned throughput for Hyperdisk Balanced storage pool (MB/s)"
  type        = number
  default     = 1024
}

resource "google_compute_storage_pool" "hyperdisk_balanced" {
  count = var.enable_openshift_virt ? 1 : 0

  name                  = "${var.clustername}-virt-pool"
  zone                  = var.gcp_zone
  deletion_protection   = false
  storage_pool_type     = "hyperdisk-balanced"
  pool_provisioned_capacity_gb  = var.hyperdisk_pool_capacity_gb
  pool_provisioned_iops         = var.hyperdisk_pool_iops
  pool_provisioned_throughput   = var.hyperdisk_pool_throughput_mbps
  capacity_provisioning_type   = "ADVANCED"
  performance_provisioning_type = "ADVANCED"
}

output "hyperdisk_pool_resource_path" {
  description = "Full resource path for the Hyperdisk storage pool (for StorageClass storage-pools parameter)"
  value       = var.enable_openshift_virt ? "projects/${var.gcp_project}/zones/${var.gcp_zone}/storagePools/${google_compute_storage_pool.hyperdisk_balanced[0].name}" : null
}
