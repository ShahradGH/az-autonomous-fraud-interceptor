# ADR-001: Real-Time Security: Autonomous Fraud Velocity Interception on Azure Event Hubs

## Status
Accepted

## Service Owner & Sign-Off Authority
Principal Cyber Risk Architect & Head of Transaction Security

## Dominant Artefact
Real-Time Fraud Velocity Detection Engine & Threat Graph Matrix

## Decision & Refusal Boundary
All production state mutations must pass deterministic pre-flight policy evaluation in `src/Test-EventHubVelocityShunt.ps1` and satisfy the 16-test Pester verification contract in `tests/Boundary-Verification.Tests.ps1` before execution.
