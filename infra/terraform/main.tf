# Terraform version of main.bicep: the same platform, resource for resource, plus the Unity Catalog
# access connector and Entra-only authentication (see README, "Bicep and Terraform").

data "azurerm_client_config" "current" {}

locals {
  admin_object_id = coalesce(var.admin_object_id, data.azurerm_client_config.current.object_id)
  # Deterministic per resource group, like uniqueString(resourceGroup().id) in the Bicep version.
  suffix     = substr(sha1(azurerm_resource_group.this.id), 0, 8)
  containers = ["bronze", "silver", "gold", "synapse"]
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}-data"
  location = var.location
  tags     = var.tags
}

# ---------------- ADLS Gen2 ----------------
resource "azurerm_storage_account" "lake" {
  # checkov:skip=CKV_AZURE_33: queue logging does not apply; this account only serves ADLS Gen2 (no queues in use)
  # checkov:skip=CKV2_AZURE_1: customer-managed keys are out of scope; data is encrypted at rest with Microsoft-managed keys, twice (infrastructure encryption)
  # checkov:skip=CKV_AZURE_206: LRS keeps cost down for a portfolio project; production would use ZRS or GRS
  # checkov:skip=CKV_AZURE_59: public endpoint kept so the local runner and Power BI can connect; access requires Entra ID and RBAC, shared keys are disabled
  # checkov:skip=CKV2_AZURE_33: private endpoints are out of scope (see README, "Not done yet")
  # checkov:skip=CKV_AZURE_43: the name is built with substr() and always meets the rules; Checkov cannot evaluate the expression
  name                              = substr("${var.prefix}${local.suffix}", 0, 24)
  resource_group_name               = azurerm_resource_group.this.name
  location                          = azurerm_resource_group.this.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  is_hns_enabled                    = true # hierarchical namespace = ADLS Gen2
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false # every client uses Entra ID and RBAC; no account keys exist to leak
  local_user_enabled                = false # no SFTP/local-user accounts either
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "lake" {
  # checkov:skip=CKV2_AZURE_21: blob read logging would go to a Log Analytics workspace this project does not deploy
  for_each              = toset(local.containers)
  name                  = each.value
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

# ---------------- Key Vault ----------------
resource "azurerm_key_vault" "this" {
  # checkov:skip=CKV_AZURE_109: public endpoint with RBAC; private networking is out of scope (see README)
  # checkov:skip=CKV_AZURE_189: same as above
  # checkov:skip=CKV2_AZURE_32: private endpoints are out of scope (see README)
  name                       = substr("kv-${var.prefix}-${local.suffix}", 0, 24)
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  tags                       = var.tags
}

# ---------------- Data Factory ----------------
resource "azurerm_data_factory" "this" {
  # checkov:skip=CKV_AZURE_103: pipelines live in adf/ in this repo and are published by scripts/publish_adf.sh, not through the ADF Git integration
  # checkov:skip=CKV_AZURE_104: private networking (managed VNet, private endpoints) is out of scope (see README)
  # checkov:skip=CKV2_AZURE_15: customer-managed keys are out of scope; Microsoft-managed encryption at rest applies
  name                = "adf-${var.prefix}-${local.suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ---------------- Databricks ----------------
resource "azurerm_databricks_workspace" "this" {
  # checkov:skip=CKV_AZURE_158: VNet injection and private link are out of scope (see README)
  # checkov:skip=CKV2_AZURE_48: customer-managed keys for DBFS are out of scope; data lives in the lake, not DBFS
  name                        = "dbw-${var.prefix}-${local.suffix}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  sku                         = var.databricks_sku
  managed_resource_group_name = "rg-${var.prefix}-dbw-managed-${local.suffix}"
  tags                        = var.tags
}

# The identity Unity Catalog uses to read and write the lake (a "storage credential"), so no
# notebook or cluster ever holds a storage key or service principal secret.
resource "azurerm_databricks_access_connector" "this" {
  name                = "dbac-${var.prefix}-${local.suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ---------------- Synapse (serverless SQL only; no dedicated pool = no idle cost) ----------------
resource "azurerm_synapse_workspace" "this" {
  # checkov:skip=CKV_AZURE_157: data exfiltration protection needs a managed VNet, out of scope here (see README)
  # checkov:skip=CKV2_AZURE_19: public network access kept so Power BI can reach the serverless endpoint; logins are Entra ID only
  # checkov:skip=CKV_AZURE_58: managed VNet is out of scope, same as CKV_AZURE_157
  # checkov:skip=CKV_AZURE_240: customer-managed keys are out of scope; serverless pools store no data of their own
  # checkov:skip=CKV2_AZURE_53: audit logs need a Log Analytics workspace, which this project does not deploy (see README)
  name                                 = "syn-${var.prefix}-${local.suffix}"
  resource_group_name                  = azurerm_resource_group.this.name
  location                             = azurerm_resource_group.this.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_container.lake["synapse"].id

  # Entra ID only: no SQL username and password exists for anyone to leak or reuse.
  azuread_authentication_only = true

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_synapse_workspace_aad_admin" "this" {
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  login                = "platform-admin"
  object_id            = local.admin_object_id
  tenant_id            = data.azurerm_client_config.current.tenant_id
}

resource "azurerm_synapse_firewall_rule" "azure_services" {
  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

# ---------------- RBAC: every service reaches the lake with its managed identity ----------------
locals {
  lake_writers = {
    data_factory = azurerm_data_factory.this.identity[0].principal_id
    synapse      = azurerm_synapse_workspace.this.identity[0].principal_id
    databricks   = azurerm_databricks_access_connector.this.identity[0].principal_id
  }
}

resource "azurerm_role_assignment" "lake_writers" {
  for_each             = local.lake_writers
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "admin_key_vault" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = local.admin_object_id
}

# Lets the administrator create containers and inspect data with their own identity (shared keys
# are disabled, so there is no other way in).
resource "azurerm_role_assignment" "admin_lake" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = local.admin_object_id
}
