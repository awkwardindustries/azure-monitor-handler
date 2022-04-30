##################
### Step 0: set parameters required for the rest of the script
##################
#information needed to authenticate to AAD and obtain a bearer token
$tenantId = "00000000-0000-0000-0000-000000000000"; #Tenant ID the data collection endpoint resides in
$appId = "00000000-0000-0000-0000-000000000000"; #Application ID created and granted permissions
$appSecret = "00000000000000000000000"; #Secret created for the application

#information needed to send data to the DCR endpoint
$dcrImmutableId = "dcr-000000000000000"; #the immutableId property of the DCR object
$dceEndpoint = "https://my-dcr-name.westus2-1.ingest.monitor.azure.com"; #the endpoint property of the Data Collection Endpoint object

##################
### Step 1: obtain a bearer token used later to authenticate against the DCE
##################
$scope= [System.Web.HttpUtility]::UrlEncode("https://monitor.azure.com//.default")   
$body = "client_id=$appId&scope=$scope&client_secret=$appSecret&grant_type=client_credentials";
$headers = @{"Content-Type"="application/x-www-form-urlencoded"};
$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

$bearerToken = (Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers).access_token

##################
### Step 2: Load up some sample data. 
##################
$currentTime = Get-Date ([datetime]::UtcNow) -Format O
$staticData = @"
[
{
    "Time": "$currentTime",
    "Computer": "Computer1",
    "AdditionalContext": {
                "InstanceName": "user1",
                "TimeZone": "Pacific Time",
                "Level": 4,
        "CounterName": "AppMetric1",
        "CounterValue": 15.3    
    }
},
{
    "Time": "$currentTime",
    "Computer": "Computer2",
    "AdditionalContext": {
                "InstanceName": "user2",
                "TimeZone": "Central Time",
                "Level": 3,
        "CounterName": "AppMetric1",
        "CounterValue": 23.5     
    }
}
]
"@;

##################
### Step 3: send the data to Log Analytics via the DCE.
##################
$body = $staticData;
$headers = @{"Authorization"="Bearer $bearerToken";"Content-Type"="application/json"};
$uri = "$dceEndpoint/dataCollectionRules/$dcrImmutableId/streams/Custom-MyTableRawData?api-version=2021-11-01-preview"

$uploadResponse = Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers