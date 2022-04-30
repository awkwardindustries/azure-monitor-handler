@description('Location of the resources')
param location string = resourceGroup().location

@description('Unique string for the resource group for global naming')
param uniqueName string = uniqueString(subscription().id, resourceGroup().id)

// ------------------------------------------------------------------
// Managed Identity (User Assignable)
//
// * Used on the Function App
// * Anticipate an intermediate function triggered by an
//   Event Grid event whose responsibility is to invoke
//   the Data Collection Endpoint with the appropriate payload
// ------------------------------------------------------------------

@description('Name of the user assigned managed identity')
param managedIdentityName string = 'mi-${uniqueName}'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

// ------------------------------------------------------------------
// Log Analytics Workspace
//
// * Creates the Log Analytics workspace
// * Creates the Data Collection Endpoint and Rule
// * Assigns Monitoring Metrics Publisher role to Managed Identity
// ------------------------------------------------------------------

@description('Name of the Log Analytics workspace')
param workspaceName string = 'log-${uniqueName}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }

  resource monitorHandlerTable 'tables' = {
    name: 'MonitorHandler_CL'
    properties: {
      schema: {
        name: 'MonitorHandler_CL'
        columns: [
          {
            name: 'TimeGenerated'
            type: 'dateTime'
            description: 'The time at which the data was generated'
          }
          {
            name: 'EventContent'
            type: 'dynamic'
            description: 'The content of the source event'
          }
        ]
      }
    }
  }
}

@description('Name of the Data Collection Endpoint (to push custom logs)')
param dataCollectionEndpointName string = 'eventGridLogger'

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2021-04-01' = {
  name: dataCollectionEndpointName
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

/*
 * This fails until my subscription has access to the updated resource provider supporting
 * the 2021-09-01-preview. Request access via https://aka.ms/CustomLogsOnboard.
*/

@description('Name of the Data Collection Rule for logging an Event Grid event')
param dataCollectionRuleName string = 'eventGridLoggerRule'

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2021-09-01-preview' = {
  name: dataCollectionRuleName
  location: location
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
      'MonitorHandlerRawData': {
        columns: [
          {
            name: 'Time'
            type: 'datetime'
          }
          {
            name: 'EventContentJsonString'
            type: 'string'
          }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: logAnalyticsWorkspace.name
        }
      ]
    }
    dataFlows: [
      {
        streams: [
#disable-next-line BCP034
          'MonitorHandlerRawData'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
        transformKql: 'source | extend jsonContent = parse_json(EventContentJsonString) | project TimeGenerated = Time, EventContent = jsonContent'
        outputStream: 'MonitorHandler_CL'
      }
    ]
  }
}

@description('Use built-in Monitoring Metrics Publisher role. See https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#monitoring-metrics-publisher')
resource monitoringMetricsPublisherRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '3913510d-42f4-4e42-8a64-420c390055eb'
}

resource managedIdentityRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(resourceGroup().id, managedIdentity.id, monitoringMetricsPublisherRoleDefinition.id)
  scope: dataCollectionRule
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ------------------------------------------------------------------
// Function App (sample source for event grid topic)
// ------------------------------------------------------------------

@description('Storage account name for Function app')
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

@description('Name for App Insights resource for Function app')
param functionAppAppInsightsName string = 'appi-${uniqueName}'

resource functionAppAppInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: functionAppAppInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

@description('Name of the Function app hosting plan')
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

@description('Name of the Function app')
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
          value: functionAppAppInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${functionAppAppInsights.properties.InstrumentationKey}'
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
          name: 'EventGridSource_TopicUri'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EventGridSource_TopicKey'
          value: eventGridTopic.listKeys().key1
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

  // Interesting Cheat
  resource eventGridSourceFunction 'functions' = {
    name: 'EventGridSource'
    properties: {
      config: {
        disabled: false
        bindings: [
          {
            name: 'req'
            type: 'httpTrigger'
            direction: 'in'
            authLevel: 'anonymous'
            methods: [
              'get'
            ]
          }
          {
            name: '$return'
            type: 'http'
            direction: 'out'
          }
          {
            name: 'outputEvent'
            type: 'eventGrid'
            topicEndpointUri: 'EventGridSource_TopicUri'
            topicKeySetting: 'EventGridSource_TopicKey'
            direction: 'out'
          }
        ]
      }
      files: {
        'run.csx': '''
#r "Microsoft.Azure.EventGrid"
using System;
using System.Net;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.EventGrid.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Primitives;

public static IActionResult Run(HttpRequest req, out EventGridEvent outputEvent, ILogger log)
{
  log.LogInformation("Request received. Publishing an EventGrid event.");
  outputEvent = new EventGridEvent(
    $"{Guid.NewGuid()}", // Message ID
    "/customEventTopic/customEvent/triggerAzureMonitorHandler", // Subject
    "EventGrid for all the things!!!!!", // Event Data (Object)
    "AwkwardIndustries.Events.SomethingToLog", // Event Type
    DateTime.UtcNow, // Time
    "1.0"); // Data Version
  return new OkObjectResult($"EventGrid event published: {outputEvent}");
}
'''
      }
    }
  }
}

// ------------------------------------------------------------------
// Event Grid Topic & Subscriptions
// ------------------------------------------------------------------

@description('Name of the Event Grid Topic')
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
