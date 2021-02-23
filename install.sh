#! /bin/bash

if grep -i '^#net.ipv4.ip_forward=1$' /etc/sysctl.conf; then
	sed -i '/^#net\.ipv4\.ip_forward=1$/s/^#//' /etc/sysctl.conf
	sysctl -w net.ipv4.ip_forward=1
fi

if ! dpkg --get-selections | grep -q '^libreswan\s\+install$'; then
	apt-get -y install libreswan

	subnet=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/subnet -H "Metadata-Flavor: Google")
	sed -i '/^\s*virtual_private=/s/$/'",%v4:\!$(echo $subnet | sed 's/\//\\\//'),%v4:\!192.168.66.0\/24"'/' /etc/ipsec.conf

	publicfqdn=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/publicfqdn -H "Metadata-Flavor: Google")
	ipsecidentifier=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/ipsecidentifier -H "Metadata-Flavor: Google")
	cat <<EOF > /etc/ipsec.d/ikev2-psk.conf
conn ikev2-psk
	authby=secret
	left=%defaultroute
	leftid=@$publicfqdn
	leftsubnet=0.0.0.0/0
	# Clients
	right=%any
	# your addresspool to use - you might need NAT rules if providing full internet to clients
	rightaddresspool=192.168.66.1-192.168.66.254
	rightid=@$ipsecidentifier
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

	psk=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/psk -H "Metadata-Flavor: Google")
	cat <<EOF > /etc/ipsec.d/ikev2-psk.secrets
: PSK "$psk"
EOF
	chmod 600 /etc/ipsec.d/ikev2-psk.secrets

	systemctl enable ipsec.service
	systemctl start ipsec.service
fi

if ! dpkg --get-selections | grep -q '^nftables\s\+install$'; then
	apt-get -y install nftables

	cat <<EOF >> /etc/nftables.conf

table ip nat {
	chain postrouting {
		type nat hook postrouting priority 100; policy accept;
		ip saddr 192.168.66.0/24 oif "`ip route show to default | awk '{print $5}'`" masquerade
	}
}
EOF

	systemctl enable nftables.service
	systemctl start nftables.service
fi

if ! dpkg --get-selections | grep -q '^ddclient\s\+install$'; then
	DEBIAN_FRONTEND=noninteractive apt-get -y install ddclient

	publicfqdn=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/publicfqdn -H "Metadata-Flavor: Google")
	dyndnsserver=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/dyndnsserver -H "Metadata-Flavor: Google")
	dyndnsuser=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/dyndnsuser -H "Metadata-Flavor: Google")
	dyndnspassword=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/dyndnspassword -H "Metadata-Flavor: Google")
	cat <<EOF > /etc/ddclient.conf
protocol=dyndns2
use=web
server=$dyndnsserver
ssl=yes
login=$dyndnsuser
password='$dyndnspassword'
$publicfqdn
EOF

	systemctl restart ddclient.service
fi
