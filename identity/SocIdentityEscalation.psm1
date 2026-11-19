<#
.SYNOPSIS
    Microsoft Graph v2.x SOC responder and Entra ID Identity Protection module for Fraud Interception.
.DESCRIPTION
    Resolves active Payments Risk & SOC on-call responders from Entra ID groups, inspects Entra ID
    Identity Protection risky users for correlated merchant credential-stuffing, and dispatches
    Teams fraud-case escalation threads via Microsoft Graph v1.0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-SocGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [scriptblock]$GraphInvoker
    )

    if ($null -ne $GraphInvoker) {
        return & $GraphInvoker $Method $Uri $Body
    }

    $params = @{
        Method = $Method
        Uri    = $Uri
    }
    if ($null -ne $Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
        $params['ContentType'] = 'application/json'
    }

    return Invoke-MgGraphRequest @params
}

function Get-SocOnCallResponderRoster {
    <#
    .SYNOPSIS
        Queries Microsoft Graph v1.0 to resolve active, enabled Payments Risk & SOC responders in an Entra ID group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SocGroupId,

        [Parameter()]
        [scriptblock]$GraphInvoker
    )

    $uri = "https://graph.microsoft.com/v1.0/groups/$SocGroupId/members?`$select=id,displayName,userPrincipalName,accountEnabled"
    $resp = Invoke-SocGraphRequest -Method 'GET' -Uri $uri -GraphInvoker $GraphInvoker
    $members = @($resp.value)

    $active = @($members | Where-Object { $_.accountEnabled -eq $true })

    return [PSCustomObject]@{
        SocGroupId         = $SocGroupId
        TotalMembers       = $members.Count
        ActiveResponders   = $active.Count
        ResponderUpns      = @($active | ForEach-Object { $_.userPrincipalName })
        RosterReady        = ($active.Count -gt 0)
        ResolvedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Test-MerchantAdminSignInRisk {
    <#
    .SYNOPSIS
        Checks Entra ID Identity Protection riskyUsers to detect compromised merchant admin accounts during velocity spikes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserId,

        [Parameter()]
        [scriptblock]$GraphInvoker
    )

    $uri = "https://graph.microsoft.com/v1.0/identityProtection/riskyUsers/$UserId"
    $riskUser = Invoke-SocGraphRequest -Method 'GET' -Uri $uri -GraphInvoker $GraphInvoker

    $isElevatedRisk = ($riskUser.riskLevel -in @('high', 'medium')) -and ($riskUser.riskState -in @('atRisk', 'confirmedCompromised'))

    return [PSCustomObject]@{
        UserId             = $riskUser.id
        UserPrincipalName  = $riskUser.userPrincipalName
        RiskLevel          = $riskUser.riskLevel
        RiskState          = $riskUser.riskState
        RequiresTokenRevoke = $isElevatedRisk
        CheckedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Invoke-FraudCaseTeamsThread {
    <#
    .SYNOPSIS
        Dispatches a structured fraud-ring escalation message to a Teams SOC channel via Microsoft Graph.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$TeamId,

        [Parameter(Mandatory)]
        [string]$ChannelId,

        [Parameter(Mandatory)]
        [string]$CaseId,

        [Parameter(Mandatory)]
        [double]$RiskScore,

        [Parameter(Mandatory)]
        [string]$RecommendedAction,

        [Parameter()]
        [scriptblock]$GraphInvoker
    )

    $uri = "https://graph.microsoft.com/v1.0/teams/$TeamId/channels/$ChannelId/messages"
    $payload = @{
        body = @{
            contentType = 'html'
            content     = "<b>Fraud Interception Escalation</b> | Case: $CaseId | RiskScore: $RiskScore | Action: <code>$RecommendedAction</code>"
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$TeamId/$ChannelId", "Post fraud case $CaseId to Teams SOC")) {
        return [PSCustomObject]@{
            CaseId     = $CaseId
            Dispatched = $false
            MessageId  = 'WHATIF-DRYRUN'
        }
    }

    $resp = Invoke-SocGraphRequest -Method 'POST' -Uri $uri -Body $payload -GraphInvoker $GraphInvoker
    return [PSCustomObject]@{
        CaseId     = $CaseId
        Dispatched = $true
        MessageId  = $resp.id
    }
}

Export-ModuleMember -Function @(
    'Get-SocOnCallResponderRoster',
    'Test-MerchantAdminSignInRisk',
    'Invoke-FraudCaseTeamsThread'
)
