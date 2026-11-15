# Real-Time Fraud Interception & Fabric RTI Triage Runbook

**Operational Scope:** Azure Event Hubs ingestion, Microsoft Fabric Real-Time Intelligence (Eventstream + KQL Eventhouse), Azure Managed Redis sliding-window state, AI Behavioural Cohort Scorer, and Microsoft Graph v2.x SOC escalations.
**Owner:** Payments Risk & Platform SRE (Contoso Retail)

---

## 1. Architecture & False-Positive Ceiling Invariants

1. **Zero-Declarative-IaC Control Plane:** Event Hubs quarantine partition policies and Fabric RTI Eventhouse streaming ingestion settings are synchronised via `src/Invoke-FabricRtiEventhouseSync.ps1` using `Invoke-AzRestMethod` and the Fabric REST API.
2. **Peak-Hour Conversion Protection (ADR-001):** During peak-hour trading or verified merchant flash sales, `ai/Invoke-FraudCohortScorer.ps1` raises the `EffectiveHardDrop` threshold (+0.06 peak buffer; capped at 3DS2 step-up when `distinctBinNorm < 0.40`) so legitimate customer surges are never dropped.
3. **Fast-Lane Isolation:** Verified payment traffic (`PERMIT_FASTLANE`) routes to `eh-tx-verified-fastlane`, while BIN-stuffing attacks (`>150 tx/10s` or `>25 distinct BINs/10s`) shunt to `eh-tx-quarantine-hold` via `src/Test-EventHubVelocityShunt.ps1`.

---

## 2. L2/L3 Incident Triage Procedures

### Scenario A: `HARD_DROP_BOT_RING` & `SHUNT_TO_QUARANTINE_HUB`
- **Symptom:** `queries/Payment-Velocity-Spikes.kql` in Fabric Eventhouse reports >150 tx/10s from a high-datacentre ASN ratio (`> 0.80`) and `graph/Send-SocFraudEscalationCard.ps1` posts an Attention card to the SOC Teams channel.
- **Diagnosis:**
  1. Inspect `RiskScore` and `distinctBins10s` in the Adaptive Card.
  2. Verify whether the source ASN belongs to a known cloud hosting provider rather than a consumer ISP.
- **Remediation:**
  1. Confirm the quarantine shunt in Teams (`confirm_quarantine_shunt`) to keep `eh-tx-verified-fastlane` latency below 35 ms.
  2. Export offending `DeviceFingerprintHash` values from Fabric Eventhouse to Azure Front Door WAF rate-limit rules.

### Scenario B: False-Positive Alert During Merchant Flash Sale
- **Symptom:** High transaction velocity (`binVelocity10s ~ 78`) triggers elevated `RiskScore`, but `distinctBins10s` remains low (`< 10`).
- **Remediation:**
  1. Ensure `isKnownFlashSaleMerchant: true` is set in the merchant cohort profile so `Invoke-FraudCohortScorer.ps1` routes to `CHALLENGE_3DS2_STEP_UP` rather than `HARD_DROP_BOT_RING`.
  2. Click **Downgrade to 3DS2 Step-Up** on the SOC Adaptive Card if an automated hard-drop occurred.

### Scenario C: Consumer Group Backpressure (`TRIP_BACKPRESSURE_SHED_NON_CRITICAL`)
- **Symptom:** `ConsumerGroupLagEvents > 5000` in Event Hubs.
- **Remediation:** Verify Fabric Eventstream checkpointing health and scale Event Hubs throughput units via `Invoke-AzRestMethod` until lag drops below 1,000 events.
