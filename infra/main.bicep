// Azure data platform for the Toronto open-data pipeline.
// Deploys: ADLS Gen2 storage (bronze/silver/gold containers), Data Factory, Databricks workspace with a
// Unity Catalog access connector, Synapse workspace with a serverless SQL pool, Key Vault. Every service
// reaches the lake with its managed identity; storage keys and SQL passwords are disabled.
// infra/terraform/ deploys the same platform with Terraform.
//
//   az group create -n rg-toronto-data -l canadacentral
//   az deployment group create -g rg-toronto-data -f infra/main.bicep -p infra/main.bicepparam

targetScope = 'resourceGroup'

@description('Short name used as a prefix for every resource. Lowercase letters and digits only.')
@minLength(3)
@maxLength(12)
param prefix string = 'tordata'

@description('Azure region. Canada Central keeps the data in-country.')
param location string = resourceGroup().location

@description('Object ID of the user who will administer Key Vault and Synapse (az ad signed-in-user show --query id -o tsv).')
param adminObjectId string

@description('premium is required for Unity Catalog, which the notebooks use to reach the lake.')
@allowed(['standard', 'premium'])
param databricksSku string = 'premium'

var suffix = uniqueString(resourceGroup().id)
var storageName = toLower('${prefix}${suffix}')
var containers = ['bronze', 'silver', 'gold', 'synapse']

// ---------------- ADLS Gen2 ----------------
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take(storageName, 24)
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    isHnsEnabled: true               // hierarchical namespace = ADLS Gen2
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false      // Entra ID + RBAC only; no account keys exist to leak
    defaultToOAuthAuthentication: true
    isLocalUserEnabled: false
    encryption: {
      requireInfrastructureEncryption: true
      keySource: 'Microsoft.Storage'
      services: { blob: { enabled: true }, file: { enabled: true } }
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource lakeContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for c in containers: {
  parent: blobService
  name: c
}]

// ---------------- Key Vault ----------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take('kv-${prefix}-${suffix}', 24)
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
  }
}

// ---------------- Data Factory ----------------
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: 'adf-${prefix}-${suffix}'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {}
}

// ---------------- Databricks ----------------
resource databricks 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: 'dbw-${prefix}-${suffix}'
  location: location
  sku: { name: databricksSku }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', 'rg-${prefix}-dbw-managed-${suffix}')
  }
}

// Unity Catalog storage credential: the identity Databricks uses to read and write the lake.
resource accessConnector 'Microsoft.Databricks/accessConnectors@2024-05-01' = {
  name: 'dbac-${prefix}-${suffix}'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {}
}

// ---------------- Synapse (serverless SQL only; no dedicated pool = no idle cost) ----------------
resource synapse 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: 'syn-${prefix}-${suffix}'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: storage.properties.primaryEndpoints.dfs
      filesystem: 'synapse'
    }
    azureADOnlyAuthentication: true  // Entra ID logins only; no SQL password exists
  }
  dependsOn: [lakeContainers]
}

resource synapseEntraAdmin 'Microsoft.Synapse/workspaces/administrators@2021-06-01' = {
  parent: synapse
  name: 'activeDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: 'platform-admin'
    sid: adminObjectId
    tenantId: subscription().tenantId
  }
}

resource synapseFirewallAzure 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapse
  name: 'AllowAllWindowsAzureIps'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

// ---------------- RBAC: ADF and Synapse read/write the lake; admin owns Key Vault ----------------
var storageBlobDataContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var keyVaultAdministrator = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
var storageBlobDataOwner = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')

resource adfLakeAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, dataFactory.id, storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataContributor
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource synapseLakeAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, synapse.id, storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataContributor
    principalId: synapse.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource databricksLakeAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, accessConnector.id, storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataContributor
    principalId: accessConnector.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// With shared keys disabled, the administrator reaches the data with their own identity.
resource adminLake 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, adminObjectId, storageBlobDataOwner)
  scope: storage
  properties: {
    roleDefinitionId: storageBlobDataOwner
    principalId: adminObjectId
    principalType: 'User'
  }
}

resource adminKeyVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, adminObjectId, keyVaultAdministrator)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultAdministrator
    principalId: adminObjectId
    principalType: 'User'
  }
}

output storageAccountName string = storage.name
output dataFactoryName string = dataFactory.name
output databricksWorkspaceUrl string = databricks.properties.workspaceUrl
output synapseServerlessEndpoint string = synapse.properties.connectivityEndpoints.sql
output keyVaultName string = keyVault.name
output databricksAccessConnectorId string = accessConnector.id
