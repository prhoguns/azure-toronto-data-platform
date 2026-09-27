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
