output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "public_ip_address" {
  value = azurerm_public_ip.mgmt.ip_address
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "subnet_ids" {
  value = {
    workload = azurerm_subnet.workload.id
    mgmt     = azurerm_subnet.mgmt.id
  }
}
