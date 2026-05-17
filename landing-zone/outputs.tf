output "spoke_vnet_ids" {
  description = "Spoke VNet IDs per environment"
  value       = { for k, v in azurerm_virtual_network.spoke : k => v.id }
}

output "web_app_urls" {
  description = "Default hostnames of the web apps per environment"
  value       = { for k, v in azurerm_linux_web_app.web : k => "https://${v.default_hostname}" }
}

output "api_app_urls" {
  description = "Default hostnames of the API apps per environment"
  value       = { for k, v in azurerm_linux_web_app.api : k => "https://${v.default_hostname}" }
}

output "mysql_fqdns" {
  description = "MySQL Flexible Server FQDNs per environment"
  value       = { for k, v in azurerm_mysql_flexible_server.main : k => v.fqdn }
}

output "key_vault_uris" {
  description = "Key Vault URIs per environment"
  value       = { for k, v in azurerm_key_vault.main : k => v.vault_uri }
}

output "resource_groups" {
  description = "Resource groups created per environment"
  value = {
    for env in keys(local.environments) : env => [
      azurerm_resource_group.network[env].name,
      azurerm_resource_group.compute[env].name,
      azurerm_resource_group.data[env].name,
    ]
  }
}

output "automation_account_name" {
  description = "Automation account name (for portfolio screenshots)"
  value       = azurerm_automation_account.main.name
}
