################################################################################
# Auto-shutdown for dev resources
#
# Tag-driven: anything tagged autoshutdown=true gets stopped on a schedule.
# Implementation: Azure Automation account with a PowerShell runbook that
# queries by tag and stops App Services and MySQL servers. Two schedules:
#   - Weekday: stop 19:00 EDT, start 07:00 EDT (Mon-Fri)
#   - Weekend: stop Friday 19:00 EDT, start Monday 07:00 EDT
#
# Why Automation account instead of Logic App: PowerShell runbooks are simpler
# for "list resources by tag, run a stop command" patterns. Logic Apps are
# better for event-driven workflows.
#
# Cost: ~$0.002 per runbook minute. With ~10 min total per day, costs pennies.
################################################################################

resource "azurerm_resource_group" "automation" {
  name     = "rg-flagship-platform-automation"
  location = var.location
  tags = {
    environment  = "platform"
    region       = var.location
    cost-center  = "flagship-portfolio"
    managed-by   = "terraform"
    service-tier = "shared"
  }
}

resource "azurerm_automation_account" "main" {
  name                = "aa-flagship-autoshutdown"
  resource_group_name = azurerm_resource_group.automation.name
  location            = azurerm_resource_group.automation.location

  sku_name = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment  = "platform"
    region       = var.location
    cost-center  = "flagship-portfolio"
    managed-by   = "terraform"
    service-tier = "shared"
  }
}

# Grant the Automation managed identity Contributor on the subscription
# scoped action: stop App Services + stop MySQL Flexible Servers
resource "azurerm_role_assignment" "automation_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.main.identity[0].principal_id
}

# PowerShell runbook: stops all resources tagged autoshutdown=true
resource "azurerm_automation_runbook" "stop_tagged" {
  name                    = "Stop-TaggedResources"
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  location                = azurerm_resource_group.automation.location

  log_verbose  = true
  log_progress = true
  description  = "Stops App Services and MySQL Flexible Servers tagged autoshutdown=true"
  runbook_type = "PowerShell"

  content = <<-EOT
    # Stop-TaggedResources.ps1
    # Stops App Services and MySQL Flexible Servers tagged autoshutdown=true.
    # Runs under the Automation account's system-assigned managed identity.

    $ErrorActionPreference = "Continue"
    Write-Output "Authenticating with managed identity..."
    Connect-AzAccount -Identity | Out-Null

    Write-Output "Finding resources tagged autoshutdown=true..."
    $resources = Get-AzResource -Tag @{ "autoshutdown" = "true" }
    Write-Output "Found $($resources.Count) tagged resources."

    foreach ($r in $resources) {
      try {
        switch ($r.ResourceType) {
          "Microsoft.Web/sites" {
            Write-Output "Stopping App Service: $($r.Name)"
            Stop-AzWebApp -ResourceGroupName $r.ResourceGroupName -Name $r.Name -ErrorAction Stop
          }
          "Microsoft.DBforMySQL/flexibleServers" {
            Write-Output "Stopping MySQL: $($r.Name)"
            $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
            $uri = "https://management.azure.com$($r.ResourceId)/stop?api-version=2023-12-30"
            Invoke-RestMethod -Uri $uri -Method POST -Headers @{ Authorization = "Bearer $token" }
          }
          default {
            Write-Output "Skipping unsupported type: $($r.ResourceType) for $($r.Name)"
          }
        }
      } catch {
        Write-Output "Failed to stop $($r.Name): $_"
      }
    }
    Write-Output "Done."
  EOT
}

# PowerShell runbook: starts tagged resources (mirror of stop)
resource "azurerm_automation_runbook" "start_tagged" {
  name                    = "Start-TaggedResources"
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  location                = azurerm_resource_group.automation.location

  log_verbose  = true
  log_progress = true
  description  = "Starts App Services and MySQL Flexible Servers tagged autoshutdown=true"
  runbook_type = "PowerShell"

  content = <<-EOT
    $ErrorActionPreference = "Continue"
    Connect-AzAccount -Identity | Out-Null
    $resources = Get-AzResource -Tag @{ "autoshutdown" = "true" }
    Write-Output "Found $($resources.Count) tagged resources to start."

    foreach ($r in $resources) {
      try {
        switch ($r.ResourceType) {
          "Microsoft.Web/sites" {
            Start-AzWebApp -ResourceGroupName $r.ResourceGroupName -Name $r.Name -ErrorAction Stop
          }
          "Microsoft.DBforMySQL/flexibleServers" {
            $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
            $uri = "https://management.azure.com$($r.ResourceId)/start?api-version=2023-12-30"
            Invoke-RestMethod -Uri $uri -Method POST -Headers @{ Authorization = "Bearer $token" }
          }
        }
      } catch {
        Write-Output "Failed to start $($r.Name): $_"
      }
    }
  EOT
}

# ─── Schedules (Eastern Daylight Time = UTC-4) ─────────────────────────────

# Stop weekday at 19:00 EDT = 23:00 UTC
resource "azurerm_automation_schedule" "stop_weekday" {
  name                    = "stop-weekday-1900-EDT"
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name

  frequency   = "Week"
  interval    = 1
  timezone    = "America/Toronto"
  start_time  = formatdate("YYYY-MM-DD'T'19:00:00-04:00", timeadd(timestamp(), "48h"))
  description = "Stop tagged resources at 7pm EDT, Mon-Fri"
  week_days   = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Start weekday at 07:00 EDT
resource "azurerm_automation_schedule" "start_weekday" {
  name                    = "start-weekday-0700-EDT"
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name

  frequency   = "Week"
  interval    = 1
  timezone    = "America/Toronto"
  start_time  = formatdate("YYYY-MM-DD'T'07:00:00-04:00", timeadd(timestamp(), "48h"))
  description = "Start tagged resources at 7am EDT, Mon-Fri"
  week_days   = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# Link runbooks to schedules
resource "azurerm_automation_job_schedule" "stop_weekday" {
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  schedule_name           = azurerm_automation_schedule.stop_weekday.name
  runbook_name            = azurerm_automation_runbook.stop_tagged.name
}

resource "azurerm_automation_job_schedule" "start_weekday" {
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  schedule_name           = azurerm_automation_schedule.start_weekday.name
  runbook_name            = azurerm_automation_runbook.start_tagged.name
}
