################################################################################
# Key Vault per environment
#
#   - Standard SKU (Premium adds HSM, unnecessary for portfolio)
#   - RBAC authorization (no access policies â€” modern pattern)
#   - Soft-delete enabled (7 days, minimum)
#   - Private endpoint into snet-private-endpoints
#   - A record auto-registered via DNS zone group â†’ Day 2's PDZ
################################################################################

resource "azurerm_key_vault" "main" {
  for_each = local.environments

  name                = "kv-flag-${each.key}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.data[each.key].name
  location            = azurerm_resource_group.data[each.key].location

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  enable_rbac_authorization     = true
  purge_protection_enabled      = false # for portfolio teardown; enable for real prod
  soft_delete_retention_days    = 7
  public_network_access_enabled = false # locked to PE

  # When public access is disabled, the deploying identity needs to either:
  #   - be added to network_acls.ip_rules, OR
  #   - reach the KV through the PE (requires DNS + VNet line-of-sight)
  # For first apply from GH Actions runners, we need IP allow on the runner's IP.
  # Easier: leave bypass = AzureServices so Terraform can reach the data plane.
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = ["174.92.95.37"]
  }

  tags = local.tags_by_env[each.key]
}

# Grant the deploying identity Key Vault Administrator so initial secret writes work.
# This is the platform-team identity (running this stack via OIDC).
resource "azurerm_role_assignment" "kv_admin" {
  for_each = local.environments

  scope                = azurerm_key_vault.main[each.key].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# â”€â”€â”€ Private endpoint â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

resource "azurerm_private_endpoint" "kv" {
  for_each = local.environments

  name                = "pe-kv-${each.key}"
  resource_group_name = azurerm_resource_group.data[each.key].name
  location            = azurerm_resource_group.data[each.key].location
  subnet_id           = azurerm_subnet.private_endpoints[each.key].id

  private_service_connection {
    name                           = "psc-kv-${each.key}"
    private_connection_resource_id = azurerm_key_vault.main[each.key].id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  # Register the PE's IP into Day 2's privatelink.vaultcore.azure.net zone
  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      data.terraform_remote_state.platform.outputs.private_dns_zone_ids["keyvault"]
    ]
  }

  tags = local.tags_by_env[each.key]
}
