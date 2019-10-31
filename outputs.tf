output "subnet_id" {
  value = azurerm_subnet.subnet.id
}

output "virtual_network_id" {
  value = azurerm_virtual_network.vnet.id
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.*.name
}

output "storage_account_key" {
  value = azurerm_storage_account.storage.*.primary_access_key
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "azurerm_network_security_group_name" {
  value = azurerm_network_security_group.nsg.name
}
