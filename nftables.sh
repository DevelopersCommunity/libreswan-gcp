#!/bin/bash
#
# Configure masquerade NAT.

#######################################
# Configure nftables.
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

  configure_nftables

  (( extglob_unset )) && shopt -u extglob
}

main "$@"
