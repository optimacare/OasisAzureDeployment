@description('Resource location')
param location string = resourceGroup().location

@description('The name of the User Assigned Identity.')
param userAssignedIdentityName string = 'assignedidentityuser' // TODO

@description('Tags for the resources')
param tags object

// TODO
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: userAssignedIdentityName
  location: location
  tags: tags
}

output userAssignedIdentity object = userAssignedIdentity

