# Invoke-FraudCohortScorer.ps1
<#
.SYNOPSIS
    AI Behavioural Cohort Scorer for Fabric Real-Time Intelligence & Azure Managed Redis fraud interception.
.DESCRIPTION
    Scores multi-dimensional checkout entropy (BIN velocity, distinct BIN spread, device fingerprint entropy,
    datacentre ASN ratio, and geo-velocity) and dynamically calibrates 3DS2 step-up vs hard-drop thresholds
    to protect peak-hour merchant conversion (respecting ADR-001 false-positive ceiling).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [PSCustomObject]$CohortTelemetry,

    [Parameter()]
    [ValidateRange(0.50, 0.95)]
    [double]$HardDropThreshold = 0.82,

    [Parameter()]
    [ValidateRange(0.20, 0.75)]
    [double]$StepUpThreshold = 0.32,

    [Parameter()]
    [string]$FoundryEndpoint = '',

    [Parameter()]
    [string]$FoundryApiKey = '',

    [Parameter()]
    [string]$FoundryDeployment = 'gpt-4o',

    [Parameter()]
    [string]$FoundryApiVersion = '2024-10-21',

    [Parameter()]
    [switch]$UseLiveFoundry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($UseLiveFoundry) {
    if ([string]::IsNullOrWhiteSpace($FoundryEndpoint)) {
        throw [System.ArgumentException]::new('Fail-closed: -FoundryEndpoint is required when -UseLiveFoundry is specified.')
    }
    if ($FoundryEndpoint -notmatch '^https://') {
        throw [System.ArgumentException]::new('Fail-closed: -FoundryEndpoint must use https://.')
    }
}

function Get-FoundryAuthHeader {
    param([string]$ApiKey)
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        return @{
            'api-key'      = $ApiKey
            'Content-Type' = 'application/json'
        }
    }
    if (Get-Command -Name 'Get-AzAccessToken' -ErrorAction SilentlyContinue) {
        $tok = Get-AzAccessToken -ResourceUrl 'https://cognitiveservices.azure.com' -ErrorAction Stop
        $rawToken = if ($tok.Token -is [System.Security.SecureString]) {
            [System.Net.NetworkCredential]::new('', $tok.Token).Password
        } else {
            [string]$tok.Token
        }
        return @{
            'Authorization' = "Bearer $rawToken"
            'Content-Type'  = 'application/json'
        }
    }
    $imdsUri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://cognitiveservices.azure.com'
    $imdsResp = Invoke-RestMethod -Method Get -Uri $imdsUri -Headers @{ Metadata = 'true' } -TimeoutSec 5 -ErrorAction Stop
    return @{
        'Authorization' = "Bearer $($imdsResp.access_token)"
        'Content-Type'  = 'application/json'
    }
}

function Invoke-FoundryJsonInference {
    param(
        [string]$Endpoint,
        [string]$ApiKey,
        [string]$Deployment,
        [string]$ApiVersion,
        [string]$SystemPrompt,
        [hashtable]$Payload
    )
    $uri = if ($Endpoint -match '/chat/completions') {
        $Endpoint
    } else {
        "$($Endpoint.TrimEnd('/'))/openai/deployments/$Deployment/chat/completions?api-version=$ApiVersion"
    }
    $headers = Get-FoundryAuthHeader -ApiKey $ApiKey
    $body = @{
        temperature     = 0.0
        response_format = @{ type = 'json_object' }
        messages        = @(
            @{ role = 'system'; content = $SystemPrompt },
            @{ role = 'user'; content = ($Payload | ConvertTo-Json -Depth 6 -Compress) }
        )
    } | ConvertTo-Json -Depth 8 -Compress

    $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 30 -ErrorAction Stop
    $content = $resp.choices[0].message.content
    return ($content | ConvertFrom-Json -ErrorAction Stop)
}

# Normalise multi-dimensional checkout signals into [0.0, 1.0] risk components
$binVelNorm = [math]::Min(1.0, ([double]$CohortTelemetry.binVelocity10s) / 150.0)
$distinctBinNorm = [math]::Min(1.0, ([double]$CohortTelemetry.distinctBins10s) / 25.0)
$deviceNorm = [math]::Min(1.0, [math]::Max(0.0, [double]$CohortTelemetry.deviceEntropyScore))
$asnNorm = [math]::Min(1.0, [math]::Max(0.0, [double]$CohortTelemetry.asnDatacentreRatio))
$geoNorm = [math]::Min(1.0, ([double]$CohortTelemetry.geoVelocityKmPerHr) / 1200.0)

