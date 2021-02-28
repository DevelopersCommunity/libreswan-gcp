#!/bin/bash
#
# VM startup script - https://cloud.google.com/compute/docs/startupscript
# Install and configure IKEv2/IPSec PSK VPN server components.

read_metadata() {
  declare -r api_prefix=\
"http://metadata.google.internal/computeMetadata/v1/instance/attributes/"
  echo $(curl -s ${api_prefix}${1} -H "Metadata-Flavor: Google")
}

enable_ip_forward() {
  echo "${1/\#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1}" > \
    /etc/sysctl.conf
  sysctl -w net.ipv4.ip_forward=1
}

configure_libreswan() {
  apt-get -y install libreswan

  declare -r snet="$(read_metadata "subnet")"
  sed -i \
    "/^\s*virtual_private=/s/$/,%v4:\!${snet/\//\\\/},%v4:\!192.168.66.0\/24/" \
    /etc/ipsec.conf

  declare -r public_fqdn="$(read_metadata "publicfqdn")"
  declare -r ipsec_id="$(read_metadata "ipsecidentifier")"
  cat <<EOF > /etc/ipsec.d/ikev2-psk.conf
conn ikev2-psk
	authby=secret
	left=%defaultroute
	leftid=@$public_fqdn
	leftsubnet=0.0.0.0/0
	# Clients
	right=%any
	# your addresspool to use - you might need NAT rules if providing full internet to clients
	rightaddresspool=192.168.66.1-192.168.66.254
	rightid=@$ipsec_id
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
EOF

    declare -r psk="$(read_metadata "psk")"
    cat <<EOF > /etc/ipsec.d/ikev2-psk.secrets
: PSK "${psk}"
EOF
  chmod 600 /etc/ipsec.d/ikev2-psk.secrets

  systemctl enable ipsec.service
  systemctl start ipsec.service
}

configure_nftables() {
  apt-get -y install nftables
  declare -r route="$(ip route show to default)"
  local dev="${route#default via*dev }"
  dev="${dev% }"

  cat <<EOF >> /etc/nftables.conf

table ip nat {
	chain postrouting {
		type nat hook postrouting priority 100; policy accept;
		ip saddr 192.168.66.0/24 oif "${dev}" masquerade
	}
}
EOF

  systemctl enable nftables.service
  systemctl start nftables.service
}

configure_ddclient() {
  DEBIAN_FRONTEND=noninteractive apt-get -y install ddclient

  declare -r public_fqdn="$(read_metadata "publicfqdn")"
  declare -r dd_server="$(read_metadata "dyndnsserver")"
  declare -r dd_user="$(read_metadata "dyndnsuser")"
  declare -r dd_password="$(read_metadata "dyndnspassword")"
  cat <<EOF > /etc/ddclient.conf
protocol=dyndns2
use=web
server=${dd_server}
ssl=yes
login=${dd_user}
password='${dd_password}'
${public_fqdn}
EOF

  systemctl restart ddclient.service
}

main() {
  declare -r sysctl_conf=$(cat /etc/sysctl.conf)
  if [[ "$sysctl_conf" =~ .*^#net.ipv4.ip_forward=1$.* ]]; then
    enable_ip_forward "$sysctl_conf"
  fi

  declare -r packages=$(dpkg --get-selections)

  if [[ ! "$packages" =~ .*^libreswan[[:space:]]+install$.* ]]; then
    configure_libreswan
  fi

  if [[ ! "$packages" =~ .*^nftables[[:space:]]+install$.* ]]; then
    configure_nftables
  fi

  if [[ ! "$packages" =~ .*^ddclient[[:space:]]+install$.* ]]; then
    configure_ddclient
  fi
}

main "$@"
