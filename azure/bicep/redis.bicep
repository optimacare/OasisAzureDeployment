@description('Resource location')
param location string = resourceGroup().location

@description('Tags for the resources')
param tags object

@description('The virtual network name')
param vnetName string

@description('The name of the subnet')
param subnetName string

@description('Name of key vault')
param keyVaultName string

@description('Private DNS zone name. Will be used as <service>.<privateDNSZoneName>')
param privateDNSZoneName string = 'privatelink.redis.cache.windows.net'

@description('Specify the name of the Azure Redis Cache to create.')
param redisCacheName string = 'celery-redis-${uniqueString(resourceGroup().id)}'

@description('Specify the pricing tier of the new Azure Redis Cache.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param redisCacheSKU string = 'Standard'

@description('Specify the family for the sku. C = Basic/Standard, P = Premium.')
@allowed([
  'C'
  'P'
])
param redisCacheFamily string = 'C'

@description('Specify the size of the new Azure Redis Cache instance. Valid values: for C (Basic/Standard) family (0, 1, 2, 3, 4, 5, 6), for P (Premium) family (1, 2, 3, 4)')
@allowed([
  0
  1
  2
  3
  4
  5
  6
])
param redisCacheCapacity int = 1

resource redisCache 'Microsoft.Cache/Redis@2021-06-01' = {
  name: redisCacheName
  location: location
  tags: tags
  properties: {
    redisVersion: '6'
    enableNonSslPort: true
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    sku: {
      capacity: redisCacheCapacity
      family: redisCacheFamily
      name: redisCacheSKU
    }
  }
}


// Secrets
resource celeryRedisServerName 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  name: '${keyVaultName}/celery-redis-server-name'
  tags: tags
  properties: {
    attributes: {
      enabled: true
    }
    value: redisCache.name
  }
}

resource celeryRedisAccessKey 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  name: '${keyVaultName}/celery-redis-password'
  tags: tags
  properties: {
    attributes: {
      enabled: true
    }
    value: redisCache.listKeys().primaryKey
  }
}

module privateEndpoint 'private_endpoint.bicep' = {
  name: 'private-redis-endpoint'
  params: {
    privateEndpointName: 'private-redis-endpoint'
    location: location
    tags: tags
    vnetName: vnetName
    subnetName: subnetName
    privateLinkServiceId: redisCache.id
    serverName: redisCache.name
    keyVaultName: keyVaultName
    privateDNSZoneName: privateDNSZoneName
    privateLinkGroupId: 'redisCache'
    secretHostName: 'celery-redis-server-host'
  }
}
