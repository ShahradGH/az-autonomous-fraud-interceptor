# Real-Time Security: Autonomous Fraud Velocity Interception on Azure Event Hubs

[![Pester Verification](https://img.shields.io/badge/pester-16%2F16%20passing-brightgreen)](tests/FraudInterceptor.Tests.ps1)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Architecture Deep-Dive](https://img.shields.io/badge/blog-alerasoul.net-0a1128)](https://alerasoul.net/autonomous-fraud-velocity-interceptor/)

> **Primary Governance Artefact:** Real-Time Fraud Velocity Detection Engine & Threat Graph Matrix  
> **Accountable Service Owner:** Principal Cyber Risk Architect & Head of Transaction Security  
> **Full Architectural Deep-Dive:** [https://alerasoul.net/autonomous-fraud-velocity-interceptor/](https://alerasoul.net/autonomous-fraud-velocity-interceptor/)

---

## Repository Layout (15 Files)

```text
├── .github/workflows/ci.yml
├── LICENSE
├── README.md
├── SECURITY.md
├── docs/ADR-001-false-positive-ceiling.md
├── docs/FRAUD-TRIAGE-RUNBOOK.md
├── fixtures/synthetic-payment-stream.json
├── infra/cosmos-changefeed-processor.bicep
├── infra/eventhub-ingress.bicep
├── queries/Payment-Velocity-Spikes.kql
├── rules/velocity-ring-heuristics.json
├── schemas/iso20022-pacs008-event.json
├── src/Invoke-AccountFreezeHold.ps1
├── src/Test-EventHubVelocityShunt.ps1
└── tests/FraudInterceptor.Tests.ps1
```

## Quickstart & Offline Verification

```powershell
# 1. Execute the primary PowerShell 7 evaluator
pwsh -NoProfile -File ./src/Test-EventHubVelocityShunt.ps1

# 2. Run the 16-test Pester verification contract
Invoke-Pester -Path ./tests/FraudInterceptor.Tests.ps1 -Output Detailed
```

## License

Released under the [MIT License](LICENSE). Authored by **Shahrad Alerasoul** ([alerasoul.net](https://alerasoul.net)).
