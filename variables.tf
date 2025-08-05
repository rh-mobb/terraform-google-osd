variable "gcp_region" {
  type        = string
  description = "The target GCP region for the cluster."
}

variable "gcp_zone" {
  type        = string
  description = "The target GCP zone for the cluster."
}

variable "gcp_project" {
  type        = string
  description = "The target GCP project for the cluster."
}

variable "vpc_routing_mode" {
  type        = string
  description = "The network-wide routing mode to use."
}

variable "clustername" {
  type        = string
  description = "The name of the cluster."

}

variable "master_cidr_block" {
  type        = string
  description = <<EOF
The IP address space from which to assign machine IPs.
Default "10.0.0.0/17"
EOF
  default     = "10.0.0.0/17"
}

variable "worker_cidr_block" {
  type        = string
  description = <<EOF
The IP address space from which to assign machine IPs.
Default "10.0.128.0/17"
EOF
  default     = "10.0.128.0/17"
}

variable "bastion_cidr_block" {
  type        = string
  description = <<EOF
The IP address space from which to deploy the bastion / jumphost.
Default "10.0.128.0/17"
EOF
  default     = "10.0.128.0/17"
}

variable "enable_osd_gcp_bastion" {
  description = <<EOF
If set to true, deploy a bastion in the OSD in GCP private subnet. 
Variable osd_gcp_private needs to be enabled."
EOF
  type        = bool
  default     = false
}

variable "osd_gcp_private" {
  description = "If set to true, deploy a second vpc/network for a OSD in GCP private install"
  type        = bool
  default     = false
}

variable "bastion_machine_type" {
  type        = string
  description = <<EOF
The Machine Type from for our Bastion.
Default "e2-micro"
EOF
  default     = "e2-micro"
}

variable "bastion_key_loc" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Public key for bastion host"
}

variable "gcp_sa_file_loc" {
  type        = string
  default     = "~/.ssh/id_rsa_sa.json"
  description = "Path to private json for OSD on GCP Admin Service Account"
}

variable "only_deploy_infra_no_osd" {
  description = "If set to true, only the networking infra will be deployed, not the OSD in GCP cluster"
  type        = bool
  default     = false
}

variable "gcp_authentication_type" {
  description = "How the installer and cluster should authenticate with GCP. Either 'service_account' or 'workload_identity_federation'"
  type        = string
  default     = "service_account"
  validation {
    condition     = contains(["service_account", "workload_identity_federation"], var.gcp_authentication_type)
    error_message = "Valid values for gcp_authentication_type are either 'service_account' or workload_identity_federation'."
  }
}
