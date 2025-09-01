@description('Environment name (dev, test, uat, staging, prod)')
param environment string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Application version')
param appVersion string = '1.0.0'

@description('Enable monitoring and logging')
param enableMonitoring bool = true

@description('Azure DevOps organization name')
param devOpsOrganization string

@description('Azure subscription ID for service principal')
param subscriptionId string = subscription().subscriptionId

@description('Azure AD tenant ID')
param tenantId string = subscription().tenantId

// Variables
var appName = 'sdr'
var resourceSuffix = '${appName}-${environment}-${locationShort(location)}'
var environmentCodes = {
  development: 'dev'
  testing: 'test'
  useracceptance: 'uat'
  staging: 'stage'
  production: 'prod'
}

// Helper function to get location short code
func locationShort(location string) string => contains(environments().locations, location) ? environments().locations[location].metadata.pairCode : 'uksouth'

// Target subscription for resource group deployment
targetScope = 'subscription'

// Resource Group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${resourceSuffix}'
  location: location
  tags: {
    Application: 'SDR-Management-System'
    Environment: environment
    Version: appVersion
    CreatedDate: utcNow('yyyy-MM-dd')
    CostCenter: 'IT-001'
    Project: 'SDR-001'
    Customized: 'false'
    DataClassification: 'Internal'
  }
}

// Deploy core infrastructure (Storage, App Insights, Key Vault if prod)
module coreInfrastructure 'modules/core-infrastructure.bicep' = {
  name: 'core-infrastructure-${uniqueString(resourceSuffix)}'
  scope: resourceGroup
  params: {
    environment: environment
    location: location
    resourceSuffix: resourceSuffix
    enableMonitoring: enableMonitoring
    subscriptionId: subscriptionId
    tenantId: tenantId
  }
}

// Deploy application services (Function Apps, Static Web App)
module applicationServices 'modules/application-services.bicep' = {
  name: 'application-services-${uniqueString(resourceSuffix)}'
  scope: resourceGroup
  params: {
    environment: environment
    location: location
    resourceSuffix: resourceSuffix
    storageAccountName: coreInfrastructure.outputs.storageAccountName
    keyVaultName: coreInfrastructure.outputs.keyVaultName
    keyVaultId: coreInfrastructure.outputs.keyVaultId
    applicationInsightsKey: coreInfrastructure.outputs.applicationInsightsKey
    devOpsOrganization: devOpsOrganization
    subscriptionId: subscriptionId
    tenantId: tenantId
  }
  dependsOn: [
    coreInfrastructure
  ]
}

// Outputs
output resourceGroupName string = resourceGroup.name
output resourceGroupId string = resourceGroup.id
output storageAccountName string = coreInfrastructure.outputs.storageAccountName
output storageAccountId string = coreInfrastructure.outputs.storageAccountId
output keyVaultName string = coreInfrastructure.outputs.keyVaultName
output functionAppName string = applicationServices.outputs.functionAppName
output functionAppId string = applicationServices.outputs.functionAppId
output staticWebAppName string = applicationServices.outputs.staticWebAppName
output staticWebAppId string = applicationServices.outputs.staticWebAppId
output applicationInsightsName string = coreInfrastructure.outputs.applicationInsightsName
output applicationInsightsKey string = coreInfrastructure.outputs.applicationInsightsKey
