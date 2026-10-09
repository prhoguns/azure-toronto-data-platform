# Tests against a mocked azurerm provider: no subscription or credentials needed.
# They check the Terraform version keeps the Bicep version's design (same resources, same names,
# managed-identity access) plus the hardening it adds.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
      object_id = "00000000-0000-0000-0000-00000000aaaa"
    }
  }
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-tordata-data" }
  }
  mock_resource "azurerm_storage_account" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-tordata-data/providers/Microsoft.Storage/storageAccounts/tordatamock" }
  }
  mock_resource "azurerm_storage_container" {
    defaults = { id = "https://tordatamock.blob.core.windows.net/synapse" }
  }
  mock_resource "azurerm_key_vault" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-tordata-data/providers/Microsoft.KeyVault/vaults/kv-tordata-mock" }
  }
  mock_resource "azurerm_synapse_workspace" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-tordata-data/providers/Microsoft.Synapse/workspaces/syn-tordata-mock"
      identity = { principal_id = "11111111-0000-0000-0000-000000000001" }
      connectivity_endpoints = {
        sqlOnDemand = "syn-tordata-mock-ondemand.sql.azuresynapse.net"
      }
    }
  }
  mock_resource "azurerm_data_factory" {
    defaults = {
      identity = { principal_id = "11111111-0000-0000-0000-000000000002" }
    }
  }
  mock_resource "azurerm_databricks_access_connector" {
    defaults = {
      identity = { principal_id = "11111111-0000-0000-0000-000000000003" }
    }
  }
}

mock_provider "fabric" {
  mock_data "fabric_capacity" {
    defaults = { id = "33333333-0000-0000-0000-000000000001" }
  }
  mock_resource "fabric_workspace" {
    defaults = {
      id       = "33333333-0000-0000-0000-000000000002"
      identity = { type = "SystemAssigned", service_principal_id = "33333333-0000-0000-0000-000000000003" }
    }
  }
  mock_resource "fabric_lakehouse" {
    defaults = { id = "33333333-0000-0000-0000-000000000004" }
  }
  mock_resource "fabric_connection" {
    defaults = { id = "33333333-0000-0000-0000-000000000005" }
  }
}

run "lake_is_adls_gen2_without_keys" {
  assert {
    condition     = azurerm_storage_account.lake.is_hns_enabled
    error_message = "The lake must be ADLS Gen2 (hierarchical namespace)."
  }
  assert {
    condition     = !azurerm_storage_account.lake.shared_access_key_enabled && !azurerm_storage_account.lake.local_user_enabled
    error_message = "Account keys and local users must be disabled; access is Entra ID + RBAC only."
  }
  assert {
    condition     = azurerm_storage_account.lake.min_tls_version == "TLS1_2" && !azurerm_storage_account.lake.allow_nested_items_to_be_public
    error_message = "TLS 1.2 minimum and no public containers."
  }
  assert {
    condition     = toset(keys(azurerm_storage_container.lake)) == toset(["bronze", "silver", "gold", "synapse"])
    error_message = "Same four containers as the Bicep version."
  }
  assert {
    condition     = alltrue([for c in azurerm_storage_container.lake : c.container_access_type == "private"])
    error_message = "Every container must be private."
  }
}

run "services_use_managed_identities" {
  assert {
    condition = toset([for r in azurerm_role_assignment.lake_writers : r.principal_id]) == toset([
      azurerm_data_factory.this.identity[0].principal_id,
      azurerm_synapse_workspace.this.identity[0].principal_id,
      azurerm_databricks_access_connector.this.identity[0].principal_id,
    ])
    error_message = "Data Factory, Synapse and the Databricks access connector each get lake access through their own identity."
  }
  assert {
    condition     = alltrue([for r in azurerm_role_assignment.lake_writers : r.role_definition_name == "Storage Blob Data Contributor"])
    error_message = "Services get data-plane access only, not Owner or Contributor on the account."
  }
  assert {
    condition     = azurerm_synapse_workspace.this.azuread_authentication_only
    error_message = "Synapse must accept Entra ID logins only (no SQL password)."
  }
  assert {
    condition     = azurerm_synapse_workspace.this.storage_data_lake_gen2_filesystem_id == azurerm_storage_container.lake["synapse"].id
    error_message = "Synapse's default filesystem is the synapse container, as in the Bicep version."
  }
  assert {
    condition     = azurerm_role_assignment.admin_key_vault.principal_id == "00000000-0000-0000-0000-00000000aaaa"
    error_message = "With no admin_object_id set, the identity running Terraform administers Key Vault."
  }
}

