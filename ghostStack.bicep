targetScope = 'resourceGroup'

@description('Prefix that will be used to generate unique resource names')
param prefix string

@description('The size of the VM')
@allowed([
  'Standard_DS1_v2'
])
param virtualMachineSize string = 'Standard_DS1_v2'

@description('OD Disk Type')
@allowed([
  'StandardSSD_LRS'
])
param osDiskType string = 'StandardSSD_LRS'

@description('Virtual Machine Administrator username')
param adminUsername string

@secure()
@description('Virtual Machine Administrator password')
param adminPassword string

@description('Location to deploy the resources')
param location string = resourceGroup().location

@description('Name of the virtual network in which the VM will be hosted')
param virtualNetworkName string

@description('Name of the subnet in which the VM will be hosted')
param subnetName string

@description('Ghost site name')
param siteName string

@description('URL of the site (example: mysite.com)')
param siteUrl string

@description('Database user')
param dbUser string

@description('Database password')
@secure()
param dbPassword string

@description('Ghost Administrator full name')
param ghostAdminUser string

@description('Ghost Administrator password')
@secure()
param ghostAdminPassword string

@description('Ghost administrator e-mail address, will be used as login name')
param ghostAdminEmail string

@allowed([
  'B_Gen5_1'
  'B_Gen5_2'
])
@description('SKU of the mysql server')
param mysqlServerSku string = 'B_Gen5_1'

var dbHost = mysqlServer.properties.fullyQualifiedDomainName
var mysqlServerName = '${prefix}-mysql-${uniqueString(resourceGroup().id)}'
var subnetRef = '${virtualNetwork.id}/subnets/${subnetName}'
var networkInterfaceName = '${prefix}-nic-${uniqueString(resourceGroup().id)}'
var virtualMachineName = '${prefix}-vm-${uniqueString(resourceGroup().id)}'
var publicIpAddressName = '${prefix}-publicIp-${uniqueString(resourceGroup().id)}'
var dbLogin = '${dbUser}@${mysqlServer.name}'
var initScriptContent = loadTextContent('initscript.sh')
var initScriptContentReplace1 = replace(initScriptContent, '<<sitename>>', siteName)
var initScriptContentReplace2 = replace(initScriptContentReplace1, '<<username>>', adminUsername)
var initScriptContentReplace3 = replace(initScriptContentReplace2, '<<siteurl>>', siteUrl)
var initScriptContentReplace4 = replace(initScriptContentReplace3, '<<dbhost>>', dbHost)
var initScriptContentReplace5 = replace(initScriptContentReplace4, '<<dbuser>>', dbLogin)
var initScriptContentReplace6 = replace(initScriptContentReplace5, '<<dbpassword>>', dbPassword)
var initScriptContentReplace7 = replace(initScriptContentReplace6, '<<ghostadminuser>>', ghostAdminUser)
var initScriptContentReplace8 = replace(initScriptContentReplace7, '<<ghostadminpass>>', ghostAdminPassword)
var initScriptFinal = replace(initScriptContentReplace8, '<<ghostadminemail>>', ghostAdminEmail)

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: virtualNetworkName
}

resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: publicIpAddressName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetRef
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpAddress.id
          }
        }
      }
    ]
    enableAcceleratedNetworking: false
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: virtualMachineName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: virtualMachineName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        patchSettings: {
          patchMode: 'ImageDefault'
        }
      }
      customData: base64(initScriptFinal)
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource mysqlServer 'Microsoft.DBforMySQL/servers@2017-12-01' = {
  name: mysqlServerName
  location: location
  sku: {
    name: mysqlServerSku
    tier: 'Basic'
  }
  properties: {
    createMode: 'Default'
    version: '5.7'
    sslEnforcement: 'Enabled'
    minimalTlsVersion: 'TLS1_2'
    administratorLogin: dbUser
    administratorLoginPassword: dbPassword
  }
}

resource firewallRules 'Microsoft.DBforMySQL/servers/firewallRules@2017-12-01' = {
  name: virtualMachine.name
  parent: mysqlServer
  properties: {
    endIpAddress: publicIpAddress.properties.ipAddress
    startIpAddress: publicIpAddress.properties.ipAddress
  }
}

var frontDoorProdName = '${prefix}-fd-prod-${uniqueString(resourceGroup().id)}'
var backendPoolProdName = '${frontDoorProdName}-backendPool'
var healthProbeProdName = '${frontDoorProdName}-healthProbe'
var frontendEndpointProdName = '${frontDoorProdName}-frontendEndpoint'
var loadBalancingProdName = '${frontDoorProdName}-loadBalancing'
var routingRuleProdName = '${frontDoorProdName}-routingRule'
var frontendEndpointProdhostName = '${frontDoorProdName}.azurefd.net'

var frontDoorStagingName = '${prefix}-fd-staging-${uniqueString(resourceGroup().id)}'
var backendPoolStagingName = '${frontDoorStagingName}-backendPool'
var healthProbeStagingName = '${frontDoorStagingName}-healthProbe'
var frontendEndpointStagingName = '${frontDoorStagingName}-frontendEndpoint'
var loadBalancingStagingName = '${frontDoorStagingName}-loadBalancing'
var routingRuleStagingName = '${frontDoorStagingName}-routingRule'
var frontendEndpointStaginghostName = '${frontDoorStagingName}.azurefd.net'

