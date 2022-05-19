@description('Location of the resources')
param location string = resourceGroup().location

@description('Unique string for the resource group for global naming')
param uniqueName string = uniqueString(subscription().id, resourceGroup().id)

// ------------------------------------------------------------------
// Managed Identity
//
// * User Assigned Managed Identity
// * Permission to write to destination storage account
// * Permission to write to Application Insights / Log Analytics workspace
// ------------------------------------------------------------------

param managedIdentityName string = 'mi-${uniqueName}'
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

// Lookup pre-defined built-in role definitions
resource storageBlobDataOwner 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
}
resource monitoringMetricsPublisher 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '3913510d-42f4-4e42-8a64-420c390055eb'
}

// Assign roles to the managed identity
resource storageBlobDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(resourceGroup().id, managedIdentity.id, storageBlobDataOwner.id, storageAccount.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataOwner.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
resource functionStorageBlobDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(resourceGroup().id, managedIdentity.id, storageBlobDataOwner.id, functionAppStorageAccount.id)
  scope: functionAppStorageAccount
  properties: {
    roleDefinitionId: storageBlobDataOwner.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
resource monitoringMetricsPublisherRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(resourceGroup().id, managedIdentity.id, monitoringMetricsPublisher.id)
  properties: {
    roleDefinitionId: monitoringMetricsPublisher.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ------------------------------------------------------------------
// Destination Bits
//
// * Log Analytics Workspace
// * Application Insights
// * Storage Account & target container
// ------------------------------------------------------------------

param workspaceName string = 'log-${uniqueName}'
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

param appInsightsName string = 'appi-${uniqueName}'
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

param storageAccountName string = 'st${uniqueName}'
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    accessTier: 'Hot'
  }
}

param blobContainerName string = 'events'
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-09-01' = {
  name: '${storageAccount.name}/default/${blobContainerName}'
}

// ------------------------------------------------------------------
// Function App
//
// * Storage Account for Function
// * App Service Plan for hosting
// * Function App definition with required App Settings
// ------------------------------------------------------------------

param functionAppStorageAccountName string = 'stf${uniqueName}'
resource functionAppStorageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: functionAppStorageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }

  resource blobServices 'blobServices' = {
    name: 'default'
    properties: {
      cors: {
        corsRules: []
      }
      deleteRetentionPolicy: {
        enabled: true
        days: 7
      }
    }
  }
}

param functionAppHostName string = 'plan-${uniqueName}'
resource functionAppHost 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: functionAppHostName
  location: location
  kind: 'functionapp'
  sku:{
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

param functionAppName string = 'func-${uniqueName}'
resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: functionAppHost.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionAppStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${functionAppStorageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~14'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'EVENT_GRID_TOPIC_URI'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENT_GRID_TOPIC_KEY'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: managedIdentity.properties.clientId
        }
        {
          name: 'STORAGE_ACCOUNT_ENDPOINT_BLOB'
          value: storageAccount.properties.primaryEndpoints.blob
        }
      ]
      cors: {
        allowedOrigins: [
          'https://ms.portal.azure.com'
        ]
      }
    }
    clientAffinityEnabled: false
    clientCertEnabled: false
    virtualNetworkSubnetId: null
    httpsOnly: true
  }
}

// ------------------------------------------------------------------
// Event Grid Topic & Subscriptions
// ------------------------------------------------------------------

param eventGridTopicName string = 'evgt-${uniqueName}'
resource eventGridTopic 'Microsoft.EventGrid/topics@2021-12-01' = {
  name: eventGridTopicName
  location: location
}

// Because these resources are allocated before the Function code is deployed to the Function
// App, we cannot automatically create the Event Subscription. If the Function were able to be
// represented by a Bicep resource (e.g., using something like:
//    resource processEventFunction 'Microsoft.Web/sites/functions@2021-03-01' existing = {
//      parent: functionApp
//      name: '<NAME-OF-FUNCTION>'
//    }
// ), you could create the subscription declaratively like this:
// 
// resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2021-10-15-preview' = {
//   parent: eventGridTopic
//   name: 'function-handler'
//   properties: {
//     deliveryWithResourceIdentity: {
//       destination: {
//         endpointType: 'AzureFunction'
//         properties: {
//           resourceId: processEventFunction.id
//         }
//       }
//       identity: {
//         type: 'UserAssigned'
//         userAssignedIdentity: managedIdentity.properties.principalId
//       }
//     }
//   }
// }

// Although we're using an Azure Function handler, it would be ideal for this scenario if
// an Azure Monitor handler could be automatically handled after declaration similar to:
//
// resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2021-10-15-preview' = {
//   parent: eventGridTopic
//   name: 'monitor-handler'
//   properties: {
//     destination: {
//       endpointType: 'AzureMonitor'
//       properties: {
//         resourceId: logAnalyticsWorkspace.id
//       }
//     }
//   }
// }
