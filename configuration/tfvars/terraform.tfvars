gcp_project = "mobb-demo"

clustername = "emea-osd-gcp"

vpc_routing_mode = "REGIONAL"

master_cidr_block = "10.0.0.0/17"

worker_cidr_block = "10.0.128.0/17"

bastion_cidr_block = "10.10.0.0/24"

gcp_region = "europe-west4"

gcp_zone = "europe-west4-a"

gcp_azs = [
  "us-west-1a",
  "us-west-1b",
  "us-west-1c"
]

enable_osd_gcp_bastion = false

osd_gcp_private = false

bastion_machine_type = "e2-small"

only_deploy_infra_no_osd = true
