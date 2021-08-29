variable "project" {
  type        = string
  description = "Google Cloud project ID."
}

variable "zone" {
  type        = string
  description = "Google Cloud zone."

  validation {
    condition     = contains([
      "us-west1-a",
      "us-west1-b",
      "us-west1-c",
      "us-central1-a",
      "us-central1-b",
      "us-central1-c",
      "us-central1-f",
      "us-east1-b",
      "us-east1-c",
      "us-east1-d"
    ], var.zone)
    error_message = "Invalid GCP free tier zone."
  }
}

variable "instance_name" {
  type        = string
  description = "Compute Engine VM instance name."
}

variable "ipsec_identifier" {
  type        = string
  description = "IPSec identifier."
}

variable "hostname" {
  type        = string
  description = "Hostname."
}

variable "dyndns" {
  type        = object({
    server   = string
    user     = string
    password = string
  })
  description = "Dynamic DNS parameters."
  sensitive   = true
}

provider "google" {
  project = var.project
  region  = substr(var.zone, 0, length(var.zone) - 2)
  zone    = var.zone
}

resource "random_password" "psk" {
  length           = 32
  lower            = true
  upper            = true
  number           = true
  special          = true
  override_special = "+/"
}

locals {
  psk = random_password.psk.result
  ddclient = replace(
    replace(
      replace(
        replace(file("ddclient.conf"), "<server>", var.dyndns.server),
        "<user>", var.dyndns.user),
      "<password>", var.dyndns.password),
    "<hostname>", var.hostname
  )
  ikev2psk = replace(
    replace(file("ikev2-psk.conf"), "<ipsec_id>", var.ipsec_identifier),
      "<hostname>", var.hostname
  )
}

resource "google_compute_firewall" "vpn" {
  name        = "allow-isakmp-ipsec-nat-t"
  network     = "default"
  target_tags = ["vpn-server"]

  allow {
    protocol = "udp"
    ports    = ["500", "4500"]
  }
}

resource "google_compute_instance" "vpn" {
  name                    = var.instance_name
  machine_type            = "e2-micro"
  can_ip_forward          = true
  tags                    = ["vpn-server"]
  metadata                = {
    "user-data"       = replace(
      replace(
        replace(
          replace(
            replace(
              file("config.yaml"),
              "<nftables.sh>",
              base64encode(file("nftables.sh"))),
            "<ddclient.conf>", base64encode(local.ddclient)
          ), "<ipsec_id>", var.ipsec_identifier
        ), "<ikev2-psk.conf>", base64encode(local.ikev2psk)
      ),
      "<ikev2-psk.secrets>",
      base64encode(
        "@${var.ipsec_identifier} @${var.hostname}: PSK \"${local.psk}\""
      )
    )
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-minimal-2004-lts"
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }

  shielded_instance_config {
      enable_vtpm                 = true
      enable_integrity_monitoring = true
  }
}

output "server_address" {
  value       = var.hostname
  description = "Server address."
}

output "ipsec_identifier" {
  value       = var.ipsec_identifier
  description = "IPSec identifier."
}

output "ipsec_pre_shared_key" {
  value       = local.psk
  description = "IPSec pre-shared key."
}