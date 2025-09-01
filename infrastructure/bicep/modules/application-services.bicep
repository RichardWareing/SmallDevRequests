@description('Environment name')
param environment string

@description('Location for resources')
param location string

@description('Resource naming suffix')
param resourceSuffix string

@description('Storage account name')
param storageAccountName string

@description('Key Vault name')  // Production only
param keyVaultName string

@description('Key Vault ID')  // Production only
param keyVaultId string

@description('Application Insights instrumentation key')
param applicationInsightsKey string

@description('Azure DevOps organization name')
param devOpsOrganization string

@description('Azure subscription ID')
param subscriptionId string

@description('Azure AD tenant ID')
param tenantId string

// Variables
var functionAppName = 'func-sdr-${environment}-${substring(location, 0, 10)}'
var staticWebAppName = 'swa-sdr-${environment}-${substring(location, 0, 10)}'
var appServicePlanName = 'asp-sdr-${environment}-${substring(location, 0, 10)}'

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: environment == 'prod' ? 'EP1' : 'Y1'  // Premium for prod, Consumption for dev/test
    tier: environment == 'prod' ? 'ElasticPremium' : 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: false  // Windows hosting
    targetWorkerCount: environment == 'prod' ? 3 : 1
    targetWorkerSizeId: environment == 'prod' ? 1 : 0
  }

  tags: {
    Application: 'SDR-Management-System'
    Environment: environment
    ResourceType: 'Compute'
    CostCenter: 'IT-001'
    Project: 'SDR-001'
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'UseDevelopmentStorage=true'  // Will be replaced during deployment
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'UseDevelopmentStorage=true'  // Will be replaced during deployment
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower('func-sdr-${environment}')
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${applicationInsightsKey}'
        }
        {
          name: 'NODE_ENV'
          value: environment == 'prod' ? 'production' : environment
        }
        {
          name: 'DEVOPS_ORGANIZATION'
          value: devOpsOrganization
        }
        {
          name: 'TENANT_ID'
          value: tenantId
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
          environment == 'prod' ? 'https://${staticWebAppName}.azurestaticapps.net' : 'https://localhost:3000'
          environment != 'prod' ? 'https://${staticWebAppName}.azurestaticapps.net' : ''
        ]
        supportCredentials: false
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
    }
  }

  tags: {
    Application: 'SDR-Management-System'
    Environment: environment
    ResourceType: 'Compute'
    Criticality: environment == 'prod' ? 'High' : 'Standard'
  }

  dependsOn: [
    appServicePlan
  ]
}

// Grant Function App access to Key Vault (production only)
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = if (environment == 'prod' && !empty(keyVaultName)) {
  name: '${keyVaultName}/add'
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: functionApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }

  dependsOn: [
    functionApp
  ]
}

// Static Web App
resource staticWebApp 'Microsoft.Web/staticSites@2022-03-01' = {
  name: staticWebAppName
  location: location
  sku: {
    name: environment == 'prod' ? 'Standard' : 'Free'
    tier: environment == 'prod' ? 'Standard' : 'Free'
  }
  properties: {
    buildProperties: {
      appLocation: '/'
      apiLocation: 'api'
      outputLocation: 'build'
      skipGithubActionWorkflowGeneration: true
    }
    stagingEnvironmentPolicy: environment == 'prod' ? 'Disabled' : 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: environment == 'prod' ? 'Enabled' : 'Disabled'
    templateProperties: {
      isGitHubAction: false
      repositoryUrl: ''
      branch: ''
      buildCommand: 'npm run build'
      apiBuildCommand: 'npm run build'
      appBuildCommand: 'npm run build'
      outputLocation: 'build'
    }
  }

  tags: {
    Application: 'SDR-Management-System'
    Environment: environment
    ResourceType: 'Web'
    CostCenter: 'IT-001'
    Project: 'SDR-001'
  }
}

// NOTE: Key Vault secrets will be created during deployment pipeline

// Outputs
output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output staticWebAppName string = staticWebApp.name
output staticWebAppId string = staticWebApp.id
output appServicePlanId string = appServicePlan.id
output functionAppIdentityPrincipalId string = functionApp.identity.principalId
