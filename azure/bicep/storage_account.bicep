@description('Resource location')
param location string = resourceGroup().location

@description('Storage account name')
param oasisStorageAccountName string = substring('oasis${uniqueString(resourceGroup().id)}', 0, 17)

//@description('The Tenant Id that should be used throughout the deployment.')
//param tenantId string = subscription().tenantId

@description('Tags for the resources')
param tags object

@description('Name of the key in the Key Vault') // TODO
param oasisFsNameSecretName string = 'oasisfs-name'

param oasisFsKeySecretName string = 'oasisfs-key'

param oasisFileShareName string = 'oasisfs'

param modelsFileShareName string = 'models'

//@description('Name of the key in the Key Vault')
//param encryptionKeyName string = 'oasisfs'

// TODO @description
param keyVaultName string // type?
param keyVaultUri string // type?

param storageAccountEncryptionKeyName string = 'oasisfs-key'

// TODO
//param userAssignedIdentity object

resource kvKey 'Microsoft.KeyVault/vaults/keys@2021-06-01-preview' = {
  //parent: keyVault
  name: '${keyVaultName}/${storageAccountEncryptionKeyName}'
  properties: {
    attributes: {
      enabled: true
    }
    keySize: 4096
    kty: 'RSA'
  }
}

resource sharedFs 'Microsoft.Storage/storageAccounts@2021-06-01' = {
    name: oasisStorageAccountName
    location: location
    sku: {
        name: 'Standard_LRS' // TODO param
    }
    kind: 'StorageV2'
    //tags: tags
    /*identity: {
        type: 'UserAssigned'
        userAssignedIdentities: {
            '${userAssignedIdentity.id}': {}
        }
    }*/
    properties: {
        accessTier: 'Hot'
        allowBlobPublicAccess: false
        supportsHttpsTrafficOnly: true
        minimumTlsVersion: 'TLS1_2'
       /* encryption: { TODO enable encryption?
          identity: {
            userAssignedIdentity: userAssignedIdentity.id
          }
          services: {
             blob: {
               enabled: true
             }
          }
          keySource: 'Microsoft.Keyvault'
          keyvaultproperties: {
            keyname: kvKey.name
            keyvaulturi: endsWith(keyVaultUri,'/') ? substring(keyVaultUri, 0, length(keyVaultUri) - 1) : keyVaultUri
          }
        }*/
    }
}

resource sharedFsSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  name: '${keyVaultName}/${oasisFsKeySecretName}'
  //parent: keyVault
  tags: tags
  properties: {
    attributes: {
      enabled: true
    }
    value: '${listKeys(sharedFs.id, sharedFs.apiVersion).keys[0].value}'
  }
}

resource sharedFsNameSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  name: '${keyVaultName}/${oasisFsNameSecretName}'
  //parent: keyVault
  tags: tags
  properties: {
    attributes: {
      enabled: true
    }
    value: oasisStorageAccountName
  }
}


resource sharedFsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-04-01' = {
  name: '${sharedFs.name}/default/${oasisFileShareName}'
}

resource modelsFsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-04-01' = {
  name: '${sharedFs.name}/default/${modelsFileShareName}'
}

output oasisFsNameSecretName string = oasisFsNameSecretName
output oasisFsKeySecretName string = oasisFsKeySecretName
output oasisFileShareName string = oasisFileShareName
output modelsFileShareName string = modelsFileShareName

