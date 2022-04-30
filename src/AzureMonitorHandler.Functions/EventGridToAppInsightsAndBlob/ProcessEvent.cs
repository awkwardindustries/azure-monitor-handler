// Default URL for triggering event grid function in the local environment.
// http://localhost:7071/runtime/webhooks/EventGrid?functionName={functionname}
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.ApplicationInsights;
using Microsoft.ApplicationInsights.DataContracts;

namespace AzureMonitorHandler.Functions
{
    public class ProcessEvent
    {
        private readonly TelemetryClient telemetryClient;
        public ProcessEvent(TelemetryClient telemetryClient)
        {
            this.telemetryClient = telemetryClient;
        }

        [Function("ProcessEvent")]
        [BlobOutput("events/{name}.txt", Connection = "DestinationStore")]
        public string Run(
            [EventGridTrigger] string input,
            FunctionContext context)
        {
            var logger = context.GetLogger("ProcessEvent");
            logger.LogInformation($"Received event: {input}");

            var eventGridEvent = Azure.Messaging.EventGrid.EventGridEvent.Parse(BinaryData.FromString(input));
            if (eventGridEvent == null)
            {
                logger.LogError("Parsing input to EventGridEvent failed.");
                throw new Exception("Failed to get event");
            }
            else
            {
                // Really, I want Data to be a JSON representation
                // DateTime mapping to nothing...
                var appInsightsEventTelemetry = new EventTelemetry();
                foreach (KeyValuePair<string, string> item in eventGridEvent.ToDictionary()) 
                {
                    appInsightsEventTelemetry.Properties[item.Key] = item.Value;
                }

                logger.LogInformation($"Pushing to Application Insights via Telemetry Client: {appInsightsEventTelemetry}");
                telemetryClient.TrackEvent(appInsightsEventTelemetry);

                logger.LogInformation("Pushing to blob storage via Blob Output");
                return eventGridEvent.ToLog();
            }
        }
    }
}