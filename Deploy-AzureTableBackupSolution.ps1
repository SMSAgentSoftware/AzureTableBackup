############################################################################################
## Deploys and configures the Azure resources required by the Azure Table Backup solution ##
############################################################################################

#! Run this script with the Owner or Contributer role in the Azure subscription !#

## Check required modules
#Requires -Modules Az.Accounts,Az.Resources,Az.Storage,Az.OperationalInsights,Az.ApplicationInsights,Az.Functions,Az.WebSites

### VARIABLES TO SET
$Subscription = "<MyAzureSubscription>" # The name of the Azure subscription which will host your resources
$Location = "<Location>" # The Azure region for your resources. Find available regions like so: Get-AzLocation | Where {$_.RegionType -eq "Physical"} | Select -ExpandProperty DisplayName | Sort, or here: https://azure.microsoft.com/en-us/explore/global-infrastructure/data-residency/#select-geography
###

### RESOURCE NAMES
$RandomSuffix = (New-Guid).ToString().Substring(0,8)
$ResourceGroupName = "rg-azTableBackup-$($RandomSuffix)"
$StorageAccountName = "staztablebackup$($RandomSuffix)"
$LogAnalyticsWorkspaceName = "log-azTableBackup-$($RandomSuffix)"
$ApplicationInsightsName = "appi-azTableBackup-$($RandomSuffix)"
$FunctionAppName = "func-azTableBackup-$($RandomSuffix)"

# Check Azure region availability
$UnavailableRegions = @{
    "China East" = "Azure Functions"
}

If ($UnavailableRegions.Keys -contains $Location)
{
    Write-Host "Sorry, the following resources are not available in the $location region: $($UnavailableRegions["$Location"])" -ForegroundColor Red
    return
}

# Connect to Azure AD
$Connection = Connect-AzAccount -Subscription $Subscription

# Create resource group
Write-Host "Creating resource group..." -NoNewline
try 
{
    $ResourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
    Write-Host "  Your resources will be created in the following resource group: $($ResourceGroup.ResourceGroupName)"
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Error $_
    return
}

# Create storage account
Write-Host "Creating storage account..." -NoNewline
try 
{
    $StorageAccount = New-AzStorageAccount `
        -ResourceGroupName $ResourceGroup.ResourceGroupName `
        -Name $StorageAccountName `
        -SkuName Standard_LRS `
        -Location $Location `
        -Kind StorageV2 `
        -AccessTier Hot `
        -EnableHttpsTrafficOnly $true `
        -MinimumTlsVersion TLS1_2 `
        -AllowSharedKeyAccess $true `
        -PublicNetworkAccess Enabled `
        -RoutingChoice MicrosoftRouting `
        -ErrorAction Stop        
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Error -Message $_.Exception.Message
    return
}

# Enable container soft delete
Write-Host "Enabling container soft delete..." -NoNewline
try 
{
    Enable-AzStorageContainerDeleteRetentionPolicy `
        -ResourceGroupName $ResourceGroup.ResourceGroupName `
        -StorageAccountName $StorageAccount.StorageAccountName `
        -RetentionDays 7 `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning $_.Exception.Message
}

# Enable blob soft delete
Write-Host "Enabling blob soft delete..." -NoNewline
try 
{
    Enable-AzStorageBlobDeleteRetentionPolicy `
        -ResourceGroupName $ResourceGroup.ResourceGroupName `
        -StorageAccountName $StorageAccount.StorageAccountName `
        -RetentionDays 7 `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning $_.Exception.Message
}

# Create a storage context
Write-Host "Creating a storage context..." -NoNewline
try 
{
    $StorageContext = New-AzStorageContext `
        -StorageAccountName $StorageAccount.StorageAccountName `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Error -Message $_.Exception.Message
    return
}

# Create backup configuration table
Write-Host "Creating a backup configuration table..." -NoNewline
$TableName = 'AutomatedTableBackupConfiguration'
Write-Host "$TableName..." -NoNewline
try 
{
    $BackupConfigurationTable = New-AzStorageTable `
        -Name "$TableName" `
        -Context $StorageContext `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning -Message $_.Exception.Message
}

# Create backup container
Write-Host "Creating a backup container..." -NoNewline
$ContainerName = 'tablebackups'
Write-Host "$ContainerName..." -NoNewline
try 
{
    $BackupConfigurationContainer = New-AzStorageContainer `
        -Name "$ContainerName" `
        -Context $StorageContext `
        -Permission Off `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning -Message $_.Exception.Message
}

# Create a log analytics workspace
Write-Host "Creating a log analytics workspace..." -NoNewline
try 
{
    $LogAnalyticsWorkspace = New-AzOperationalInsightsWorkspace `
        -Location $Location `
        -Name $LogAnalyticsWorkspaceName `
        -Sku pergb2018 `
        -ResourceGroupName $ResourceGroupName `
        -ErrorAction Stop 
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Error -Message $_.Exception.Message
    return
}

# Create an application insights instance
Write-Host "Creating an application insights instance..." -NoNewline
try 
{
    $AppInsights = New-AzApplicationInsights `
        -Kind web `
        -ResourceGroupName $ResourceGroupName `
        -Name $ApplicationInsightsName `
        -location $Location `
        -WorkspaceResourceId $LogAnalyticsWorkspace.ResourceId `
        -ErrorAction Stop 
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Error -Message $_.Exception.Message
    return
}

