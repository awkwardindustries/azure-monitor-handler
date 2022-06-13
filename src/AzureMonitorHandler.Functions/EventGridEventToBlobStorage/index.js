// Event Grid always sends an array of data and may send more
// than one event in the array. The runtime invokes this function
// once for each array element, so we are always dealing with one.
// See: https://docs.microsoft.com/en-us/azure/azure-functions/functions-bindings-event-grid-trigger?tabs=in-process%2Cextensionv3&pivots=programming-language-javascript#event-schema
module.exports = async function (context, eventGridEvent) {
    context.log(JSON.stringify(context.bindings));
    context.log(JSON.stringify(context.bindingData));

    context.bindings.outputBlob = JSON.stringify(eventGridEvent);
};