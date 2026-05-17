################################################################################
# Landing-zone stack
#
# Deploys the workload spokes (prod + dev):
#   - Spoke VNets peered to the hub from flagship-platform
#   - App Service Plans + App Services (web + API per environment)
#   - MySQL Flexible Server per environment with private endpoint
#   - Key Vault per environment with private endpoint
#   - Auto-shutdown Logic App for dev resources
#
# Runs from GitHub Actions via OIDC. State key: landing-zone.tfstate
#
# Depends on flagship-platform outputs (hub VNet ID, private DNS zone IDs,
# Log Analytics workspace ID). Consumed via terraform_remote_state.
################################################################################

terraform {
  required_version = ">= 1.9.0"

  backend "azurerm" {
    use_azuread_auth = true
    # Backend config supplied at init time by the reusable workflow
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true # for portfolio teardown; remove for real prod
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

# Pull outputs from the platform stack — hub VNet, DNS zones, Log Analytics
data "terraform_remote_state" "platform" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
    key                  = "platform.tfstate"
    use_azuread_auth     = true
  }
}

data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

# Short random suffix for globally-unique resource names (KV, MySQL)
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

locals {
  region_short = "cac"

  # Environment definitions — drives most of the for_each loops below.
  environments = {
    prod = {
      address_space     = ["10.20.0.0/16"]
      subnet_app        = "10.20.10.0/24"
      subnet_mysql      = "10.20.20.0/24"
      subnet_pe         = "10.20.30.0/24"
      app_service_sku   = "B1"
      mysql_sku         = "B_Standard_B1ms"
      mysql_storage_gb  = 32
      mysql_backup_days = 7
      autoshutdown      = "false"
      service_tier      = "production"
    }
    dev = {
      address_space     = ["10.30.0.0/16"]
      subnet_app        = "10.30.10.0/24"
      subnet_mysql      = "10.30.20.0/24"
      subnet_pe         = "10.30.30.0/24"
      app_service_sku   = "F1"
      mysql_sku         = "B_Standard_B1ms"
      mysql_storage_gb  = 20
      mysql_backup_days = 7
      autoshutdown      = "true"
      service_tier      = "development"
    }
  }

  # 5-tag taxonomy — applied per environment. autoshutdown is the lever for the Logic App.
  tags_by_env = {
    for k, v in local.environments : k => {
      environment  = k
      region       = var.location
      cost-center  = "flagship-portfolio"
      managed-by   = "terraform"
      service-tier = v.service_tier
      autoshutdown = v.autoshutdown
    }
  }
}
