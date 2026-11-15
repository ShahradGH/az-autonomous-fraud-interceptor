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
    [double]$StepUpThreshold = 0.32
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

return [PSCustomObject]@{
    CaseId               = $CohortTelemetry.caseId
    MerchantTenantId     = $CohortTelemetry.merchantTenantId
    RiskScore            = $riskScore
    EffectiveHardDrop    = $effectiveHardDrop
    StepUpThreshold      = $StepUpThreshold
    RecommendedAction    = $action
    RequiresSocEscalation = ($action -eq 'HARD_DROP_BOT_RING')
    PeakConversionGuard  = [bool]$CohortTelemetry.isPeakHourWindow
}
