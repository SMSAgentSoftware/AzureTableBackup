############################################################################################
## Deploys and configures the Azure resources required by the Azure Table Backup solution ##
############################################################################################

#! Run this script with the [Owner] or [Contributer + User Access Administrator] roles in the Azure subscription !#

## Check required modules
#Requires -Modules Az.Accounts,Az.Resources,Az.Storage,Az.OperationalInsights,Az.ApplicationInsights,Az.Functions,Az.WebSites

### VARIABLES TO SET
$Tenant = "<tenant Id>"# The ID of the tenant containing your Azure subscription
$Subscription = "<subscription name>" # The name of the Azure subscription which will host your resources
$Location = "East US" # The Azure region for your resources. Find available regions like so: Get-AzLocation | Where {$_.RegionType -eq "Physical"} | Select -ExpandProperty DisplayName | Sort, or here: https://azure.microsoft.com/en-us/explore/global-infrastructure/data-residency/#select-geography
###

### RESOURCE NAMES
$RandomSuffix = (New-Guid).ToString().Substring(0,8)
$ResourceGroupName = "rg-azTableBackup-$($RandomSuffix)"
$StorageAccountName = "staztablebackup$($RandomSuffix)"
$LogAnalyticsWorkspaceName = "log-azTableBackup-$($RandomSuffix)"
$ApplicationInsightsName = "appi-azTableBackup-$($RandomSuffix)"
$FunctionAppName = "func-azTableBackup-$($RandomSuffix)"
$BackupConfigurationTableName = 'AutomatedTableBackupConfiguration'
$BackupContainerName = 'tablebackups'

# Check Azure region availability
$UnavailableRegions = @{
    "China East" = "Azure Functions, Application Insights, Log Analytics"
    "China Non-Regional" = "Azure Function, Application Insights, Log Analytics, Storage Accounts"
    "China North" = "Application Insights, Log Analytics"
    "China North2" = "Application Insights, Log Analytics"
    "West Central US" = "Application Insights"
}

If ($UnavailableRegions.Keys -contains $Location)
{
    Write-Host "Sorry, the following resources are not available in the $location region: $($UnavailableRegions["$Location"])" -ForegroundColor Red
    return
}

# Connect to Azure AD
try 
{
    $Connection = Connect-AzAccount -Subscription $Subscription -Tenant $Tenant -ErrorAction Stop
}
catch 
{
    throw $_.Exception.Message
}

# Check role assignments
try 
{
    $RoleAssignments = Get-AzRoleAssignment `
        -SignInName $Connection.Context.Account.Id `
        -Scope "/subscriptions/$($Connection.Context.Subscription.id)" `
        -IncludeClassicAdministrators `
        -ErrorAction Stop |
        Where {$_.Scope -eq "/subscriptions/$($Connection.Context.Subscription.id)"}

    If ($RoleAssignments.Count -ge 1)
    {
        [array]$Roles = $RoleAssignments.RoleDefinitionName
        If (-not ($Roles -contains "ServiceAdministrator" -or $Roles -contains "CoAdministrator" -or $Roles -contains "Owner" -or ($Roles -contains "Contributor" -and $Roles -contains "User Access Administrator")))
        {
            throw "The signed-in user does not have the required role assignments in this subscription. Either the 'Owner' role or the 'Contributor' PLUS 'User Access Administrator' roles are required"
        }
    }
    else 
    {
        throw "The signed-in user does not have the required role assignments in this subscription. Either the 'Owner' role or the 'Contributor' PLUS 'User Access Administrator' roles are required"    
    }
}
catch 
{
    throw $_.Exception.Message
}

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
    Write-Error $_.Exception.Message.Split([Environment]::NewLine)[0]
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
    Write-Error -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
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
    Write-Warning $_.Exception.Message.Split([Environment]::NewLine)[0]
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
    Write-Warning $_.Exception.Message.Split([Environment]::NewLine)[0]
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
    Write-Error -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
    return
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
    Write-Error -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
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
    Write-Error -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
    return
}

# Create a function app
Write-Host "Creating a function app..." -NoNewline
$AppSettings = @{
    'BackupConfigurationStorageAccount' = $StorageAccountName
    'BackupConfigurationStorageTable' = $BackupConfigurationTableName
    'BackupConfigurationTimerExpression' = "0 0 1 * * *"
    'WEBSITE_RUN_FROM_PACKAGE' = "1"
    'FUNCTIONS_WORKER_RUNTIME' = "dotnet-isolated"   
}
try 
{
    $FunctionApp = New-AzFunctionApp `
        -Name $FunctionAppName `
        -StorageAccountName $StorageAccountName `
        -Location $Location `
        -ResourceGroupName $ResourceGroupName `
        -Runtime DotNet `
        -RuntimeVersion 8 `
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
    Write-Error -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
    return
}

# Add portal.azure.com to CORS
Write-Host "Adding 'portal.azure.com' to CORS on function app..." -NoNewline
try 
{
    $AzResourceParams = @{
        ResourceGroupName = $ResourceGroupName
        ResourceName = $FunctionAppName
        ResourceType =  "Microsoft.Web/sites"
    }
    $WebAppResource = Get-AzResource @AzResourceParams -ErrorAction Stop
    $WebAppResource.Properties.siteConfig.cors = @{
        allowedOrigins = @("https://portal.azure.com")
    }
    $Update = $WebAppResource | Set-AzResource -Force -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Error -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
    return
}

# Assign Azure roles
# note the required permissions
# https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-powershell#prerequisites
Write-Host "Adding role assignments for current user to storage account..."
"Storage Table Data Contributor","Storage Blob Data Contributor" | foreach {
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
        Write-Warning -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
    }
}

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
        Write-Warning -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
    }
}

# Create backup configuration table
Write-Host "Creating a backup configuration table..." -NoNewline
Write-Host "$BackupConfigurationTableName..." -NoNewline
try 
{
    $BackupConfigurationTable = New-AzStorageTable `
        -Name "$BackupConfigurationTableName" `
        -Context $StorageContext `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
}

# Create backup container
Write-Host "Creating a backup container..." -NoNewline
Write-Host "$BackupContainerName..." -NoNewline
try 
{
    $BackupConfigurationContainer = New-AzStorageContainer `
        -Name "$BackupContainerName" `
        -Context $StorageContext `
        -Permission Off `
        -ErrorAction Stop
    Write-Host "Success!" -ForegroundColor Green
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
}

# Add the backup configuration table itself to the backup
Write-Host "Adding storage configuration table to backup..." -NoNewline
try 
{
    $StorageToken = (Get-AzAccessToken -ResourceTypeName Storage -AsSecureString -ErrorAction Stop).Token | ConvertFrom-SecureString -AsPlainText
    $GetStorageToken = $true
}
catch 
{
    Write-Host "Failed!" -ForegroundColor Red
    Write-Warning -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
}

if ($GetStorageToken)
{
    $Body = @{
        PartitionKey = $StorageAccountName
        RowKey = $BackupContainerName
        SourceTableNames = "$BackupConfigurationTableName"
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
$URL = "https://github.com/SMSAgentSoftware/AzureTableBackup/raw/main/backupAzureTableNet8.zip"
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
    Write-Warning -Message $_.Exception.Message.Split([Environment]::NewLine)[0]
}
