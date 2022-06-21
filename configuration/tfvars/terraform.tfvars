gcp_project = "mobb-demo"

clustername = "mobb-osd"

vpc_routing_mode = "REGIONAL"

master_cidr_block = "10.0.0.0/17"

worker_cidr_block = "10.0.128.0/17"

bastion_cidr_block = "10.10.0.0/24"

gcp_region = "us-west1"

gcp_zone = "us-west1-a"

enable_osd_gcp_bastion = true

osd_gcp_private = true

bastion_machine_type = "e2-small"

