################################################################################
# Workload spokes (prod + dev)
#
# Per-environment:
#   - Resource group: rg-flagship-<env>-network
#   - VNet with three subnets:
#       snet-app-service       (delegated to Microsoft.Web/serverFarms)
#       snet-mysql             (delegated to Microsoft.DBforMySQL/flexibleServers)
#       snet-private-endpoints
#   - NSG with default-deny inbound from Internet
#   - VNet peering to hub (bidirectional)
################################################################################

# Resource groups — one for network, one for compute, one for data per env
resource "azurerm_resource_group" "network" {
  for_each = local.environments

  name     = "rg-flagship-${each.key}-network"
  location = var.location
  tags     = local.tags_by_env[each.key]
}

resource "azurerm_resource_group" "compute" {
  for_each = local.environments

  name     = "rg-flagship-${each.key}-compute"
  location = var.location
  tags     = local.tags_by_env[each.key]
}

resource "azurerm_resource_group" "data" {
  for_each = local.environments

  name     = "rg-flagship-${each.key}-data"
  location = var.location
  tags     = local.tags_by_env[each.key]
}

# ─── Spoke VNet ────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "spoke" {
  for_each = local.environments

  name                = "vnet-flagship-${each.key}-${local.region_short}"
  resource_group_name = azurerm_resource_group.network[each.key].name
  location            = azurerm_resource_group.network[each.key].location
  address_space       = each.value.address_space

  tags = local.tags_by_env[each.key]
}

# App Service subnet — delegated to Microsoft.Web so VNet integration works
resource "azurerm_subnet" "app" {
  for_each = local.environments

  name                 = "snet-app-service"
  resource_group_name  = azurerm_resource_group.network[each.key].name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.subnet_app]

  delegation {
    name = "appservice-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# MySQL subnet — delegated to Microsoft.DBforMySQL/flexibleServers
resource "azurerm_subnet" "mysql" {
  for_each = local.environments

  name                 = "snet-mysql"
  resource_group_name  = azurerm_resource_group.network[each.key].name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.subnet_mysql]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Private endpoints subnet — no delegation
resource "azurerm_subnet" "private_endpoints" {
  for_each = local.environments

  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.network[each.key].name
  virtual_network_name = azurerm_virtual_network.spoke[each.key].name
  address_prefixes     = [each.value.subnet_pe]
}

# ─── NSGs (default-deny inbound from Internet) ─────────────────────────────

resource "azurerm_network_security_group" "spoke" {
  for_each = local.environments

  name                = "nsg-flagship-${each.key}"
  resource_group_name = azurerm_resource_group.network[each.key].name
  location            = azurerm_resource_group.network[each.key].location

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = local.tags_by_env[each.key]
}

resource "azurerm_subnet_network_security_group_association" "app" {
  for_each = local.environments

  subnet_id                 = azurerm_subnet.app[each.key].id
  network_security_group_id = azurerm_network_security_group.spoke[each.key].id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  for_each = local.environments

  subnet_id                 = azurerm_subnet.private_endpoints[each.key].id
  network_security_group_id = azurerm_network_security_group.spoke[each.key].id
}

# Note: MySQL delegated subnets cannot have NSGs at the subnet level —
# Azure manages MySQL Flexible Server's network access internally.

# ─── Hub-spoke peering (bidirectional) ─────────────────────────────────────

# Spoke → Hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = local.environments

  name                         = "peer-${each.key}-to-hub"
  resource_group_name          = azurerm_resource_group.network[each.key].name
  virtual_network_name         = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id    = data.terraform_remote_state.platform.outputs.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Hub → Spoke (created in the platform-network RG since that's where the hub lives)
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each = local.environments

  name                         = "peer-hub-to-${each.key}"
  resource_group_name          = data.terraform_remote_state.platform.outputs.network_resource_group_name
  virtual_network_name         = data.terraform_remote_state.platform.outputs.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.spoke[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}
