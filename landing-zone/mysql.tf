################################################################################
# MySQL Flexible Server per environment
#
#   - B_Standard_B1ms (1 vCore, 2 GiB RAM, burstable — fits cheap demo)
#   - VNet-integrated via snet-mysql delegated subnet (no public network access)
#   - Generated random admin password stored in Key Vault as `mysql-admin-password`
#   - 7-day backup retention
#
# IMPORTANT: VNet-integrated MySQL Flexible Server does NOT use private endpoints.
# It uses subnet delegation — the server itself lives in the delegated subnet and
# is reachable from the VNet's address space. No PE/PDZ needed for the DB itself.
################################################################################

resource "random_password" "mysql_admin" {
  for_each = local.environments

  length      = 24
  special     = true
  min_lower   = 2
  min_upper   = 2
  min_numeric = 2
  min_special = 2
  # Exclude characters that cause connection-string headaches
  override_special = "!@#$%^*-_=+"
}

# Store the password in Key Vault FIRST. The MySQL server uses an output from
# random_password directly, so the secret lookup is not on the deploy path —
# it's there for the app/operators to retrieve later.
resource "azurerm_key_vault_secret" "mysql_admin_password" {
  for_each = local.environments

  name         = "mysql-admin-password"
  value        = random_password.mysql_admin[each.key].result
  key_vault_id = azurerm_key_vault.main[each.key].id

  content_type = "text/plain"

  # Make sure the Key Vault RBAC for this principal exists before writing.
  depends_on = [azurerm_role_assignment.kv_admin]

  tags = local.tags_by_env[each.key]

  lifecycle {
    ignore_changes = [value] # so password rotations outside Terraform don't trigger drift
  }
}

# Also store the server's FQDN as a Key Vault secret for the app to read
resource "azurerm_key_vault_secret" "mysql_fqdn" {
  for_each = local.environments

  name         = "mysql-fqdn"
  value        = azurerm_mysql_flexible_server.main[each.key].fqdn
  key_vault_id = azurerm_key_vault.main[each.key].id

  depends_on = [azurerm_role_assignment.kv_admin]
  tags       = local.tags_by_env[each.key]
}

# ─── MySQL Flexible Server ─────────────────────────────────────────────────

resource "azurerm_mysql_flexible_server" "main" {
  for_each = local.environments

  name                = "mysql-flag-${each.key}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.data[each.key].name
  location            = azurerm_resource_group.data[each.key].location

  administrator_login    = "flagshipadmin"
  administrator_password = random_password.mysql_admin[each.key].result

  sku_name = each.value.mysql_sku
  version  = "8.0.21"

  # VNet integration — server lives in the delegated subnet, no public IP
  delegated_subnet_id = azurerm_subnet.mysql[each.key].id
  # Private DNS zone for MySQL — Day 2 created this
  private_dns_zone_id = data.terraform_remote_state.platform.outputs.private_dns_zone_ids["mysql"]

  backup_retention_days        = each.value.mysql_backup_days
  geo_redundant_backup_enabled = false # cost-engineered, single-region

  storage {
    size_gb           = each.value.mysql_storage_gb
    auto_grow_enabled = true
    iops              = 360 # B1ms minimum
  }

  # High availability disabled — B-series SKU doesn't support it anyway
  # Maintenance window: Sunday 03:00 local time
  maintenance_window {
    day_of_week  = 0
    start_hour   = 3
    start_minute = 0
  }

  tags = local.tags_by_env[each.key]

  lifecycle {
    ignore_changes = [
      administrator_password, # ignore drift after manual rotations
      zone                    # Azure may auto-pick a zone; don't fight it
    ]
  }
}

# ─── Server-level config ───────────────────────────────────────────────────

# Require SSL — defensive default
resource "azurerm_mysql_flexible_server_configuration" "require_secure_transport" {
  for_each = local.environments

  name                = "require_secure_transport"
  resource_group_name = azurerm_resource_group.data[each.key].name
  server_name         = azurerm_mysql_flexible_server.main[each.key].name
  value               = "ON"
}

# Set timezone to UTC for consistency
resource "azurerm_mysql_flexible_server_configuration" "time_zone" {
  for_each = local.environments

  name                = "time_zone"
  resource_group_name = azurerm_resource_group.data[each.key].name
  server_name         = azurerm_mysql_flexible_server.main[each.key].name
  value               = "+00:00"
}
