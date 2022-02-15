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
param keyVaultName string = 'oasis-enterprise'

module vnet 'vnet.bicep' = {
  name: 'vnetDeploy'
  params: {
    vnetName: '${clusterName}-vnet'
    subnetName: '${clusterName}-snet'
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
    tags: tags
  }

  dependsOn: [
    vnet
  ]
}

module keyVault 'key_vault.bicep' = {
  name: 'keyVault'
  params: {
    keyVaultName: keyVaultName
    userAssignedIdentity: identities.outputs.userAssignedIdentity
    tags: tags
  }

  dependsOn: [
    identities
  ]
}

module storageAccount 'storage_account.bicep' = {
  name: 'storageAccount'
  params: {
    userAssignedIdentity: identities.outputs.userAssignedIdentity
    keyVaultName: keyVault.outputs.keyVaultName
    keyVaultUri: keyVault.outputs.keyVaultUri
    tags: tags
  }

  dependsOn: [
    vnet
  ]
}

module aks 'aks.bicep' = {
  name: 'aksDeploy'
  params: {
    clusterName: clusterName
    subnetId: vnet.outputs.subnetId
    platformNodeVm: platformNodeVm
    workerNodesVm: workerNodesVm
    workerNodesMaxCount: workerNodesMaxCount
    availabilityZones: availabilityZones
    workspaceTier: workspaceTier
    tags: tags
  }

  dependsOn: [
    storageAccount
  ]
}

module registry 'registry.bicep' = {
  name: 'registryDeploy'
  params: {
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
