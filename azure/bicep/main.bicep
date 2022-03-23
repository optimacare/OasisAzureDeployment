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
    vnet
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
