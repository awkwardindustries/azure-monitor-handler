const appInsights = require("applicationinsights");
appInsights.setup();
const appInsightsClient = appInsights.defaultClient;

// Event Grid always sends an array of data and may send more
// than one event in the array. The runtime invokes this function
// once for each array element, so we are always dealing with one.
// See: https://docs.microsoft.com/en-us/azure/azure-functions/functions-bindings-event-grid-trigger?tabs=in-process%2Cextensionv3&pivots=programming-language-javascript#event-schema
module.exports = async function (context, eventGridEvent) {
    context.log(typeof eventGridEvent);
    context.log(eventGridEvent);

    // As written, the Application Insights custom event will not be
    // correlated to any other context or span. If the custom event 
    // should be correlated to the parent function invocation, use
    // the tagOverrides property. For example:
    //   var operationIdOverride = { 
    //       "ai.operation.id": context.traceContext.traceparent 
    //   };
    //   client.trackEvent({
    //       name: "correlated to function invocation", 
    //       tagOverrides: operationIdOverride, 
    //       properties: {}
    //   });

    context.log(`Sending to App Insights...`);
    
    appInsightsClient.trackEvent({
        name: "Event Grid Event",
        properties: {
            eventGridEvent: eventGridEvent
        }
    });
    
    context.log(`Sent to App Insights successfully`);
};