const { generateUuid } = require("@azure/core-http");

module.exports = async function (context, req) {
    context.log('JavaScript HTTP trigger function processed a request.');

    const name = (req.query.name || (req.body && req.body.name));
    const responseMessage = name
        ? "Hello, " + name + ". This HTTP triggered function executed successfully."
        : "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.";

    context.bindings.outputEvent = {
        "topic": "/subscriptions/6d1cc86a-ad12-4f88-8923-5e0c418b4acf/resourceGroups/rg-test-azmon/providers/Microsoft.EventGrid/topics/evgt-2nz6ktw5gxivg",
        "subject": "function/manualcreate",
        "eventType": "somethingHappened",
        "eventTime": new Date().toISOString(),
        "id": generateUuid(),
        "data": {
            "fileUrl": "https://test.blob.core.windows.net/debugging/testblob.txt",
            "fileType": "AzureBlockBlob",
            "partitionId": "1",
            "sizeInBytes": 0,
            "eventCount": 0,
            "firstSequenceNumber": -1,
            "lastSequenceNumber": -1,
            "firstEnqueueTime": "0001-01-01T00:00:00",
            "lastEnqueueTime": "0001-01-01T00:00:00"
        },
        "dataVersion": "1.0", 
        "metadataVersion": "1" 
    };

    context.res = {
        // status: 200, /* Defaults to 200 */
        body: responseMessage
    };
}