@description('Resource location')
param location string

@description('The virtual network name')
param vnetName string

@description('The name of the subnet')
param subnetName string

@description('The virtual network address prefixes')
param vnetAddressPrefixes array

@description('The subnet address prefix')
param subnetAddressPrefix string

@description('Tags for the resources')
param tags object

@description('The virtual network address prefixes')
param allowedCidrRanges array

@description('Open HTTP for everyone to access - required for validate domain for a letsencrypt certificate. All other traffic is redirected to HTTPS')
param openHttpForAll bool = false

resource vnetSG 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
    name: '${vnetName}-sg'
    location: location
    tags: tags
    properties: {
        securityRules: concat([
                {
                    name: 'HTTPS-IP-Allow'
                    type: 'Microsoft.Network/networkSecurityGroups/securityRules'
                    properties: {
                        priority: 550
                        description: 'Open HTTPS for specific IPs.'
                        direction: 'Inbound'
                        protocol: 'Tcp'
                        sourcePortRange: '*'
                        sourceAddressPrefixes: allowedCidrRanges
                        destinationPortRange: '443'
                        destinationAddressPrefix: '*'
                        access: 'Allow'
                    }
                }
            ], openHttpForAll == true ? [
                {
                    name: 'HTTP-ALL-Allow'
                    type: 'Microsoft.Network/networkSecurityGroups/securityRules'
                    properties: {
                        priority: 500
                        description: 'Allow all to access HTTP - all requests are redirected to HTTPS except for the temporary endpoint used for letsencrypt domain verification'
                        direction: 'Inbound'
                        protocol: 'Tcp'
                        sourcePortRange: '*'
                        sourceAddressPrefix: 'Internet'
                        destinationPortRange: '80'
                        destinationAddressPrefix: '*'
                        access: 'Allow'
                    }
                }
            ] : [])
    }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: vnetAddressPrefixes
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
           networkSecurityGroup: {
            id: vnetSG.id
           }
           privateEndpointNetworkPolicies: 'Disabled'
           serviceEndpoints: [
            {
                service: 'Microsoft.Storage'
            }
           ]
        }
      }
    ]
  }
}

output subnetId string = '${vnet.id}/subnets/${subnetName}'
