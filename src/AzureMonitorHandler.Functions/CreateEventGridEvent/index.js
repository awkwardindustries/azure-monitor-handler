const { generateUuid } = require("@azure/core-http");

module.exports = async function (context, req) {
    context.log('JavaScript HTTP trigger function processed a request.');

    const responseMessage = "This HTTP triggered function executed successfully."

    var timestamp = new Date().toISOString();
    var messageId = generateUuid();
    context.bindings.outputEvent = {
        "subject": "function/manualcreate",
        "eventType": "somethingHappened",
        "eventTime": timestamp,
        "id": messageId,
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