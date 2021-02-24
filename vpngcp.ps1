#!/usr/bin/env pwsh

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

function ConvertTo-Base64 {
    param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [byte[]]
        $Bytes
    )

    [System.Convert]::ToBase64String($Bytes)
}

function New-Psk {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [int]
        $Size
    )
    , (Get-Random -Maximum 255 -Count $Size) | ConvertTo-Base64
}

if (!(gcloud compute firewall-rules list `
            --filter="name~'^allow-isakmp-ipsec-nat-t$'" `
            --format=json |
        ConvertFrom-Json)
) {
    gcloud compute firewall-rules create allow-isakmp-ipsec-nat-t `
        --allow=udp:500`,udp:4500 `
        --target-tags=vpn-server
}

$Psk = New-Psk -Size 24

gcloud compute instances create $InstanceName `
    --image-family=debian-10 `
    --image-project=debian-cloud `
    --zone=$Zone `
    --shielded-integrity-monitoring `
    --shielded-vtpm `
    --can-ip-forward `
    --machine-type=f1-micro `
    --tags=vpn-server `
    --metadata=publicfqdn=$PublicFqdn`,psk=$Psk`,ipsecidentifier=$IPSecIdentifier`,dyndnsserver=$DynDnsServer`,dyndnsuser=$DynDnsUser`,dyndnspassword=$($DynDnsPassword | ConvertFrom-SecureString -AsPlainText)`,subnet=$(gcloud compute networks subnets describe default --region=$($Zone.Substring(0, $Zone.Length - 2)) --format='value(ipCidrRange)') `
    --metadata-from-file=startup-script=.\install.sh

"----------------------"
"VPN client parameters:"
"----------------------"

, $([PSCustomObject]@{Android = "Server address"; iOS = "Server"; Value = "$PublicFqdn" },
    [PSCustomObject]@{Android = "N/A"; iOS = "Remote ID"; Value = "$PublicFqdn" },
    [PSCustomObject]@{Android = "IPSec identifier"; iOS = "Local ID"; Value = "$IPSecIdentifier" },
    [PSCustomObject]@{Android = "IPSec pre-shared key"; iOS = "Secret"; Value = "$Psk" }) |
Format-Table
