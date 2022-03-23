@description('Resource location')
param location string = resourceGroup().location

@description('Storage account name')
param oasisStorageAccountName string = substring('oasis${uniqueString(resourceGroup().id)}', 0, 17)

@description('Azure storage SKU type')
@allowed([
    'Premium_LRS'
    'Premium_ZRS'
    'Standard_GRS'
    'Standard_GZRS'
    'Standard_LRS'
    'Standard_RAGRS'
    'Standard_RAGZRS'
    'Standard_ZRS'
])
param oasisStorageAccountSKU string = 'Standard_LRS'

@description('Tags for the resources')
param tags object

@description('Name of secret to store name of storage account')
param oasisFsNameSecretName string = 'oasisfs-name'

@description('Name of secret to store key to storage account')
param oasisFsKeySecretName string = 'oasisfs-key'

@description('Shared files name for oasis shared file system')
param oasisFileShareName string = 'oasisfs'

@description('Shared files name for model files')
param modelsFileShareName string = 'models'

@description('Name of key vault')
param keyVaultName string

param storageAccountEncryptionKeyName string = 'oasisfs-key'

/* TODO
resource kvKey 'Microsoft.KeyVault/vaults/keys@2021-06-01-preview' = {
  name: '${keyVaultName}/${storageAccountEncryptionKeyName}'
  properties: {
    attributes: {
      enabled: true
    }
    keySize: 4096
    kty: 'RSA'
  }
}*/

resource sharedFs 'Microsoft.Storage/storageAccounts@2021-06-01' = {
    name: oasisStorageAccountName
    location: location
    sku: {
        name: oasisStorageAccountSKU
    }
    kind: 'StorageV2'
    tags: tags
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

