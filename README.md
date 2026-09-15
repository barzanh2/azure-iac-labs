# Azure IaC Labs — Network Baseline (Terraform)

A segmented Azure network baseline built with Terraform. Two subnets with
separate security boundaries, NSG rules scoped to specific sources rather than
left open, and the whole environment parameterised so the same code deploys a
dev or prod configuration.

Built as a hands-on lab while studying for AZ-104, coming from a Cisco
networking background. The Azure concepts map fairly directly onto physical
networking: a VNet is the address space, subnets are broadcast domains, and NSGs
are ACLs applied at the subnet boundary.

## What it deploys

| Resource | Purpose |
|---|---|
| Resource group | Randomly suffixed name, environment-prefixed |
| Virtual network | Address space set per environment |
| Workload subnet | Application tier |
| Management subnet | Admin / jump host tier |
| Management NSG | SSH allowed from one known public IP only, then deny all |
| Workload NSG | SSH allowed from the management subnet only, then deny all |
| NSG associations | Applied at subnet level, not per-NIC |
| Public IP | Static, Standard SKU, reserved for the management tier |
| Storage account | Diagnostics, TLS 1.2 minimum, uniquely named |
| SSH key pair | Generated in Azure via the azapi provider |

15 resources in total.

## Design decisions

**Two subnets, not one.** The workload subnet is not reachable from the
internet at all. The only inbound path to it is from the management subnet.
This is the cloud equivalent of putting management traffic on its own VLAN and
filtering between them, and it means a misconfigured workload host is not
directly exposed.

**NSGs attached to subnets rather than NICs.** Subnet association means the rule
applies to everything placed in that subnet, including resources added later.
Per-NIC association is easy to forget on the next deployment.

**Explicit deny rules.** Azure already has a default deny at priority 65500, so
the `DenyAllInbound` rules at priority 4000 are technically redundant. They are
there because an NSG that states its intent is easier to audit than one that
relies on an invisible default, and because a rule added later at priority 4500
will now fail closed rather than open.

**Admin IP is not in the repo.** `allowed_ssh_source_ip` lives in
`terraform.tfvars`, which is gitignored. `terraform.tfvars.example` is committed
in its place so the required variable is documented without publishing a home IP
address.

**Standard SKU public IP with static allocation.** Basic SKU public IPs are
being retired by Azure and new subscriptions cannot create them. Standard SKU
does not support dynamic allocation, so the two settings have to change
together.

**Tags on everything that supports them.** Environment, owner, project and
`managed_by`, applied from a `locals` block so they cannot drift between
resources.

## Repository layout

```
main.tf                    Network, security and storage resources
variables.tf               Input variable definitions
outputs.tf                 Resource group, public IP, VNet and subnet IDs
providers.tf               Provider versions and requirements
ssh.tf                     SSH key generation via the azapi provider
dev.tfvars                 Dev environment values (10.10.0.0/16)
prod.tfvars                Prod environment values (10.20.0.0/16)
terraform.tfvars.example   Template for the gitignored admin IP file
.gitignore                 Excludes state, plans and the real tfvars
```

## Usage

Requires the Azure CLI and Terraform. Authenticate first:

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

Set your own admin IP:

```bash
cp terraform.tfvars.example terraform.tfvars
curl ifconfig.me          # put this value in terraform.tfvars
```

Deploy:

```bash
terraform init
terraform fmt
terraform validate
terraform plan -var-file=dev.tfvars -out main.tfplan
terraform apply main.tfplan
```

Tear down:

```bash
terraform destroy -var-file=dev.tfvars
```

Swap `dev.tfvars` for `prod.tfvars` to deploy the prod address space and naming.
`terraform plan -var-file=prod.tfvars` against a dev deployment shows a full
replacement, which is the intended behaviour — they are separate environments,
not a migration path.

## Problems hit and how they were solved

The Microsoft quickstart this started from is out of date in several places.
These are the failures worth recording.

### Basic SKU public IPs cannot be created

```
IPv4BasicSkuPublicIpCountLimitReached: Cannot create more than 0 IPv4 Basic SKU
public IP addresses for this subscription in this region.
```

Azure is retiring Basic SKU public IPs, and new subscriptions have a hard limit
of zero. The quickstart still specified Basic with dynamic allocation. Fixing it
required two changes, not one: Standard SKU, and `allocation_method` changed
from `Dynamic` to `Static`, because Standard does not support dynamic
allocation. Changing only the SKU produces a second error.

### Provider returned an inconsistent result

```
Error: Provider produced inconsistent result after apply
When applying changes to azurerm_public_ip.my_terraform_public_ip, provider
produced an unexpected new value: Root object was present, but now absent.
```

A bug in `azurerm` 3.x. Azure created the public IP, but the provider lost track
of it and recorded nothing in state. The next `plan` then tried to create it
again and Azure refused, because a resource with that ID already existed.

Two things to take from this. First, the fix was pinning `azurerm` to `~>4.0`,
after which it did not recur. Second, the intermediate state — real resources
that Terraform has no record of — is the failure mode that makes people distrust
IaC. The options are `terraform import` to adopt the orphaned resources, or
delete the resource group outright and start from a clean state. For a
disposable lab, deleting was faster; in production, import is the answer.

### VM SKU not available

```
SkuNotAvailable: The requested VM size for resource 'Following SKUs have failed
for Capacity Restrictions: Standard_B1s' is currently not available in location
'australiaeast'.
```

Hit across four combinations: `Standard_DS1_v2` in East US, `Standard_B1s` and
`Standard_D2s_v3` in Australia East, `Standard_D2s_v3` in Australia Southeast.

The diagnosis took a while because the obvious explanation — quota — was wrong.
`az vm list-usage` showed 0 of 4 vCPUs used, so quota was available.
`az vm list-skus` was more revealing:

```bash
az vm list-skus --location australiaeast --size Standard_B --resource-type virtualMachines -o table
```

Every x64 B-series size returned `NotAvailableForSubscription`. The only sizes
showing no restrictions were `Bpls_v2` and `Bps_v2` variants, which are ARM64
and would not have run the x64 Ubuntu image the config specified.

The underlying cause is that Azure free trial subscriptions have compute
restricted in many regions, and free trials are not eligible for quota increase
requests. The resolution is to upgrade to pay-as-you-go, or to build something
that does not require compute.

### What that changed

The VM was removed from the lab entirely. It was only ever there because the
quickstart's title was "create a Linux VM" — it contributed nothing to the
networking design, and the NIC that existed solely to attach it was removed at
the same time, with NSGs re-attached at subnet level instead.

The result is a better fit for what the lab is actually about. Everything that
remains — address space design, subnet segmentation, scoped security rules,
environment parameterisation — is the part worth demonstrating.

## Known gaps

Deliberately left for later rather than overlooked:

- **State is local.** `terraform.tfstate` sits on disk and contains the
  generated SSH private key and storage account keys in plaintext. This is why
  it is gitignored. A shared environment needs a remote backend with state
  locking.
- **No CI.** `fmt`, `validate` and `plan` should run on pull requests rather
  than by hand.
- **Single region.** No peering, no hub-and-spoke, no route tables.
- **No compute.** See above.
