# Send-SocFraudEscalationCard.ps1
<#
.SYNOPSIS
    Dispatches a Real-Time Fraud Ring & Cohort Escalation Adaptive Card to the SOC Teams channel via Graph v2.x.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [PSCustomObject]$CohortVerdict,

    [Parameter(Mandatory)]
    [string]$TeamId,

    [Parameter(Mandatory)]
    [string]$ChannelId,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cardColour = if ($CohortVerdict.RecommendedAction -eq 'HARD_DROP_BOT_RING') { 'Attention' } else { 'Warning' }

$adaptiveCard = [ordered]@{
    type    = 'AdaptiveCard'
    version = '1.5'
    body    = @(
        @{
            type   = 'TextBlock'
            text   = "Fabric RTI Fraud Interceptor: $($CohortVerdict.RecommendedAction)"
            weight = 'Bolder'
            size   = 'Medium'
            color  = $cardColour
        }
        @{
            type  = 'FactSet'
            facts = @(
                @{ title = 'Case ID'; value = $CohortVerdict.CaseId }
                @{ title = 'Merchant Tenant'; value = $CohortVerdict.MerchantTenantId }
                @{ title = 'Cohort Risk Score'; value = "$($CohortVerdict.RiskScore)" }
                @{ title = 'Effective Hard-Drop'; value = "$($CohortVerdict.EffectiveHardDrop)" }
                @{ title = 'Peak Conversion Guard'; value = "$($CohortVerdict.PeakConversionGuard)" }
            )
        }
    )
    actions = @(
        @{
            type  = 'Action.Submit'
            title = 'Confirm Bot-Ring Quarantine Shunt'
            data  = @{ action = 'confirm_quarantine_shunt'; caseId = $CohortVerdict.CaseId }
        }
        @{
            type  = 'Action.Submit'
            title = 'Downgrade to 3DS2 Step-Up'
            data  = @{ action = 'downgrade_to_3ds2'; caseId = $CohortVerdict.CaseId }
        }
    )
}

$attachmentId = [guid]::NewGuid().ToString()
$graphPayload = [ordered]@{
    body = @{
        contentType = 'html'
        content     = "<attachment id=`"$attachmentId`"></attachment>"
    }
    attachments = @(
        @{
            id          = $attachmentId
            contentType = 'application/vnd.microsoft.card.adaptive'
            content     = ($adaptiveCard | ConvertTo-Json -Depth 12 -Compress)
        }
    )
}

$graphUri = "https://graph.microsoft.com/v1.0/teams/$TeamId/channels/$ChannelId/messages"

if ($DryRun) {
    return [PSCustomObject]@{
        Status       = 'DRY_RUN_PREPARED'
        GraphUri     = $graphUri
        AttachmentId = $attachmentId
        Payload      = $graphPayload
    }
}

$resp = Invoke-MgGraphRequest -Method POST -Uri $graphUri -Body ($graphPayload | ConvertTo-Json -Depth 12) -ContentType 'application/json'
return [PSCustomObject]@{
    Status       = 'DISPATCHED_TO_SOC_TEAMS'
    GraphUri     = $graphUri
    MessageId    = $resp.id
    AttachmentId = $attachmentId
}
