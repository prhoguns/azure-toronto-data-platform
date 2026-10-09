# Microsoft Fabric serving layer: the successor path to Synapse serverless (see README, "Fabric").
# Off by default. With enable_fabric = true it adds a Fabric capacity, a workspace with its own
# identity, and a Lakehouse whose tables are OneLake shortcuts to the gold Delta tables Databricks
# already writes. Nothing is copied: the SQL analytics endpoint and Power BI Direct Lake read the
# same files Synapse does. Synapse stays in place so the two can run side by side during a move.

locals {
  fabric_count = var.enable_fabric ? 1 : 0
  gold_tables  = toset(["dim_date", "dim_neighbourhood", "fct_crime_incidents", "agg_crime_monthly_neighbourhood"])
}

resource "azurerm_fabric_capacity" "this" {
  count                  = local.fabric_count
  name                   = "fab${var.prefix}${local.suffix}"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  administration_members = [var.fabric_admin_upn]
  tags                   = var.tags

  sku {
    name = var.fabric_sku
    tier = "Fabric"
  }
}

# The Fabric API addresses capacities by their Fabric ID, not the Azure resource ID.
data "fabric_capacity" "this" {
  count        = local.fabric_count
  display_name = azurerm_fabric_capacity.this[0].name
}

resource "fabric_workspace" "this" {
  count        = local.fabric_count
  display_name = "${var.prefix}-toronto-data"
  description  = "Gold layer of the Toronto data platform, served from OneLake shortcuts."
  capacity_id  = data.fabric_capacity.this[0].id

  # Workspace identity: Fabric reaches the lake as itself, like the other services, with no keys.
  identity = {
    type = "SystemAssigned"
  }
}

# Read-only, unlike the services that write the lake.
resource "azurerm_role_assignment" "fabric_lake_reader" {
  count                = local.fabric_count
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = fabric_workspace.this[0].identity.service_principal_id
  principal_type       = "ServicePrincipal"
}

resource "fabric_lakehouse" "gold" {
  count        = local.fabric_count
  display_name = "lh_toronto_gold"
  workspace_id = fabric_workspace.this[0].id
  description  = "Shortcuts to the gold Delta tables in ADLS Gen2."
}

resource "fabric_connection" "lake" {
  count             = local.fabric_count
  display_name      = "adls-${var.prefix}-gold"
  connectivity_type = "ShareableCloud"
  privacy_level     = "Organizational"

  connection_details = {
    type            = "AzureDataLakeStorage"
    creation_method = "AzureDataLakeStorage"
    parameters = [
      { name = "server", value = "${azurerm_storage_account.lake.name}.dfs.core.windows.net" },
      { name = "path", value = "gold" },
    ]
  }

  credential_details = {
    credential_type = "WorkspaceIdentity"
  }

  depends_on = [azurerm_role_assignment.fabric_lake_reader]
}

resource "fabric_shortcut" "gold" {
  for_each     = var.enable_fabric ? local.gold_tables : toset([])
  workspace_id = fabric_workspace.this[0].id
  item_id      = fabric_lakehouse.gold[0].id
  name         = each.key
  path         = "Tables"

  target = {
    adls_gen2 = {
      location      = "https://${azurerm_storage_account.lake.name}.dfs.core.windows.net"
      subpath       = "/gold/${each.key}"
      connection_id = fabric_connection.lake[0].id
    }
  }
}
