@description('Environment name')
param environment string

@description('Location for resources')
param location string

@description('Resource naming suffix')
param resourceSuffix string

@description('Enable monitoring')
param enableMonitoring bool = true

@description('Azure subscription ID')
param subscriptionId string

@description('Azure AD tenant ID')
param tenantId string

// Variables for resource configuration
var storageAccountName = replace('stsdr${resourceSuffix}', '-', '')  // Remove hyphens for storage
var keyVaultName = 'kv-sdr-${environment}-${substring(location, 0, 10)}'
var appInsightsName = 'ai-sdr-${environment}-${substring(location, 0, 10)}'
var logAnalyticsName = 'law-sdr-${environment}-${substring(location, 0, 10)}'

// Storage Account - Deployed in all environments
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: environment == 'prod' ? 'Standard_ZRS' : 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: true
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: environment == 'prod' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
      virtualNetworkRules: environment == 'prod' ? [] : []
      ipRules: environment == 'prod' ? [] : []
    }
    supportsHttpsTrafficOnly: true
    isHnsEnabled: false  // Hierarchical namespace for ADLS Gen2
    isSftpEnabled: false
    isNfsV3Enabled: false
  }

  tags: {
    Application: 'SDR-Management-System'
    Environment: environment
    ResourceType: 'Storage'
    BackupRequired: 'Yes'
  }
}

// Create storage containers
resource attachmentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/attachments'
  properties: {
    publicAccess: 'None'
    metadata: {
      Purpose: 'SDR File Attachments'
      Environment: environment
    }
  }
  dependsOn: [
    storageAccount
  ]
}

resource aiProcessingContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/ai-processing'
  properties: {
    publicAccess: 'None'
    metadata: {
      Purpose: 'AI Processing Artifacts'
      Environment: environment
    }
  }
  dependsOn: [
    storageAccount
  ]
}

resource exportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/exports'
  properties: {
    publicAccess: 'None'
    metadata: {
      Purpose: 'Generated Reports and Exports'
      Environment: environment
    }
  }
  dependsOn: [
    storageAccount
  ]
}

// Log Analytics Workspace - For monitoring environments
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableMonitoring) {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: environment == 'prod' ? 90 : 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      clusterResourceId: null
    }
  }

  tags: {
    Application: 'SDR-Management-System'
    Environment: environment
    ResourceType: 'Monitoring'
  }
}

// Application Insights - For all environments with monitoring enabled
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableMonitoring) {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableMonitoring ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    DisableLocalAuth: false
    ForceCustomerStorageForProfiler: false
  }

  tags: {
    Application: 'SDR-Management-System'
    Environment: environment
    ResourceType: 'Monitoring'
  }
}

// Key Vault - PRODUCTION ONLY
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = if (environment == 'prod') {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    accessPolicies: []  // Will be set by service principal deployment
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    softDeleteRetentionInDays: 90
  }

  tags: {
    Application: 'SDR-Management-System'
    Environment: environment
    ResourceType: 'Security'
    Criticality: 'High'
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output keyVaultName string = environment == 'prod' ? keyVault.name : ''
output keyVaultId string = environment == 'prod' ? keyVault.id : ''
output applicationInsightsName string = enableMonitoring ? applicationInsights.name : ''
output applicationInsightsKey string = enableMonitoring ? applicationInsights.properties.InstrumentationKey : ''
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.id : ''
