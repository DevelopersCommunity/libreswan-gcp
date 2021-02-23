# Google Cloud Platform free tier IKEv2/IPSec PSK VPN Server

How to create a free personal VPN Server on [Google Cloud Platform (GCP)](https://cloud.google.com/free) with [libreswan](https://libreswan.org/wiki/VPN_server_for_remote_clients_using_IKEv2).

Both [Android 11 or higher](https://source.android.com/devices/architecture/modular-system/ipsec) and [iOS 4.0+](https://developer.apple.com/documentation/devicemanagement/vpn/ikev2) devices can connect to IKEv2/IPSec VPN servers with their native VPN clients.

## PowerShell installation

Follow the instructions at <https://docs.microsoft.com/powershell/scripting/install/installing-powershell> to install PowerShell.

## gcloud command-line tool installation

Follow the instructions at <https://cloud.google.com/sdk/docs/install> to install the gcloud CLI, then run the following commands to initialize it and install the required components.

```powershell
gcloud init
gcloud components install beta
```

## Project billing configuration

Before creating your first VM instance, you need to link a billing account to the GCP project you will use to create your VPN server.

A default project and billing account are provisioned when you create a free trial GCP account.

Use the following PowerShell commands to get your default project and billing account details, and link them. Replace the `filter` parameters with the names of your project and billing account.

```powershell
gcloud projects list
$projectID = gcloud projects list `
    --filter="name:'My First Project'" `
    --format="value(projectId)"

gcloud beta billing accounts list
$billingAccount = gcloud beta billing accounts list `
    --filter="displayName:'Minha conta de faturamento'" `
    --format="value(name)"

gcloud beta billing projects link $projectID `
    --billing-account=$billingAccount
```

## Dynamic DNS

GCP doesn't have a feature to create a public DNS name for virtual machines and [Google Cloud Free Tier does not include external IP addresses](https://cloud.google.com/free/docs/gcp-free-tier#free-tier-usage-limits). We will use a Dynamic DNS name to provide a convenient way to access the VPN server.

There are a few free Dynamic DNS service providers available, such as [No-IP.com](https://www.noip.com/remote-access). If you own a domain name, it is possible that your registrar provides this service (for example, [Google Domains](https://support.google.com/domains/answer/6147083).)

The installation script configures the [DDclient](https://ddclient.net/) package to update the dynamic DNS entry using the [dyndns2 protocol](https://ddclient.net/protocols.html#dyndns2). If you select a provider that doesn't support this protocol, you will need to adapt the script.

## VM creation

Run the `vpngcp.ps1` PowerShell script to create a VM and configure it as a VPN server. This script requires the following parameters:

- `InstanceName`: GCP VM instance name
- `Zone`: free VMs are available in the following zones:
  - `us-west1-a`
  - `us-west1-b`
  - `us-west1-c`
  - `us-central1-a`
  - `us-central1-b`
  - `us-central1-c`
  - `us-central1-f`
  - `us-east1-b`
  - `us-east1-c`
  - `us-east1-d`
- `PublicFqdn`: Dynamic DNS name
- `Psk`: IKEv2 pre-shared key
- `IPSecIdentifier`: IPSec identifier
- `DynDnsServer`: Dynamic DNS update server
  - No-IP.com: `dynupdate.no-ip.com`
  - Google Domains: `domains.google.com`
- `DynDnsUser`: Dynamic DNS service user name
- `DynDnsPassword`: Dynamic DNS service password

```powershell
.\vpngcp.ps1
```

## SSH

Execute the following command to open an SSH session to your VM and check if the installation succeeded. Use the instructions at <https://cloud.google.com/compute/docs/startupscript> to view the installation script output.

```powershell
gcloud compute ssh <instance name> --zone=<zone>
```

## Android 11 native IKEv2/IPSec PSK VPN client configuration

Use the following values from the parameters provided to the VM installation script:

- Type: IKEv2/IPSec PSK
- Server address: `PublicFqdn`
- IPSec Identifier: `IPSecIdentifier`
- IPSec pre-shared key: `Psk`

![Android native IKEv2/IPSec PSK VPN client](vpnandroid.png)

## iOS native IKEv2 VPN client configuration

Use the following values from the parameters provided to the VM installation script:

- Type: IKEv2
- Server: `PublicFqdn`
- Remote ID: `PublicFqdn`
- Local ID: `IPSecIdentifier`
- User Authentication: None
- Use Certificate: disabled
- Secret: `Psk`

![iOS native IKEv2 VPN client](vpnios.png)
