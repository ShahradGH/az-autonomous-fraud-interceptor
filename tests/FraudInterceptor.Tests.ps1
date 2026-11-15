BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ShuntScript = Join-Path $script:RepoRoot 'src/Test-EventHubVelocityShunt.ps1'
    $script:FabricSyncScript = Join-Path $script:RepoRoot 'src/Invoke-FabricRtiEventhouseSync.ps1'
    $script:CohortScorerScript = Join-Path $script:RepoRoot 'ai/Invoke-FraudCohortScorer.ps1'
    $script:CalibrationPath = Join-Path $script:RepoRoot 'ai/fraud-calibration-eval.json'
    $script:SocGraphScript = Join-Path $script:RepoRoot 'graph/Send-SocFraudEscalationCard.ps1'
    $script:KqlPath = Join-Path $script:RepoRoot 'queries/Payment-Velocity-Spikes.kql'
    $script:CalibrationCases = Get-Content -Path $script:CalibrationPath -Raw | ConvertFrom-Json
}

Describe 'Real-Time Fraud Interception: Fabric RTI, Event Hubs & AI Cohort Scorer Suite' {
    Context 'Event Hubs Velocity Shunt & Fabric RTI Control Plane' {
        It 'Routes normal checkout telemetry to verified fastlane' {
            $win = [PSCustomObject]@{
                MerchantTenantId       = 'contoso-uk-retail'
                DeviceFingerprintHash  = 'fp-001'
                TxCount10s             = 12
                DistinctBinCount10s    = 3
                ConsumerGroupLagEvents = 120
            }
            $res = & $script:ShuntScript -WindowTelemetry $win
            $res.RoutingVerdict | Should -Be 'ROUTE_TO_VERIFIED_FASTLANE'
            $res.TargetEventHub | Should -Be 'eh-tx-verified-fastlane'
        }

        It 'Shunts high-velocity BIN-stuffing attack (>150 tx/10s) to quarantine hub' {
            $win = [PSCustomObject]@{
                MerchantTenantId       = 'contoso-uk-retail'
                DeviceFingerprintHash  = 'fp-bot-99'
                TxCount10s             = 210
                DistinctBinCount10s    = 34
                ConsumerGroupLagEvents = 400
            }
            $res = & $script:ShuntScript -WindowTelemetry $win
            $res.RoutingVerdict | Should -Be 'SHUNT_TO_QUARANTINE_HUB'
            $res.TargetEventHub | Should -Be 'eh-tx-quarantine-hold'
        }

        It 'Prepares Fabric RTI Eventhouse & Event Hubs ARM REST sync in DryRun mode' {
            $sync = & $script:FabricSyncScript -WorkspaceId '00000000-0000-0000-0000-000000000010' -EventhouseName 'ehouse-contoso-fraud' -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-contoso-rti' -EventHubNamespace 'ehns-contoso-pay' -DryRun
            $sync.Status | Should -Be 'DRY_RUN_PREPARED'
            $sync.FabricApiUri | Should -Match 'api\.fabric\.microsoft\.com/v1/workspaces/'
            $sync.KqlPolicy | Should -Match 'streamingingestion enable'
        }
    }

    Context 'AI Subcomponent: Behavioural Cohort Scorer & Peak-Conversion Guard' {
        It 'Permits low-entropy peak-hour checkout via fastlane (FRAUD-401)' {
            $case = $script:CalibrationCases | Where-Object { $_.caseId -eq 'FRAUD-401' }
            $res = & $script:CohortScorerScript -CohortTelemetry $case
            $res.RecommendedAction | Should -Be 'PERMIT_FASTLANE'
            $res.RequiresSocEscalation | Should -BeFalse
        }

        It 'Triggers 3DS2 step-up for moderate entropy during peak hours (FRAUD-402)' {
            $case = $script:CalibrationCases | Where-Object { $_.caseId -eq 'FRAUD-402' }
            $res = & $script:CohortScorerScript -CohortTelemetry $case
            $res.RecommendedAction | Should -Be 'CHALLENGE_3DS2_STEP_UP'
        }

        It 'Hard-drops high-entropy datacentre BIN-stuffing bot ring (FRAUD-403)' {
            $case = $script:CalibrationCases | Where-Object { $_.caseId -eq 'FRAUD-403' }
            $res = & $script:CohortScorerScript -CohortTelemetry $case
            $res.RecommendedAction | Should -Be 'HARD_DROP_BOT_RING'
            $res.RequiresSocEscalation | Should -BeTrue
        }

        It 'Protects flash-sale merchant from hard-drop by capping at 3DS2 step-up (FRAUD-404)' {
            $case = $script:CalibrationCases | Where-Object { $_.caseId -eq 'FRAUD-404' }
            $res = & $script:CohortScorerScript -CohortTelemetry $case
            $res.RecommendedAction | Should -Be 'CHALLENGE_3DS2_STEP_UP'
            $res.PeakConversionGuard | Should -BeTrue
        }

        It 'Fails closed when -UseLiveFoundry is set without -FoundryEndpoint and supports mocked live Foundry REST call' {
            $case = $script:CalibrationCases | Where-Object { $_.caseId -eq 'FRAUD-401' }
            { & $script:CohortScorerScript -CohortTelemetry $case -UseLiveFoundry } | Should -Throw '*FoundryEndpoint*'

            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    choices = @(
                        [PSCustomObject]@{
                            message = [PSCustomObject]@{
                                content = '{"recommendedAction":"PERMIT_FASTLANE","rationale":"Low entropy checkout during peak window."}'
                            }
                        }
                    )
                }
            }

            $res = & $script:CohortScorerScript -CohortTelemetry $case -UseLiveFoundry -FoundryEndpoint 'https://contoso-foundry.openai.azure.com' -FoundryApiKey 'test-key'
            $res.InferenceMode | Should -Be 'LIVE_FOUNDRY'
            $res.RecommendedAction | Should -Be 'PERMIT_FASTLANE'
            Should -Invoke Invoke-RestMethod -Times 1
        }
    }

    Context 'Microsoft Graph v2.x SOC Escalation & Zero-Leak Governance' {
        It 'Builds valid SOC Teams Adaptive Card payload in DryRun mode' {
            $case = $script:CalibrationCases | Where-Object { $_.caseId -eq 'FRAUD-403' }
            $verdict = & $script:CohortScorerScript -CohortTelemetry $case
            $card = & $script:SocGraphScript -CohortVerdict $verdict -TeamId '00000000-0000-0000-0000-000000000001' -ChannelId '19:soc@thread.tacv2' -DryRun
            $card.Status | Should -Be 'DRY_RUN_PREPARED'
            $card.GraphUri | Should -Match '^https://graph\.microsoft\.com/v1\.0/teams/'
        }

        It 'Contains zero Bicep or Terraform files and zero internal sequence tags' {
            $iac = Get-ChildItem -Path $script:RepoRoot -Recurse -File | Where-Object { $_.Extension -in '.bicep', '.tf' }
            $iac.Count | Should -Be 0
            (Get-Content (Join-Path $script:RepoRoot 'README.md') -Raw) | Should -Not -Match 'Decision Pack 0|mvpfoundry\.alerasoul\.net|idea-021'
            (Get-Content $script:KqlPath -Raw) | Should -Match 'summarize|where'
            (Get-Item (Join-Path $script:RepoRoot 'docs/FRAUD-TRIAGE-RUNBOOK.md')).Length | Should -BeGreaterThan 2048
        }
    }
}
