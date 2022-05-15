variable "gcp_region" {
  type        = string
  description = "The target GCP region for the cluster."
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
  type = string

  description = "The name of the cluster."

}