# Create a function app
Write-Host "Creating a function app..." -NoNewline
$AppSettings = @{
    'BackupConfigurationStorageAccount' = $StorageAccountName
    'BackupConfigurationStorageTable' = $TableName
    'BackupConfigurationTimerExpression' = "0 0 1 * * *"
    'WEBSITE_RUN_FROM_PACKAGE' = "1"
}
try 
{
    $FunctionApp = New-AzFunctionApp `
        -Name $FunctionAppName `
        -StorageAccountName $StorageAccountName `
        -Location $Location `
        -ResourceGroupName $ResourceGroupName `
        -Runtime DotNet `
        -RuntimeVersion 6 `
        -FunctionsVersion 4 `
        -OSType Windows `
        -IdentityType SystemAssigned `
        -ApplicationInsightsName $AppInsights.Name `
        -ApplicationInsightsKey $AppInsights.InstrumentationKey `
        -AppSetting $AppSettings `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Error -Message $_.Exception.Message
    return
}

# Assign Azure roles
# note the required permissions
# https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-powershell#prerequisites
Write-Host "Adding role assignments for function app system identity to storage account..."
"Storage Table Data Reader","Storage Blob Data Contributor" | foreach {
    Write-Host "  $_..." -NoNewline
    try 
    {
        $RoleAssignment = New-AzRoleAssignment `
        -ObjectId $FunctionApp.IdentityPrincipalId `
        -RoleDefinitionName "$_" `
        -Scope $StorageAccount.Id `
        -WarningAction SilentlyContinue `
        -ErrorAction Stop
        Write-Host "Success!" -ForegroundColor Green
    }
    catch 
    {
        Write-Host "Failed!" -ForegroundColor Red
        Write-Warning -Message $_.Exception.Message
    }
}

Write-Host "Adding role assignment for current user to storage account..."
"Storage Table Data Contributor"| foreach {
    Write-Host "  $_..." -NoNewline
    try 
    {
        $AzContext = Get-AzContext -ErrorAction Stop
        $SignInUser = $AzContext.Account.Id
        $RoleAssignment = New-AzRoleAssignment `
        -SignInName $SignInUser `
        -RoleDefinitionName "$_" `
        -Scope $StorageAccount.Id `
        -WarningAction SilentlyContinue `
        -ErrorAction Stop
        Write-Host "Success!" -ForegroundColor Green
    }
    catch 
    {
        Write-Host "Failed!" -ForegroundColor Red
        Write-Warning -Message $_.Exception.Message
    }
}

# Add the backup configuration table itself to the backup
Write-Host "Adding storage configuration table to backup..." -NoNewline
try 
{
    $StorageToken = (Get-AzAccessToken -ResourceTypeName Storage -ErrorAction Stop).Token
    $GetStorageToken = $true
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning -Message $_.Exception.Message
}

if ($GetStorageToken)
{
    $Body = @{
        PartitionKey = $StorageAccountName
        RowKey = $ContainerName
        SourceTableNames = "$TableName"
    }
    $Headers = @{
        Accept = "application/json;odata=nometadata"
        'x-ms-version' = "2020-08-04"
        'x-ms-date' = $((Get-Date).ToUniversalTime().toString('R'))
        Authorization = "Bearer " + $StorageToken
        'Content-Length' = ($body | ConvertTo-Json).Length
    }
    $TableURL = "$($BackupConfigurationTable.Uri)(PartitionKey='$($Body['PartitionKey'])',RowKey='$($Body['RowKey'])')"
    try 
    {
        $Response = Invoke-WebRequest -Method PUT -Uri $TableURL -Headers $headers -Body ($body | ConvertTo-Json) -ContentType application/json 
        Write-Host "Success! ($($Response.StatusCode))" -ForegroundColor Green 
    }
    catch 
    {
        Write-Host "Failed!" -ForegroundColor Red
        $Response = $_
        [PSCustomObject]@{
            Message = $response.Exception.Message
            StatusCode = $response.Exception.Response.StatusCode
            StatusDescription = $response.Exception.Response.StatusDescription
        }
        Write-Warning $Response
    }
}

# Download the ZIP deploy package
Write-Host "Downloading ZIP deploy package..." -NoNewline
$URL = "https://github.com/SMSAgentSoftware/AzureTableBackup/raw/main/backupAzureTables.zip"
$FileName = $URL.Split('/')[-1]
$Destination = "$env:USERPROFILE\Downloads\$Filename"
$Response = Invoke-WebRequest -Uri $URL -OutFile $Destination -UseBasicParsing -ErrorAction SilentlyContinue
If (-not ([System.IO.File]::Exists($Destination)))
{
    Write-Host "Failed!" -ForegroundColor Red
    Throw "Failed to download the ZIP deploy package"
}
Write-Host "Success!" -ForegroundColor Green

# Deploy the Azure function
Write-Host "Deploying the Azure function to the function app..." -NoNewline
try 
{
    $WebApp = Publish-AzWebapp `
        -ResourceGroupName $ResourceGroupName `
        -Name $FunctionAppName `
        -ArchivePath $Destination `
        -Force `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning -Message $_.Exception.Message
}

# Add https://portal.azure.com to function app CORS