run "key_vault_and_names" {
  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled && azurerm_key_vault.this.purge_protection_enabled
    error_message = "Key Vault uses RBAC and purge protection."
  }
  assert {
    condition = alltrue([
      startswith(azurerm_data_factory.this.name, "adf-tordata-"),
      startswith(azurerm_databricks_workspace.this.name, "dbw-tordata-"),
      startswith(azurerm_synapse_workspace.this.name, "syn-tordata-"),
      startswith(azurerm_key_vault.this.name, "kv-tordata-"),
      length(azurerm_key_vault.this.name) <= 24,
      length(azurerm_storage_account.lake.name) <= 24,
    ])
    error_message = "Names follow the Bicep version's pattern and Azure's length limits."
  }
  assert {
    condition     = azurerm_databricks_workspace.this.sku == "premium"
    error_message = "Unity Catalog needs the premium tier."
  }
}

run "explicit_admin_is_used" {
  variables {
    admin_object_id = "22222222-2222-2222-2222-222222222222"
  }
  assert {
    condition     = azurerm_synapse_workspace_aad_admin.this.object_id == "22222222-2222-2222-2222-222222222222"
    error_message = "admin_object_id must be the Synapse Entra admin."
  }
}

run "rejects_invalid_prefix" {
  command = plan
  variables {
    prefix = "Tor-Data"
  }
  expect_failures = [var.prefix]
}

run "fabric_is_off_by_default" {
  assert {
    condition     = length(azurerm_fabric_capacity.this) == 0 && length(fabric_workspace.this) == 0 && length(fabric_shortcut.gold) == 0
    error_message = "The Fabric layer is opt-in; a default deploy must not create a capacity that bills."
  }
}

run "fabric_serves_gold_through_shortcuts" {
  variables {
    enable_fabric    = true
    fabric_admin_upn = "admin@example.com"
  }
  assert {
    condition     = azurerm_fabric_capacity.this[0].sku[0].name == "F2" && azurerm_fabric_capacity.this[0].administration_members == toset(["admin@example.com"])
    error_message = "Smallest capacity by default, administered by the named user."
  }
  assert {
    condition     = fabric_workspace.this[0].capacity_id == "33333333-0000-0000-0000-000000000001" && fabric_workspace.this[0].identity.type == "SystemAssigned"
    error_message = "The workspace runs on the new capacity and has its own identity."
  }
  assert {
    condition     = azurerm_role_assignment.fabric_lake_reader[0].principal_id == "33333333-0000-0000-0000-000000000003" && azurerm_role_assignment.fabric_lake_reader[0].role_definition_name == "Storage Blob Data Reader"
    error_message = "Fabric reads the lake through the workspace identity, read-only."
  }
  assert {
    condition     = fabric_connection.lake[0].credential_details.credential_type == "WorkspaceIdentity"
    error_message = "The lake connection uses the workspace identity, not a key or secret."
  }
  assert {
    condition     = toset(keys(fabric_shortcut.gold)) == toset(["dim_date", "dim_neighbourhood", "fct_crime_incidents", "agg_crime_monthly_neighbourhood"])
    error_message = "One shortcut per gold table, the same four Synapse exposes."
  }
  assert {
    condition = alltrue([for k, sc in fabric_shortcut.gold :
      sc.path == "Tables" && sc.target.adls_gen2.subpath == "/gold/${k}" && sc.target.adls_gen2.connection_id == "33333333-0000-0000-0000-000000000005"
    ])
    error_message = "Each shortcut lands under Tables and points at its gold folder through the lake connection."
  }
}

run "fabric_requires_an_admin" {
  command = plan
  variables {
    enable_fabric = true
  }
  expect_failures = [var.fabric_admin_upn]
}
