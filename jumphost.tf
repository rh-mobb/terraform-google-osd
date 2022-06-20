resource "google_compute_instance" "bastion" {
  count        = var.enable_osd_gcp_bastion ? 1 : 0
  name         = "${var.clustername}-bastion-vm"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  disk {
    image = "centos-stream-8-v20220519"
  }

  # Local SSD disk
  disk {
    type    = "local-ssd"
    scratch = true
  }

  network_interface {
    network = google_compute_network.vpc_network.id
    access_config {}
  }

  tags = {
    Name = "${local.name}-bastion"
  }
}

# TODO: Install utils and ocp
