output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "storage_account_name" {
  value = azurerm_storage_account.lake.name
}

output "data_factory_name" {
  value = azurerm_data_factory.this.name
}

output "databricks_workspace_url" {
  value = azurerm_databricks_workspace.this.workspace_url
}

output "databricks_access_connector_id" {
  description = "Use as the Unity Catalog storage credential for the lake."
  value       = azurerm_databricks_access_connector.this.id
}

output "synapse_serverless_endpoint" {
  value = azurerm_synapse_workspace.this.connectivity_endpoints["sqlOnDemand"]
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "fabric_workspace_id" {
  value = var.enable_fabric ? fabric_workspace.this[0].id : null
}

output "fabric_lakehouse_sql_endpoint" {
  description = "Connection string for the Lakehouse SQL analytics endpoint (run fabric/sql/ here)."
  value       = var.enable_fabric ? fabric_lakehouse.gold[0].properties.sql_endpoint_properties.connection_string : null
}