resource frontDoorProd 'Microsoft.Network/frontDoors@2020-05-01' = {
  name: frontDoorProdName
  location: 'global'
  properties: {
    routingRules: [
      {
        name: routingRuleProdName
        properties: {
          frontendEndpoints: [
            {
              id: resourceId('Microsoft.Network/frontDoors/frontendEndpoints', frontDoorProdName, frontendEndpointProdName)
            }
          ]
          acceptedProtocols: [
            'Http'
            'Https'
          ]
          patternsToMatch: [
            '/*'
          ]
          routeConfiguration: {
            '@odata.type': '#Microsoft.Azure.FrontDoor.Models.FrontdoorForwardingConfiguration'
            forwardingProtocol: 'HttpOnly'
            backendPool: {
              id: resourceId('Microsoft.Network/frontDoors/backendPools', frontDoorProdName, backendPoolProdName)
            }
            cacheConfiguration: {
              queryParameterStripDirective: 'StripNone'
              dynamicCompression: 'Enabled'
            }
          }
          enabledState: 'Enabled'
        }
      }
    ]
    healthProbeSettings: [
      {
        name: healthProbeProdName
        properties: {
          path: '/'
          protocol: 'Https'
          intervalInSeconds: 120
        }
      }
    ]
    loadBalancingSettings: [
      {
        name: loadBalancingProdName
        properties: {
          sampleSize: 4
          successfulSamplesRequired: 2
        }
      }
    ]
    backendPools: [
      {
        name: backendPoolProdName
        properties: {
          backends: [
            {
              address: publicIpAddress.properties.ipAddress
              backendHostHeader: siteUrl
              httpPort: 80
              httpsPort: 443
              weight: 50
              priority: 1
              enabledState: 'Enabled'
            }
          ]
          loadBalancingSettings: {
            id: resourceId('Microsoft.Network/frontDoors/loadBalancingSettings', frontDoorProdName, loadBalancingProdName)
          }
          healthProbeSettings: {
            id: resourceId('Microsoft.Network/frontDoors/healthProbeSettings', frontDoorProdName, healthProbeProdName)
          }
        }
      }
    ]
    frontendEndpoints: [
      {
        name: frontendEndpointProdName
        properties: {
          hostName: frontendEndpointProdhostName
          sessionAffinityEnabledState: 'Disabled'
        }
      }
    ]
    enabledState: 'Enabled'
  }
}

resource frontDoorStaging 'Microsoft.Network/frontDoors@2020-05-01' = {
  name: frontDoorStagingName
  location: 'global'
  properties: {
    routingRules: [
      {
        name: routingRuleStagingName
        properties: {
          frontendEndpoints: [
            {
              id: resourceId('Microsoft.Network/frontDoors/frontendEndpoints', frontDoorStagingName, frontendEndpointStagingName)
            }
          ]
          acceptedProtocols: [
            'Http'
            'Https'
          ]
          patternsToMatch: [
            '/*'
          ]
          routeConfiguration: {
            '@odata.type': '#Microsoft.Azure.FrontDoor.Models.FrontdoorForwardingConfiguration'
            forwardingProtocol: 'HttpOnly'
            backendPool: {
              id: resourceId('Microsoft.Network/frontDoors/backendPools', frontDoorStagingName, backendPoolStagingName)
            }
            cacheConfiguration: {
              queryParameterStripDirective: 'StripNone'
              dynamicCompression: 'Enabled'
            }
          }
          enabledState: 'Enabled'
        }
      }
    ]
    healthProbeSettings: [
      {
        name: healthProbeStagingName
        properties: {
          path: '/'
          protocol: 'Https'
          intervalInSeconds: 120
        }
      }
    ]
    loadBalancingSettings: [
      {
        name: loadBalancingStagingName
        properties: {
          sampleSize: 4
          successfulSamplesRequired: 2
        }
      }
    ]
    backendPools: [
      {
        name: backendPoolStagingName
        properties: {
          backends: [
            {
              address: publicIpAddress.properties.ipAddress
              backendHostHeader: 'staging_${siteUrl}'
              httpPort: 80
              httpsPort: 443
              weight: 50
              priority: 1
              enabledState: 'Enabled'
            }
          ]
          loadBalancingSettings: {
            id: resourceId('Microsoft.Network/frontDoors/loadBalancingSettings', frontDoorStagingName, loadBalancingStagingName)
          }
          healthProbeSettings: {
            id: resourceId('Microsoft.Network/frontDoors/healthProbeSettings', frontDoorStagingName, healthProbeStagingName)
          }
        }
      }
    ]
    frontendEndpoints: [
      {
        name: frontendEndpointStagingName
        properties: {
          hostName: frontendEndpointStaginghostName
          sessionAffinityEnabledState: 'Disabled'
        }
      }
    ]
    enabledState: 'Enabled'
  }
}

module functionApp 'modules/functionApp.bicep' = {
  name: 'functionAppDeployment'
  params: {
    ghostProdPassword: ghostAdminPassword
    ghostProdUrl: 'http://${frontendEndpointProdhostName}'
    ghostProdUsername: ghostAdminEmail
    ghostStagingPassword: ghostAdminPassword
    ghostStagingUrl: 'http://${frontendEndpointStaginghostName}'
    ghostStagingUsername: ghostAdminEmail
    prefix: prefix
  }
}

output virtualMachineName string = virtualMachine.name
output virtualMachinePublicIpAddress string = publicIpAddress.properties.ipAddress
output ghostProductionAddress string = 'http://${frontendEndpointProdhostName}'
output ghostStagingAddress string = 'http://${frontendEndpointStaginghostName}'
output functionUrl string = functionApp.outputs.functionAppUrl