# Weighted behavioural cohort risk score
$rawScore = (0.28 * $binVelNorm) +
            (0.22 * $distinctBinNorm) +
            (0.20 * $deviceNorm) +
            (0.18 * $asnNorm) +
            (0.12 * $geoNorm)

$riskScore = [math]::Round($rawScore, 4)

# Peak-hour & Flash-Sale False-Positive Ceiling Calibration (ADR-001)
$effectiveHardDrop = $HardDropThreshold
if ($CohortTelemetry.isPeakHourWindow) {
    $effectiveHardDrop = [math]::Min(0.95, $HardDropThreshold + 0.06)
}
$isFlashSale = [bool]($CohortTelemetry.PSObject.Properties['isKnownFlashSaleMerchant'] -and $CohortTelemetry.isKnownFlashSaleMerchant)
if ($isFlashSale -and $distinctBinNorm -lt 0.40) {
    # Flash sales exhibit high volume but low distinct-BIN stuffing; cap at 3DS2 step-up instead of hard drop
    $effectiveHardDrop = 0.99
}

$action = if ($riskScore -ge $effectiveHardDrop) {
    'HARD_DROP_BOT_RING'
}
elseif ($riskScore -ge $StepUpThreshold) {
    'CHALLENGE_3DS2_STEP_UP'
}
else {
    'PERMIT_FASTLANE'
}

$inferenceMode = 'DETERMINISTIC_LOCAL'
$foundryRationale = $null

if ($UseLiveFoundry) {
    $allowedActions = @('PERMIT_FASTLANE', 'CHALLENGE_3DS2_STEP_UP', 'HARD_DROP_BOT_RING')
    try {
        $foundryResult = Invoke-FoundryJsonInference `
            -Endpoint $FoundryEndpoint `
            -ApiKey $FoundryApiKey `
            -Deployment $FoundryDeployment `
            -ApiVersion $FoundryApiVersion `
            -SystemPrompt 'You are a real-time payment fraud cohort scorer. Return JSON with keys: recommendedAction (PERMIT_FASTLANE|CHALLENGE_3DS2_STEP_UP|HARD_DROP_BOT_RING), rationale (string).' `
            -Payload @{
                caseId                   = $CohortTelemetry.caseId
                merchantTenantId         = $CohortTelemetry.merchantTenantId
                riskScore                = $riskScore
                effectiveHardDrop        = $effectiveHardDrop
                stepUpThreshold          = $StepUpThreshold
                isPeakHourWindow         = [bool]$CohortTelemetry.isPeakHourWindow
                isKnownFlashSaleMerchant = $isFlashSale
                deterministicAction      = $action
            }

        $llmAction = if ($null -ne $foundryResult.PSObject.Properties['recommendedAction']) { [string]$foundryResult.recommendedAction } else { '' }
        if ($llmAction -in $allowedActions) {
            # ADR-001 guard: never escalate flash-sale merchant with low distinct BIN stuffing to HARD_DROP_BOT_RING
            if (-not ($isFlashSale -and $distinctBinNorm -lt 0.40 -and $llmAction -eq 'HARD_DROP_BOT_RING')) {
                $action = $llmAction
            }
            $inferenceMode = 'LIVE_FOUNDRY'
            if ($null -ne $foundryResult.PSObject.Properties['rationale']) {
                $foundryRationale = [string]$foundryResult.rationale
            }
        } else {
            Write-Warning "Foundry returned invalid recommendedAction '$llmAction'; falling back to deterministic cohort score."
            $inferenceMode = 'DETERMINISTIC_FALLBACK'
        }
    } catch {
        Write-Warning "Live Foundry inference failed ($($_.Exception.Message)); falling back to deterministic cohort score."
        $inferenceMode = 'DETERMINISTIC_FALLBACK'
    }
}

return [PSCustomObject]@{
    CaseId                = $CohortTelemetry.caseId
    MerchantTenantId      = $CohortTelemetry.merchantTenantId
    RiskScore             = $riskScore
    EffectiveHardDrop     = $effectiveHardDrop
    StepUpThreshold       = $StepUpThreshold
    RecommendedAction     = $action
    RequiresSocEscalation = ($action -eq 'HARD_DROP_BOT_RING')
    PeakConversionGuard   = [bool]$CohortTelemetry.isPeakHourWindow
    InferenceMode         = $inferenceMode
    FoundryRationale      = $foundryRationale
}
