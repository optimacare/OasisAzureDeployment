@description('The name of the Managed Cluster resource')
param clusterName string

@description('Resource location')
param location string = resourceGroup().location

@description('Kubernetes version to use')
param kubernetesVersion string = '1.27.7'

@description('The VM Size to use for the platform')
param platformNodeVm string

@description('The VM Size to use for each worker node')
param workerNodesVm string

@maxValue(10)
@description('Max number of nodes to scale up to')
param workerNodesMaxCount int = 1

@description('Availability zones to use for the cluster nodes')
param availabilityZones array

@description('Tags for the resources')
param tags object

@description('Log Analytics Workspace Tier')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
  'Premium'
])
param workspaceTier string = 'PerGB2018'

@allowed([
  'azure'
])
@description('Network plugin used for building Kubernetes network')
param networkPlugin string = 'azure'

@description('Subnet id to use for the cluster')
param subnetId string

@description('Cluster services IP range')
param serviceCidr string = '10.0.0.0/16'

@description('DNS Service IP address')
param dnsServiceIP string = '10.0.0.10'

@description('Docker Bridge IP range')
param dockerBridgeCidr string = '172.17.0.1/16'

@description('Name of resource group for aks node')
param nodeResourceGroup string = '${clusterName}-aks'

@description('Name of key vault')
param keyVaultName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: '${clusterName}-oms'
  location: location
  properties: {
    sku: {
      name: workspaceTier
    }
  }
  tags: tags
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2021-03-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    nodeResourceGroup: nodeResourceGroup
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${clusterName}-dns'
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'platform'
        count: 1
        enableAutoScaling: false
        vmSize: platformNodeVm
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        availabilityZones: availabilityZones
        vnetSubnetID: subnetId
        nodeLabels: {
          'oasislmf/node-type': 'platform'
        }
      }
      {
        name: 'workers'
        count: 1
        enableAutoScaling: true
        minCount: 1
        maxCount: workerNodesMaxCount
        vmSize: workerNodesVm
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        availabilityZones: availabilityZones
        vnetSubnetID: subnetId
        nodeLabels: {
          'oasislmf/node-type': 'worker'
        }
      }
    ]
    networkProfile: {
      loadBalancerSku: 'standard'
      networkPlugin: networkPlugin
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      dockerBridgeCidr: dockerBridgeCidr
    }
    addonProfiles: {
      azurepolicy: {
        enabled: false
      }
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        }
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
      }
    }
  }
}

resource symbolicname 'Microsoft.KeyVault/vaults/accessPolicies@2021-11-01-preview' = {
  name: '${keyVaultName}/add'
  properties: {
    accessPolicies: [
      {
        objectId: aksCluster.properties.identityProfile.kubeletidentity.objectId
        permissions: {
          secrets: [
            'list'
            'get'
          ]
        }
        tenantId: subscription().tenantId
      }
    ]
  }
}

output controlPlaneFQDN string = reference('${clusterName}').fqdn
output clusterPrincipalID string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output aksCluster object = aksCluster
