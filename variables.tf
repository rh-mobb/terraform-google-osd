variable "gcp_region" {
  type        = string
  description = "The target GCP region for the cluster."
}

variable "gcp_region" {
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
