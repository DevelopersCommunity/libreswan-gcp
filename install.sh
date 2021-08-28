#!/bin/bash
#
# Install and configure IKEv2/IPSec PSK VPN server components.

#######################################
# Print out error messages.
# Globals:
#   None
# Arguments:
#   Error message
# Outputs:
#   Formatted error message
#######################################
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Retrieve VM instance metadata.
# Globals:
#   None
# Arguments:
#   Metadata key
# Outputs:
#   Metadata value
#######################################
read_metadata() {
  readonly API_PREFIX=\
"http://metadata.google.internal/computeMetadata/v1/instance/attributes/"
  local md
  if ! md="$(curl -s ${API_PREFIX}"$1" -H "Metadata-Flavor: Google")"; then
    err "Unable to read metadata $1"
    exit 1
  fi
  echo "$md"
}

#######################################
# Enable IP forward.
# Globals:
#   None
# Arguments:
#   /etc/sysctl.conf file content
#######################################
enable_ip_forward() {
  echo "${1/\#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1}" > /etc/sysctl.conf
  sysctl -w net.ipv4.ip_forward=1
}

#######################################
# Install and configure Librewan.
# Globals:
#   None
# Arguments:
#   None
#######################################
configure_libreswan() {
  local dd_hostname
  dd_hostname=$(read_metadata "dyndnshostname")
  local ipsec_id
  ipsec_id=$(read_metadata "ipsecidentifier")
  cat <<END > "/etc/ipsec.d/ikev2-psk-${ipsec_id}.conf"
conn ikev2-psk-${ipsec_id}
	authby=secret
	left=%defaultroute
	leftid=@$(read_metadata "dyndnshostname")
	leftsubnet=0.0.0.0/0
	# Clients
	right=%any
	# your addresspool to use
	# you might need NAT rules if providing full internet to clients
	rightaddresspool=192.168.66.1-192.168.66.254
	rightid=@${ipsec_id}
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
END

    cat <<END > /etc/ipsec.d/ikev2-psk.secrets
@${ipsec_id} @${dd_hostname}: PSK "$(read_metadata "psk")"
END
  chmod 600 /etc/ipsec.d/ikev2-psk.secrets

  systemctl enable ipsec.service
  systemctl start ipsec.service
}

#######################################
# Install and configure nftables.
# Globals:
#   None
# Arguments:
#   None
#######################################
configure_nftables() {
  local route
  route=$(ip route show to default)
  local dev
  dev="${route#default via +([0-9.]) dev+([[:space:]])}"
  dev="${dev%%+([[:space:]])*}"
  cat <<END >> /etc/nftables.conf
table ip nat {
	chain postrouting {
		type nat hook postrouting priority 100; policy accept;
		ip saddr 192.168.66.0/24 oif "${dev}" masquerade
	}
}
END

  systemctl enable nftables.service
  systemctl start nftables.service
}

#######################################
# Install and configure DDclient.
# Globals:
#   None
# Arguments:
#   None
#######################################
configure_ddclient() {
  cat <<END > /etc/ddclient.conf
protocol=dyndns2
use=web
server=$(read_metadata "dyndnsserver")
ssl=yes
login=$(read_metadata "dyndnsuser")
password='$(read_metadata "dyndnspassword")'
$(read_metadata "dyndnshostname")
END

  systemctl restart ddclient.service
}

#######################################
# VM startup script entrypoint.
# Globals:
#   None
# Arguments:
#   None
#######################################
main() {
  shopt -q extglob
  declare -r extglob_unset=$?
  (( extglob_unset )) && shopt -s extglob

  local sysctl_conf
  sysctl_conf=$(cat /etc/sysctl.conf)
  [[ "$sysctl_conf" =~ .*^#net.ipv4.ip_forward=1$.* ]] \
    && enable_ip_forward "$sysctl_conf"

  configure_libreswan
  configure_nftables
  configure_ddclient

  (( extglob_unset )) && shopt -u extglob
}

main "$@"
