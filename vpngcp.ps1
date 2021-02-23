#! /usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $InstanceName,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("us-west1-a", "us-west1-b", "us-west1-c", "us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f", "us-east1-b", "us-east1-c", "us-east1-d")]
    [string]
    $Zone,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $PublicFqdn,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [securestring]
    $Psk,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $IPSecIdentifier,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $DynDnsServer,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $DynDnsUser,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [securestring]
    $DynDnsPassword
)

gcloud compute firewall-rules create allow-isakmp `
    --allow=udp:500 `
    --target-tags=ipsec
gcloud compute firewall-rules create allow-ipsec-nat-t `
    --allow=udp:4500 `
    --target-tags=ipsec

gcloud compute instances create $InstanceName `
    --image-family=debian-10 `
    --image-project=debian-cloud `
    --zone=$Zone `
    --shielded-integrity-monitoring `
    --shielded-vtpm `
    --can-ip-forward `
    --machine-type=f1-micro `
    --tags=ipsec `
    --metadata=publicfqdn=$PublicFqdn`,psk=$($Psk | ConvertFrom-SecureString -AsPlainText)`,ipsecidentifier=$IPSecIdentifier`,dyndnsserver=$DynDnsServer`,dyndnsuser=$DynDnsUser`,dyndnspassword=$($DynDnsPassword | ConvertFrom-SecureString -AsPlainText)`,subnet=$(gcloud compute networks subnets describe default --region=$($Zone.Substring(0, $Zone.Length - 2)) --format='value(ipCidrRange)') `
    --metadata-from-file=startup-script=.\install.sh
