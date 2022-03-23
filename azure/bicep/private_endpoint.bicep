
@description('Resource location')
param location string

@description('The virtual network name')
param vnetName string

@description('The name of the subnet')
param subnetName string

@description('Private DNS zone name. Will be used as <service>.<privateDNSZoneName>')
param privateDNSZoneName string

@description('Tags for the resources')
param tags object

@description('Service ID to link to')
param privateLinkServiceId string

@description('Group id for service link')
param privateLinkGroupId string

@description('Name of server to link to. This will be part of the domain name.')
param serverName string

@description('Name of key vault')
param keyVaultName string

@description('Name of the private endpoint')
param privateEndpointName string

@description('Name of the secret to store the hostname')
param secretHostName string

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
     subnet: {
       id: resourceId('Microsoft.Network/VirtualNetworks/subnets', vnetName, subnetName)
     }
     privateLinkServiceConnections: [
       {
         name: 'db-connection'
         properties: {
           privateLinkServiceId: privateLinkServiceId
           groupIds: [
            privateLinkGroupId
           ]
         }
       }
     ]
  }
}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDNSZoneName
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZones
  name: '${privateDnsZones.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: resourceId('Microsoft.Network/VirtualNetworks', vnetName)
    }
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-08-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: privateDNSZoneName
        properties: {
          privateDnsZoneId: privateDnsZones.id
        }
      }
    ]
  }
}

resource oasisServerDbName 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  name: '${keyVaultName}/${secretHostName}'
  tags: tags
  properties: {
    attributes: {
      enabled: true
    }
    value: '${serverName}.${privateDNSZoneName}'
  }
}
