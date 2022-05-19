# Azure Function Handler for Event Grid to Application Insights & Blob Storage

## Overview

Azure Event Grid offers several built-in handlers, but none that push directly to Azure Monitor. This sample uses an Azure Function handler that can be registered as an Event Grid handler for any Event Grid topic from which events should be logged. The sample handles the event in two ways -- creating a custom Application Insights event and persisting to Azure Blob Storage.

![Resource diagram of conceptual architecture](./.assets/event-grid_to_app-insights.png)

While not required, this sample was created using Visual Studio Code with the Azure Functions extension. The extension provides some useful shortcuts for debugging locally and deploying to Azure. If you would prefer use a different code editor, please refer to the files under the `.vscode` directory to see what commands are being used by the extension and VS Code to support local building, debugging, and deployment.

## Run Locally

### Azure Functions settings

At the base of the *src/AzureMonitorHandler.Functions* directory, create or update the `local.settings.json` file to include:

```jsonc
{
  "IsEncrypted": false,
  "Values": {
    /* For running locally, you can use the Azurite storage emulator as described
     * here: https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azurite.
     * You can also use an Azure Storage Account connection string if desired. */
    "AzureWebJobsStorage": "DefaultEndpointsProtocol=https;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=https://127.0.0.1:10000/devstoreaccount1;QueueEndpoint=https://127.0.0.1:10001/devstoreaccount1;",
    /* Tells the Functions runtime this is a Node function. */
    "FUNCTIONS_WORKER_RUNTIME": "node",
    /* Tells the Functions runtime this should use Node 14. */
    "WEBSITE_NODE_DEFAULT_VERSION": "~14",
    /* Required for local debugging. */
    "languageWorkers:node:arguments": "--inspect=5858",
    /* An Azure Application Insights resource connection string is required. */
    "APPLICATIONINSIGHTS_CONNECTION_STRING": "<APPLICATION_INSIGHTS_CONNECTION_STRING>",
    /* These aren't required for local development unless you want to trigger the CreateEvent
     * function and verify publish to the Event Grid Topic. You can also use an
     * Azure Event Grid Topic resource if desired. */
    "EVENT_GRID_TOPIC_URI": "",
    "EVENT_GRID_TOPIC_KEY": "",
    /* Defines the storage target. For local development you can use the Azurite storage emulator,
     * or you can use an Azure resource (e.g., https://<ACCOUNTNAME>.blob.core.windows.net) as
     * long as the local credentials used to run the function have Storage Account Owner permissions
     * on the target account. */
    "STORAGE_ACCOUNT_ENDPOINT_BLOB": "https://127.0.0.1:10000/devstoreaccount1"
  }
}
```

### Run Azurite Storage Emulator

1. **Create a PEM certificate**
   ```sh
   cd path/to/pem-certs
   openssl req -newkey rsa:2048 -x509 -nodes -keyout key.pem -new -out cert.pem -sha256 -days 365 -addext "subjectAltName=IP:127.0.0.1" -subj "/C=CO/ST=ST/L=LO/O=OR/OU=OU/CN=CN"
   # Must run as Administrator
   certutil –addstore -enterprise –f "Root" cert.pem
   ```
1. **Run Azurite from Docker**
   ```sh
   docker run -p 10000:10000 -p 10001:10001 -p 10002:10002 -v path/to/cert:/certs \
     mcr.microsoft.com/azure-storage/azurite \
     azurite --blobHost 0.0.0.0 --queueHost 0.0.0.0 --tableHost 0.0.0.0 \
       --cert /certs/cert.pem --key /certs/key.pem --oauth basic
   ```

### Run the Functions

If using VS Code, launch the `Attach to Node Functions` configuration using **F5** or from the *Run and Debug* view. This action should re-build and start the Functions runtime. If successful, your Terminal will show the output log of the local Azure Function Core Tools.

For HTTP triggered events (such as CreateEvent), you can use the HTTP endpoint exposed in the log or right-click on the function in the Azure Functions extension Functions browser and click *Execute Function Now...*.

### Trigger ProcessEvent

When debugging locally, you can trigger functions dependent on Event Grid triggers by creating a `POST` request to the local address `http://localhost:7071/runtime/webhooks/EventGrid` with the query parameter `functionName` equal to the function you'd like to trigger. The body should contain a JSON array with a single object matching the Event Grid event schema.

```http
POST /runtime/webhooks/EventGrid?functionName=ProcessEvent HTTP/1.1
Host: localhost
Aeg-Event-Type: Notification
Content-Type: application/json

[
    {
        "id": "a1c4e585-e3de-4f7c-b2b2-092d67aa4237",
        "topic": "my-topic",
        "subject": "my-subject",
        "data": {
            "fileUrl": "https://test.blob.core.windows.net/debugging/testblob.txt",
            "fileType": "AzureBlockBlob",
            "partitionId": "1",
            "sizeInBytes": 0,
            "eventCount": 0,
            "firstSequenceNumber": -1,
            "lastSequenceNumber": -1,
            "firstEnqueueTime": "0001-01-01T00:00:00Z",
            "lastEnqueueTime": "0001-01-01T00:00:00Z"
        },
        "eventType": "somethingHappened",
        "dataVersion": "1.0",
        "metadataVersion": "1",
        "eventTime": "2022-05-18T17:34:01.92Z"
    }
]
```

> Note: The request header `Aeg-Event-Type: Notification` is important and must be included; otherwise, the function will not be triggered.

If you've dropped a breakpoint into the ProcessEvent's index.js function export, VS Code's debugger should break to allow local variable investigation and stepping through the function handler code.

If you'd like to debug your local code against an actual Event Grid event, you can use the ngrok utility to expose the local function as an Event Grid webhook subscription. See <https://docs.microsoft.com/en-us/azure/azure-functions/functions-debug-event-grid-trigger-local#allow-azure-to-call-your-local-function> for detailed directions on how to setup.

## Deploy to Azure

1. **Provision the Resources**
   ```bash
   # Bash commands from the /iac directory
   resourceGroup="rg-sample-eg-to-azmon"
   location="southcentralus"

   # Create the Resource Group
   az group create --name $resourceGroup --location "$location"

   # Kickoff the deployment
   az deployment group create --name DeployResources --resource-group $resourceGroup \
     --template-file .\fn-handler-with-appinsights-and-blob.bicep
   ```
1. **Deploy the Function Code** Using VS Code's Azure Function extension, highlight the Local Project and click the *Deploy to Function App...* button on the Functions section header. This action will build the code for production, create a Zip package, and deploy to the specified Function App.
1. **Trigger an Event** The output from a successful deployment will include the Function URI to invoke the CreateEvent function. Open the URL and verify that the HTTP triggered function executed successfully.
