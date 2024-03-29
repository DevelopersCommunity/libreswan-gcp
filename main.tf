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
  ddclientconf = <<-EOT
  # Configuration file for ddclient
  #
  # /etc/ddclient.conf

  protocol=dyndns2
  use=web
  server=${var.dyndns.server}
  ssl=yes
  login=${var.dyndns.user}
  password='${var.dyndns.password}'
  ${var.hostname}
  EOT

  ddclient = <<-EOT
  # Configuration for ddclient scripts
  #
  # /etc/default/ddclient

  # Set to "true" if ddclient should be run every time DHCP client ('dhclient'
  # from package isc-dhcp-client) updates the systems IP address.
  run_dhclient="false"

  # Set to "true" if ddclient should be run every time a new ppp connection is
  # established. This might be useful, if you are using dial-on-demand.
  run_ipup="false"

  # Set to "true" if ddclient should run in daemon mode
  # If this is changed to true, run_ipup and run_dhclient must be set to false.
  run_daemon="true"

  # Set the time interval between the updates of the dynamic DNS name in
  # seconds.
  # This option only takes effect if the ddclient runs in daemon mode.
  daemon_interval="300"
  EOT

  ikev2psk = <<-EOT
  conn ikev2-psk-${var.ipsec_identifier}
    authby=secret
    left=%defaultroute
    leftid=@${var.hostname}
    leftsubnet=0.0.0.0/0
    # Clients
    right=%any
    # your addresspool to use
    # you might need NAT rules if providing full internet to clients
    rightaddresspool=192.168.66.1-192.168.66.254
    rightid=@${var.ipsec_identifier}
    #
    # connection configuration
    # DNS servers for clients to use
    modecfgdns=8.8.8.8,8.8.4.4
    narrowing=yes
    # recommended dpd/liveness to cleanup vanished clients
    dpddelay=30
    dpdtimeout=120
    dpdaction=clear
    auto=add
    ikev2=insist
    rekey=no
    # ikev2 fragmentation support requires libreswan 3.14 or newer
    fragmentation=yes
    # optional PAM username verification (eg to implement bandwidth quota
    # pam-authorize=yes
    ike=aes_gcm-aes_xcbc,aes_cbc-sha2
  EOT

  config = <<-EOT
  #cloud-config

  packages:
    - libreswan
    - nftables
    - firewalld
    - ddclient
  package_update: true
  package_upgrade: true
  package_reboot_if_required: true

  write_files:
    - encoding: b64
      content: ${base64encode(local.ddclientconf)}
      owner: root:root
      path: /etc/ddclient.conf
      permissions: '0600'
    - encoding: b64
      content: ${base64encode(local.ddclient)}
      owner: root:root
      path: /etc/default/ddclient
      permissions: '0600'
    - encoding: b64
      content: ${base64encode(local.ikev2psk)}
      owner: root:root
      path: /etc/ipsec.d/ikev2-psk-${var.ipsec_identifier}.conf
    - encoding: b64
      content: ${
        base64encode(
          format(
            "@${var.ipsec_identifier} @${var.hostname}: PSK \"%s\"",
            random_password.psk.result
          )
        )
      }
      owner: root:root
      path: /etc/ipsec.d/ikev2-psk.secrets
      permissions: '0600'

  runcmd:
    - [ sed,
      -i,
      "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g",
      /etc/sysctl.conf ]
    - [ sysctl, -w, net.ipv4.ip_forward=1 ]
    - [ systemctl, enable, ipsec.service ]
    - [ systemctl, start, ipsec.service ]
    - [ systemctl, restart, ddclient.service ]
    - [ sed,
      -i,
      "s/FirewallBackend=iptables/FirewallBackend=nftables/g",
      /etc/firewalld/firewalld.conf ]
    - [ systemctl, restart, firewalld.service ]
    - firewall-cmd --zone=external
      --change-interface="$(ip route show to default | awk '{printf $5}')"
      --permanent
    - [ firewall-cmd,
      --zone=external,
      --add-port=500/udp,
      --add-port=4500/udp,
      --permanent ]
    - [ firewall-cmd,
      --zone=external,
      --add-source=192.168.66.0/24,
      --permanent ]
    - [ firewall-cmd, --reload ]
  EOT
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
    "user-data" = local.config
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