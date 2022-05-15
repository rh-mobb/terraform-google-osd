gcp_project = "mobb-demo"

clustername = "mobb-osd"

vpc_routing_mode = "REGIONAL"

master_cidr_block = "10.0.0.0/17"

worker_cidr_block = "10.0.128.0/17"


gcp_extra_tags = {
  "owner" = "mobb-team"
}
gcp_azs = [
  "us-west-1a",
  "us-west-1b",
  "us-west-1c"
]

gcp_region = "us-west-1"
