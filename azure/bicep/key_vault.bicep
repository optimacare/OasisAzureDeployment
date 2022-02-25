@description('Resource location')
param location string = resourceGroup().location

@description('The Tenant Id that should be used throughout the deployment.')
param tenantId string = subscription().tenantId

@description('The name of the Key Vault.')
param keyVaultName string

@description('Tags for the resources')
param tags object

// TODO
param userAssignedIdentity object

// TODO
param currentUserObjectId string = ''

var accessPolicies = concat([
    {
     tenantId: tenantId
     permissions: {
       secrets: [
         'get'
         'list'
       ]
     }
     objectId: userAssignedIdentity.properties.principalId
    }
    {
     tenantId: tenantId
     permissions: {
       secrets: [
         'all' // TODO strict https://docs.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults?tabs=bicep#permissions
       ]
     }
     objectId: 'c6a0e57a-62db-4d77-8010-7b62c1104085' // TODO remove. Johan Nilsson account
   }
], empty(currentUserObjectId) == true ? [] : [
    {
     tenantId: tenantId
     permissions: {
       secrets: [
         'all'
       ]
     }
     objectId: currentUserObjectId
    }
])

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    enableSoftDelete: true
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    tenantId: tenantId
    accessPolicies: accessPolicies
  }
}

output keyVaultName string = keyVaultName
output keyVaultUri string = keyVault.properties.vaultUri
