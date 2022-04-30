using Azure.Messaging.EventGrid;

namespace AzureMonitorHandler.Functions
{
    public static class EventGridEventExtensions
    {
        public static string ToLog(this EventGridEvent evt) => 
            $"{evt.Id},{evt.Topic},{evt.Subject},{evt.EventType},{evt.EventTime},{evt.Data}";

        public static IDictionary<string, string> ToDictionary(this EventGridEvent evt) =>
            evt.GetType()
                .GetProperties(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public)
                .ToDictionary(prop => prop.Name, prop => prop.GetValue(evt, null) as string ?? string.Empty);
    }

}