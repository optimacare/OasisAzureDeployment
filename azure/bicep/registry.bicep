@description('Resource location')
param location string = resourceGroup().location

@description('The name of the container registry')
param registryName string

@description('The principal ID of the AKS cluster')
param aksPrincipalId string

@description('Tags for the resources')
param tags object

// acdd72a7-3385-48ef-bd42-f606fba81ae7 - Azure role Reader
param roleAcrPull string = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2019-05-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
  }
  tags: tags
}

resource assignAcrPullToAks 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, registryName, aksPrincipalId, 'AssignAcrPullToAks')
  scope: containerRegistry
  properties: {
    description: 'Assign AcrPull role to AKS'
    principalId: aksPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${roleAcrPull}'
  }
}

output name string = containerRegistry.name

