locals {
  common_tags = {
    environment = var.environment
    owner       = var.owner
    project     = "azure-iac-labs"
    managed_by  = "terraform"
  }
}

resource "random_pet" "rg_name" {
  prefix = "${var.resource_group_name_prefix}-${var.environment}"
}

resource "azurerm_resource_group" "rg" {
  name     = random_pet.rg_name.id
  location = var.resource_group_location
  tags     = local.common_tags
}

# Virtual network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.environment}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.common_tags
}

# Workload subnet - application tier
resource "azurerm_subnet" "workload" {
  name                 = "snet-workload-${var.environment}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.workload_subnet_prefix]
}

# Management subnet - jump host / admin access tier
resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt-${var.environment}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.mgmt_subnet_prefix]
}

# Management NSG: SSH permitted only from a single known public IP
resource "azurerm_network_security_group" "mgmt" {
  name                = "nsg-mgmt-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowSSHFromAdminIP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${var.allowed_ssh_source_ip}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Workload NSG: reachable only from the management subnet, not the internet
resource "azurerm_network_security_group" "workload" {
  name                = "nsg-workload-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowSSHFromMgmtSubnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.mgmt_subnet_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

# Static public IP reserved for the management tier
resource "azurerm_public_ip" "mgmt" {
  name                = "pip-mgmt-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Unique suffix for the globally-scoped storage account name
resource "random_id" "storage_suffix" {
  keepers = {
    resource_group = azurerm_resource_group.rg.name
  }
  byte_length = 8
}

# Storage account for diagnostics
resource "azurerm_storage_account" "diagnostics" {
  name                     = "diag${random_id.storage_suffix.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.common_tags
}
