using Azure.Messaging.EventGrid;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace AzureMonitorHandler.Functions
{
    public class CreateEvent
    {
        private static Random random = new Random();

        [Function("CreateEvent")]
        [EventGridOutput(TopicEndpointUri = "EventGridSource_topicUri", TopicKeySetting = "EventGridSource_topicKey")]
        public static EventGridEvent Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get")] HttpRequestData req,
            FunctionContext context)
        {
            var logger = context.GetLogger("CreateEvent");
            logger.LogInformation("Generating event.");

            var eventToPublish = GenerateEvent(context);
            logger.LogInformation($"Publishing event: {eventToPublish}");

            return eventToPublish;
        }

        [Function("CreateEventsContinuously")]
        [EventGridOutput(TopicEndpointUri = "EventGridSource_topicUri", TopicKeySetting = "EventGridSource_topicKey")]
        public static EventGridEvent RunOnTimer(
            [TimerTrigger("0 0 */5 * * *")] TimerInfo timer,
            FunctionContext context)
        {
            var logger = context.GetLogger("CreateEventsContinuously");
            logger.LogInformation("Generating event.");

            var eventToPublish = GenerateEvent(context);
            logger.LogInformation($"Publishing event: {eventToPublish}");

            return eventToPublish;
        }

        private static EventGridEvent GenerateEvent(FunctionContext context) 
        {
            return new EventGridEvent(
                subject: $"/eventGridSource/EventGridToAppInsightsAndBlob/function/{context.FunctionId}",
                eventType: "AzureMonitorHandler.Functions.SampleEvent",
                dataVersion: "0.0.1",
                data: $"[{GenerateRandomAlphaString()}] EventGrid4allthethings!!!!");
        }

        private static string GenerateRandomAlphaString(int length = 8) 
        {
            var availableSet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
            return new string(availableSet.Select(c => availableSet[random.Next(availableSet.Length)]).Take(length).ToArray());
        }
    }
}