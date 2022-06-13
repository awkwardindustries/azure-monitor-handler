const appInsights = require("applicationinsights");
appInsights.setup();
const appInsightsClient = appInsights.defaultClient;

// The Event Grid Trigger does not support the CloudEvents schema, so an
// HTTP Trigger may be used to receive events.
module.exports = async function (context, req) {
    context.log('JavaScript HTTP trigger function processed a request.');

    if (req.method == "OPTIONS") {
        // If the request is for subscription validation, send back the
        // validation code.
        context.log('Validate subscription request received');
        context.res = {
            status: 200,
            headers: {
                'Webhook-Allowed-Origin': 'eventgrid.azure.net',
            },
        };
    }
    else {
        // An event has been received. The CloudEvents schema delivers one
        // event at a time, so the body represents a single event in the
        // CloudEvents schema in JSON format.
        context.log(`Sending to App Insights...`);

        appInsightsClient.trackEvent({
            name: 'Event Grid Event',
            properties: {
                eventGridEvent: req.body
            }
        });

        context.log(`Sent to App Insights successfully`);
    }
}