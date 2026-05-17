################################################################################
# App Service per environment
#
# Per env:
#   - App Service Plan (Linux)
#     prod: B1 always-on capable
#     dev:  F1 free tier
#   - Web App  (Node 20, hosts React frontend)
#   - API App  (Node 20, hosts Express API)
#   - VNet integration into snet-app-service (for outbound to MySQL + KV)
#   - Managed identity per app, granted RBAC reader on its KV
################################################################################

resource "azurerm_service_plan" "main" {
  for_each = local.environments

  name                = "plan-flagship-${each.key}-${local.region_short}"
  resource_group_name = azurerm_resource_group.compute[each.key].name
  location            = azurerm_resource_group.compute[each.key].location

  os_type  = "Linux"
  sku_name = each.value.app_service_sku

  tags = local.tags_by_env[each.key]
}

# ─── Web app (frontend) ────────────────────────────────────────────────────

resource "azurerm_linux_web_app" "web" {
  for_each = local.environments

  name                = "app-flagship-procurement-web-${each.key}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.compute[each.key].name
  location            = azurerm_service_plan.main[each.key].location
  service_plan_id     = azurerm_service_plan.main[each.key].id

  https_only                    = true
  public_network_access_enabled = true # web frontend is public

  # System-assigned managed identity — used to read secrets from KV
  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on        = each.value.app_service_sku != "F1" # F1 doesn't support always-on
    ftps_state       = "Disabled"
    http2_enabled    = true
    minimum_tls_version = "1.2"
    application_stack {
      node_version = "20-lts"
    }
  }

  app_settings = {
    WEBSITE_NODE_DEFAULT_VERSION    = "~20"
    SCM_DO_BUILD_DURING_DEPLOYMENT  = "true"
    KEY_VAULT_URI                   = azurerm_key_vault.main[each.key].vault_uri
    API_BASE_URL                    = "https://app-flagship-procurement-api-${each.key}-${random_string.suffix.result}.azurewebsites.net"
    APPLICATIONINSIGHTS_CONNECTION_STRING = "" # Day 4 will wire App Insights
  }

  tags = local.tags_by_env[each.key]

  lifecycle {
    ignore_changes = [
      # ignore changes from app deployments
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
      site_config[0].application_stack[0].node_version
    ]
  }
}

# VNet integration for the web app — outbound through snet-app-service
resource "azurerm_app_service_virtual_network_swift_connection" "web" {
  for_each = { for k, v in local.environments : k => v if v.app_service_sku != "F1" }
  # F1 free tier doesn't support VNet integration

  app_service_id = azurerm_linux_web_app.web[each.key].id
  subnet_id      = azurerm_subnet.app[each.key].id
}

# Grant the web app's identity Key Vault Secrets User on its KV
resource "azurerm_role_assignment" "web_kv_reader" {
  for_each = local.environments

  scope                = azurerm_key_vault.main[each.key].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.web[each.key].identity[0].principal_id
}

# ─── API app (backend) ─────────────────────────────────────────────────────

resource "azurerm_linux_web_app" "api" {
  for_each = local.environments

  name                = "app-flagship-procurement-api-${each.key}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.compute[each.key].name
  location            = azurerm_service_plan.main[each.key].location
  service_plan_id     = azurerm_service_plan.main[each.key].id

  https_only                    = true
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on        = each.value.app_service_sku != "F1"
    ftps_state       = "Disabled"
    http2_enabled    = true
    minimum_tls_version = "1.2"
    application_stack {
      node_version = "20-lts"
    }
    cors {
      allowed_origins = [
        "https://app-flagship-procurement-web-${each.key}-${random_string.suffix.result}.azurewebsites.net"
      ]
    }
  }

  app_settings = {
    WEBSITE_NODE_DEFAULT_VERSION   = "~20"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    KEY_VAULT_URI                  = azurerm_key_vault.main[each.key].vault_uri
    MYSQL_HOST                     = azurerm_mysql_flexible_server.main[each.key].fqdn
    MYSQL_USER                     = "flagshipadmin"
    MYSQL_DATABASE                 = "procurement"
    # MYSQL_PASSWORD pulled at runtime from KV via @Microsoft.KeyVault reference
    MYSQL_PASSWORD = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.mysql_admin_password[each.key].versionless_id})"
  }

  tags = local.tags_by_env[each.key]
}

resource "azurerm_app_service_virtual_network_swift_connection" "api" {
  for_each = { for k, v in local.environments : k => v if v.app_service_sku != "F1" }

  app_service_id = azurerm_linux_web_app.api[each.key].id
  subnet_id      = azurerm_subnet.app[each.key].id
}

resource "azurerm_role_assignment" "api_kv_reader" {
  for_each = local.environments

  scope                = azurerm_key_vault.main[each.key].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.api[each.key].identity[0].principal_id
}
