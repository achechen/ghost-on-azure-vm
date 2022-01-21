targetScope = 'resourceGroup'

@description('URL of the production instance of ghost. Example: http://mysite.local')
param ghostProdUrl string

@description('Ghost production instance administrator username')
param ghostProdUsername string

@description('Ghost production instance administrator password')
@secure()
param ghostProdPassword string

@description('URL of the production instance of ghost. Example: http://mysite-staging.local')
param ghostStagingUrl string

@description('Ghost staging instance administrator username')
param ghostStagingUsername string

@description('Ghost staging instance administrator password')
@secure()
param ghostStagingPassword string

@description('Prefix that will be used to generate unique resource names')
param prefix string

@description('Location to deploy the resources')
param location string = resourceGroup().location

@description('SKU of the hosting plan for function app')
param hostingPlansku string = 'S1'

//@description('The instance size of he hosting plan.')
//@allowed([
//  '0'
//  '1'
//  '2'
//])
//param workerSize string = '0'

@description('Storage account sku')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('URL of the GitHub repository that contains the app')
param repoUrl string = 'https://github.com/achechen/ghostoperations.git'

@description('Branh of GitHub repo to use')
param branch string = 'main'

var functionAppName = '${prefix}-fa-${uniqueString(resourceGroup().id)}'
var hostingPlanName = '${prefix}-fa-plan-${uniqueString(resourceGroup().id)}'
var storageAccountName = '${prefix}sa${uniqueString(resourceGroup().id)}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
}

resource hostingPlan 'Microsoft.Web/serverfarms@2020-12-01' = {
  name: hostingPlanName
  location: location
  kind: 'linux'
  sku: {
    name: hostingPlansku
    tier: 'Standard'
  }
  properties: {
    //workerSize: workerSize
    //numberOfWorkers: 1
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2020-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    //name: functionAppName
    serverFarmId: hostingPlan.id
    clientAffinityEnabled: false
    siteConfig: {
      alwaysOn: true
      use32BitWorkerProcess: false
      linuxFxVersion: 'Python|3.9'
      cors: {
        allowedOrigins: [
          '*'
        ]
      }
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${listkeys(storageAccount.id, '2019-06-01').keys[0].value};'
        }
        {
          name: 'AzureWebJobsDashboard'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${listkeys(storageAccount.id, '2019-06-01').keys[0].value};'
        }
        {
          name: 'GHOST_PROD_URL'
          value: ghostProdUrl
        }
        {
          name: 'GHOST_PROD_USERNAME'
          value: ghostProdUsername
        }
        {
          name: 'GHOST_PROD_PASSWORD'
          value: ghostProdPassword
        }
        {
          name: 'GHOST_STAGING_URL'
          value: ghostStagingUrl
        }
        {
          name: 'GHOST_STAGING_USERNAME'
          value: ghostStagingUsername
        }
        {
          name: 'GHOST_STAGING_PASSWORD'
          value: ghostStagingPassword
        }
      ]
    }
  }
}

resource functionAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2018-11-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    repoUrl: repoUrl
    branch: branch
    isManualIntegration: true
  }
}

output functionAppUrl string = functionApp.properties.defaultHostName
