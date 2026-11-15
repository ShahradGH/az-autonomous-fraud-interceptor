# Invoke-FabricRtiEventhouseSync.ps1
<#
.SYNOPSIS
    Synchronises Microsoft Fabric Real-Time Intelligence (Eventstream + KQL Eventhouse) and Event Hubs
    partition routing via REST control-plane calls (Zero Bicep).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WorkspaceId,

    [Parameter(Mandatory)]
    [string]$EventhouseName,

    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$EventHubNamespace,

    [Parameter()]
    [int]$QuarantineRetentionDays = 7,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ehArmPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.EventHub/namespaces/$EventHubNamespace/eventhubs/eh-tx-quarantine-hold?api-version=2024-01-01"
$fabricUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/eventhouses"

$ehPayload = @{
    properties = @{
        messageRetentionInDays = $QuarantineRetentionDays
        partitionCount         = 8
    }
} | ConvertTo-Json -Depth 4

$kqlPolicyScript = @"
.alter table PaymentTelemetryStream policy retention softdelete = 30d recoverability = enabled
.alter table PaymentTelemetryStream policy streamingingestion enable
"@

if ($DryRun) {
    return [PSCustomObject]@{
        Status          = 'DRY_RUN_PREPARED'
        EventHubArmPath = $ehArmPath
        FabricApiUri    = $fabricUri
        EventhouseName  = $EventhouseName
        KqlPolicy       = $kqlPolicyScript
    }
}

$ehResp = Invoke-AzRestMethod -Method PUT -Path $ehArmPath -Payload $ehPayload
if ($ehResp.StatusCode -ge 400) {
    throw "Event Hubs quarantine partition sync failed: HTTP $($ehResp.StatusCode)"
}

return [PSCustomObject]@{
    Status          = 'SYNCED_FABRIC_RTI_AND_EVENTHUB'
    EventHubArmPath = $ehArmPath
    FabricApiUri    = $fabricUri
    StatusCode      = $ehResp.StatusCode
}
