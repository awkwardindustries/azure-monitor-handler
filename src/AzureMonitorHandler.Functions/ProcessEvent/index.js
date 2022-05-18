const appInsights = require("applicationinsights");
appInsights.setup();
const appInsightsClient = appInsights.defaultClient;

const { BlobServiceClient } = require("@azure/storage-blob");
const STORAGE_CONNECTION_STRING = process.env.STORAGE_CONNECTION_STRING || "";
const blobServiceClient = BlobServiceClient.fromConnectionString(STORAGE_CONNECTION_STRING);

module.exports = async function (context, eventGridEvent) {
    context.log(typeof eventGridEvent);
    context.log(eventGridEvent);

    // Use if needed to correlate the custom events to the parent function invocation.
    // var operationIdOverride = {"ai.operation.id":context.traceContext.traceparent};
    // client.trackEvent{name: "correlated to function invocation", tagOverrides:operationIdOverride, properties: {}};
    context.log(`Sending to App Insights...`);
    appInsightsClient.trackEvent({
        name: "Event Grid Event",
        properties: {
            eventGridEvent: eventGridEvent
        }
    });
    context.log(`Sent to App Insights successfully`);

    // Write to Blob Storage also
    context.log(`Uploading blob...`);
    const containerClient = blobServiceClient.getContainerClient("events");
    containerClient.createIfNotExists();
    const blockBlobClient = containerClient.getBlockBlobClient(eventGridEvent.id);
    const eventAsString = JSON.stringify(eventGridEvent);
    const uploadBlobResponse = await blockBlobClient.upload(eventAsString, Buffer.byteLength(eventAsString));
    context.log(`Uploaded block blob ${eventGridEvent.id} successfully`, uploadBlobResponse.requestId);
};