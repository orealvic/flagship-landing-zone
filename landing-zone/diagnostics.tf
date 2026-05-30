################################################################################
# Diagnostic settings — centralized observability
#
# Routes platform/resource logs and metrics from the workload resources to the
# shared Log Analytics workspace created in flagship-platform.
#
# SCOPE: Production only.
#   Dev is ephemeral (auto-shuts-down nightly via the Automation runbooks) and
#   its log volume isn't worth the ingestion cost. If dev diagnostics are needed
#   for a specific investigation, add "dev" to local.diag_environments below.
#
# CATEGORIES: allLogs + AllMetrics.
#   "allLogs" is a category GROUP — it auto-includes every log category the
#   resource type supports, and survives Azure adding new categories later
#   (no Terraform change needed when a new log type ships). AllMetrics captures
#   the platform metrics. This is the lowest-maintenance comprehensive setting.
#
# WORKSPACE: pulled from the platform remote state output
#   `log_analytics_workspace_id` — same pattern as private_dns_zone_ids.
################################################################################

locals {
  # Which environments get diagnostic settings. Prod only by default.
  # To add dev temporarily, change to: toset(["prod", "dev"])
  diag_environments = toset([for k, v in local.environments : k if v.service_tier == "production"])

  # Shorthand for the workspace ID, resolved from platform remote state.
  log_analytics_workspace_id = data.terraform_remote_state.platform.outputs.log_analytics_workspace_id
}

# ─── Web app (frontend) ─────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "web" {
  for_each = local.diag_environments

  name                       = "diag-web-${each.key}"
  target_resource_id         = azurerm_linux_web_app.web[each.key].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ─── API app (backend) ──────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "api" {
  for_each = local.diag_environments

  name                       = "diag-api-${each.key}"
  target_resource_id         = azurerm_linux_web_app.api[each.key].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ─── MySQL Flexible Server ──────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "mysql" {
  for_each = local.diag_environments

  name                       = "diag-mysql-${each.key}"
  target_resource_id         = azurerm_mysql_flexible_server.main[each.key].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ─── Key Vault ──────────────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  for_each = local.diag_environments

  name                       = "diag-kv-${each.key}"
  target_resource_id         = azurerm_key_vault.main[each.key].id
  log_analytics_workspace_id = local.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
