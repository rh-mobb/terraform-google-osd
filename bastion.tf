
# create ssh bastion firewall rules 
resource "google_compute_firewall" "bastion-fw-rules" {
  count   = var.enable_osd_gcp_bastion ? 1 : 0
  name    = "${var.clustername}-fw-allow-bastion"
  network = google_compute_network.vpc_network.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  // Allow traffic from everywhere to instances with an bastion tag
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.clustername}-bastion-vm"]
}

data "google_client_openid_userinfo" "me" {}

# Generate an bastion instance in the Bastion VPC subnet and install utils and ssh-keys 
resource "google_compute_instance" "bastion" {
  count        = var.enable_osd_gcp_bastion ? 1 : 0
  name         = "${var.clustername}-bastion-vm"
  machine_type = "e2-small"
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-stream-8"
    }
  }

  # TODO: Add Squid Server?
  metadata = {
    ssh-keys       = "${split("@", data.google_client_openid_userinfo.me.email)[0]}:${file(var.bastion_key_loc)}"
    startup-script = <<-EOF
    sudo dnf install telnet wget bash-completion -y
    wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
    tar -xvf openshift-client-linux.tar.gz
    sudo mv oc kubectl /usr/bin/
    oc completion bash > oc_bash_completion
    sudo cp oc_bash_completion /etc/bash_completion.d/
    now=$(date)
    echo "Finished at $now" >> /tmp/post-install-osd.txt
    EOF
  }

  network_interface {
    subnetwork = google_compute_subnetwork.vpc_subnetwork_bastion[0].id
    access_config {
    }
  }

  # Add labels

  tags = ["${var.clustername}-bastion-vm"]

  depends_on = [google_compute_firewall.bastion-fw-rules]
}
