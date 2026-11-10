# Test-EventHubVelocityShunt.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [PSCustomObject]$WindowTelemetry
)

$ErrorActionPreference = 'Stop'

# 1. Hard Shunt on High-Velocity BIN-Stuffing Signature (>150 tx/10s or >25 distinct BINs/10s)
if ($WindowTelemetry.TxCount10s -gt 150 -or $WindowTelemetry.DistinctBinCount10s -gt 25) {
    return [PSCustomObject]@{
        MerchantTenantId      = $WindowTelemetry.MerchantTenantId
        DeviceFingerprintHash = $WindowTelemetry.DeviceFingerprintHash
        RoutingVerdict        = 'SHUNT_TO_QUARANTINE_HUB'
        TargetEventHub        = 'eh-tx-quarantine-hold'
        FastLaneProtected     = $true
    }
}

# 2. Protect Downstream Consumers if Partition Lag Breaches 5,000 Unread Events
if ($WindowTelemetry.ConsumerGroupLagEvents -gt 5000) {
    return [PSCustomObject]@{
        MerchantTenantId      = $WindowTelemetry.MerchantTenantId
        DeviceFingerprintHash = $WindowTelemetry.DeviceFingerprintHash
        RoutingVerdict        = 'TRIP_BACKPRESSURE_SHED_NON_CRITICAL'
        TargetEventHub        = 'eh-tx-quarantine-hold'
        FastLaneProtected     = $true
    }
}

return [PSCustomObject]@{
    MerchantTenantId      = $WindowTelemetry.MerchantTenantId
    DeviceFingerprintHash = $WindowTelemetry.DeviceFingerprintHash
    RoutingVerdict        = 'ROUTE_TO_VERIFIED_FASTLANE'
    TargetEventHub        = 'eh-tx-verified-fastlane'
    FastLaneProtected     = $true
}
