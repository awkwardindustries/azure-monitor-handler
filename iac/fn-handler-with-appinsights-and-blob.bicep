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
  name: guid(resourceGroup().id, managedIdentity.id, storageBlobDataOwner.id)
  scope: storageAccount
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
// * Storage Account
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
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsights.properties.InstrumentationKey}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionAppStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${functionAppStorageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'EventGridSource_topicUri'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EventGridSource_topicKey'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'DestinationStore__serviceUri'
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

// @description('Name for the Event Grid Topic Subscription')
// param eventGridSubscriptionName string = 'evgs-${uniqueName}'

// resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2021-12-01' = {
//   name: eventGridSubscriptionName
//   scope: eventGridTopic
//   properties: {
//     /*
//     destination: {
//       endpointType: 'AzureMonitor'
//       properties: {
//         resourceId: logAnalyticsWorkspace.id
//       }
//     }
//     */
//     deliveryWithResourceIdentity: {
//       destination: {
//         endpointType: 'AzureFunction'
//       }
//       identity: {
//         type: 'UserAssigned'
//         userAssignedIdentity: managedIdentity.properties.principalId
//       }
//     }
//   }
// }
