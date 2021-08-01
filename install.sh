#!/bin/bash
#
# VM startup script - https://cloud.google.com/compute/docs/startupscript
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
  declare -r api_prefix=\
"http://metadata.google.internal/computeMetadata/v1/instance/attributes/"
  local metadata
  metadata="$(curl -s ${api_prefix}$1 -H "Metadata-Flavor: Google")"
  if (( $? != 0 )); then
    err "Unable to read metadata $1"
    exit 1
  fi
  echo "$metadata"
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
  if ! apt-get -y install libreswan; then
    err "Unable to install libreswan"
    exit 1
  fi

  declare -r ipsec_conf=$(cat /etc/ipsec.conf)
  local vp
  vp="${ipsec_conf#"${ipsec_conf%%virtual_private=*}"}"
  vp="${vp%%[[:cntrl:]]*}"
  declare -r subnet="$(read_metadata "subnet")"
  declare -r new_vp="${vp},%v4:"'!'"${subnet},%v4:"'!192.168.66.0/24'
  echo "${ipsec_conf/${vp}/${new_vp}}" > /etc/ipsec.conf

  declare -r dd_hostname="$(read_metadata "dyndnshostname")"
  declare -r ipsec_id="$(read_metadata "ipsecidentifier")"
  cat <<END > "/etc/ipsec.d/ikev2-psk-${ipsec_id}.conf"
conn ikev2-psk-${ipsec_id}
	authby=secret
	left=%defaultroute
	leftid=@${dd_hostname}
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

    declare -r psk="$(read_metadata "psk")"
    cat <<END > /etc/ipsec.d/ikev2-psk.secrets
@${ipsec_id} @${dd_hostname}: PSK "${psk}"
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
  if ! apt-get -y install nftables; then
    err "Unable to install nftables"
    exit 1
  fi

  declare -r route="$(ip route show to default)"
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
  if ! DEBIAN_FRONTEND=noninteractive apt-get -y install ddclient; then
    err "Unable to install ddclient"
    exit 1
  fi

  declare -r dd_hostname="$(read_metadata "dyndnshostname")"
  declare -r dd_server="$(read_metadata "dyndnsserver")"
  declare -r dd_user="$(read_metadata "dyndnsuser")"
  declare -r dd_password="$(read_metadata "dyndnspassword")"
  cat <<END > /etc/ddclient.conf
protocol=dyndns2
use=web
server=${dd_server}
ssl=yes
login=${dd_user}
password='${dd_password}'
${dd_hostname}
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

  declare -r sysctl_conf=$(cat /etc/sysctl.conf)
  [[ "$sysctl_conf" =~ .*^#net.ipv4.ip_forward=1$.* ]] \
    && enable_ip_forward "$sysctl_conf"

  declare -r packages=$(dpkg --get-selections)

  # powermgmt-base and python3-gi are used by unattended-upgrades
  [[ ! "$packages" =~ .*^powermgmt-base[[:space:]]+install$.* ]] \
    && apt-get install -y powermgmt-base
  [[ ! "$packages" =~ .*^python3-gi[[:space:]]+install$.* ]] \
    && apt-get install -y python3-gi

  [[ ! "$packages" =~ .*^libreswan[[:space:]]+install$.* ]] \
    && configure_libreswan
  [[ ! "$packages" =~ .*^nftables[[:space:]]+install$.* ]] \
    && configure_nftables
  [[ ! "$packages" =~ .*^ddclient[[:space:]]+install$.* ]] \
    && configure_ddclient

  (( extglob_unset )) && shopt -u extglob
}

main "$@"
