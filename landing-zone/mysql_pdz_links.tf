################################################################################
# Spoke VNet links for the MySQL Private DNS zone
#
# WHY THIS EXISTS:
# Day 2 created the MySQL PDZ (privatelink.mysql.database.azure.com) and linked
# it to the hub VNet only. But Private DNS zone links do NOT traverse VNet
# peering -- each VNet that needs to resolve a privatelink hostname must have
# its own dedicated zone link.
#
# Since the MySQL servers themselves live in the spoke VNets (via subnet
# delegation), the spoke VNets MUST be linked to the MySQL PDZ for the
# server provisioning to complete.
################################################################################

resource "azurerm_private_dns_zone_virtual_network_link" "mysql_spoke" {
  for_each = local.environments

  name                  = "link-${each.key}-mysql"
  resource_group_name   = data.terraform_remote_state.platform.outputs.network_resource_group_name
  private_dns_zone_name = "privatelink.mysql.database.azure.com"
  virtual_network_id    = azurerm_virtual_network.spoke[each.key].id

  registration_enabled = false

  tags = local.tags_by_env[each.key]
}
