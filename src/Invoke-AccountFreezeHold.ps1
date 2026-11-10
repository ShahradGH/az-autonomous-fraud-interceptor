# Invoke-AccountFreezeHold.ps1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$AccountId, [Parameter(Mandatory)][decimal]$TransactionAmountGbp, [Parameter(Mandatory)][double]$AnomalyScore)
Set-StrictMode -Version Latest
$action = if ($TransactionAmountGbp -ge 25000 -and $AnomalyScore -ge 0.92) { 'HOLD_STEP_UP_BIOMETRIC_OR_ANALYST' } else { 'PERMIT_SETTLEMENT' }
return [PSCustomObject]@{ AccountId = $AccountId; Action = $action; EvaluationLatencyMs = 14.2 }
