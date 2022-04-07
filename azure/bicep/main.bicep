@description('Resource location')
param location string = resourceGroup().location

@description('The name of the cluster')
param clusterName string

@description('The VM size to use for the platform cluster node')
param platformNodeVm string

@description('The VM Size to use for each worker cluster node')
param workerNodesVm string

@description('Max number of worker nodes to scale up to')
param workerNodesMaxCount int = 1

@description('Availability zones to use for the cluster nodes')
param availabilityZones array = []

@description('Log Analytics Workspace Tier')
param workspaceTier string

@description('The virtual network address prefixes')
param vnetAddressPrefixes array

@description('The subnet address prefix')
param subnetAddressPrefix string

@description('The virtual network address prefixes')
param allowedCidrRanges array

@description('Tags for the resources')
param tags object

@description('Open HTTP for everyone to access - required for validate domain for a letsencrypt certificate. All other traffic is redirected to HTTPS')
param openHttpForAll bool = false

@description('The name of the container registry')
param registryName string

@description('The name of the Key Vault.')
param keyVaultName string = 'oasis-${uniqueString(resourceGroup().id)}'

@description('Azure storage SKU type')
param oasisStorageAccountSKU string = 'Standard_LRS'

@description('Name of resource group for aks node')
param nodeResourceGroup string

@description('Current user object id - if set will add access for this user to the key vault')
param currentUserObjectId string = ''

@description('Password for admin user')
param oasisServerAdminPassword string

@description('Name of virtual network')
param vnetName string = '${clusterName}-vnet'

@description('Name of sub network')
param subnetName string = '${clusterName}-snet'

module vnet 'vnet.bicep' = {
  name: 'vnetDeploy'
  params: {
    location: location
    vnetName: vnetName
    subnetName: subnetName
    vnetAddressPrefixes: vnetAddressPrefixes
    subnetAddressPrefix: subnetAddressPrefix
    allowedCidrRanges: allowedCidrRanges
    tags: tags
    openHttpForAll: openHttpForAll
  }

  dependsOn: [
  ]
}

module identities 'identities.bicep' = {
  name: 'identities'
  params: {
    location: location
    clusterName: clusterName
    tags: tags
  }

  dependsOn: [
    vnet
  ]
}

module keyVault 'key_vault.bicep' = {
  name: 'keyVault'
  params: {
    location: location
    keyVaultName: keyVaultName
    userAssignedIdentity: identities.outputs.userAssignedIdentity
    currentUserObjectId: currentUserObjectId
    tags: tags
  }

  dependsOn: [
    identities
  ]
}

module oasisPostgresqlDb 'postgresql.bicep' = {
  name: 'oasisPostgresqlDb'
  params: {
    location: location
    tags: tags
    keyVaultName: keyVault.outputs.keyVaultName
    oasisServerAdminPassword: oasisServerAdminPassword
    vnetName: vnetName
    subnetName: subnetName
  }

  dependsOn: [
    vnet
  ]
}

module celeryRedis 'redis.bicep' = {
  name: 'celeryRedis'
  params: {
    location: location
    tags: tags
    keyVaultName: keyVault.outputs.keyVaultName
    vnetName: vnetName
    subnetName: subnetName
  }

  dependsOn: [
    vnet
  ]
}

module storageAccount 'storage_account.bicep' = {
  name: 'storageAccount'
  params: {
    location: location
    keyVaultName: keyVault.outputs.keyVaultName
    oasisStorageAccountSKU: oasisStorageAccountSKU
    tags: tags
    subnetId: vnet.outputs.subnetId
    allowedCidrRanges: allowedCidrRanges
  }

  dependsOn: [
    vnet
  ]
}

module aks 'aks.bicep' = {
  name: 'aksDeploy'
  params: {
    location: location
    clusterName: clusterName
    subnetId: vnet.outputs.subnetId
    platformNodeVm: platformNodeVm
    workerNodesVm: workerNodesVm
    workerNodesMaxCount: workerNodesMaxCount
    availabilityZones: availabilityZones
    nodeResourceGroup: nodeResourceGroup
    workspaceTier: workspaceTier
    tags: tags
    keyVaultName: keyVault.outputs.keyVaultName
  }

  dependsOn: [
    storageAccount
  ]
}

module registry 'registry.bicep' = {
  name: 'registryDeploy'
  params: {
    location: location
    registryName: registryName
    aksPrincipalId: aks.outputs.clusterPrincipalID
    tags: tags
  }

  dependsOn: [
    aks
  ]
}

output oasisFsNameSecretName string = storageAccount.outputs.oasisFsNameSecretName
output oasisFsKeySecretName string = storageAccount.outputs.oasisFsKeySecretName
output oasisFileShareName string = storageAccount.outputs.oasisFileShareName
output modelsFileShareName string = storageAccount.outputs.modelsFileShareName
output aksCluster object = aks.outputs.aksCluster
