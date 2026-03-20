# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **database migration planning and documentation repository** for an online migration from **AWS RDS (Oracle SE) → OCI DBCS (Oracle SE)** using OCI GoldenGate. There is no source code, build system, or automated tests — this is an operational runbook and planning framework.

## Repository Structure

```
crscube/
├── docs/
│   └── 00. validation_plan.xlsx    # 136-item validation checklist (6 sheets)
└── plan/
    ├── migration_plan.md           # Master plan: 8-phase strategy, rollback, criteria
    ├── migration_plan_draft.md     # Draft / working version
    ├── 01.pre_migration.md         # Phase 0–2 runbook: environment, source/target DB prep
    ├── 02_migration.md             # Phase 3–5 runbook: GoldenGate setup, initial load, delta sync
    └── 03.validation.md            # Phase 6–7 runbook: validation, cut-over, post-migration
```

## Migration Architecture

```
[AWS RDS Oracle SE]
    ↓ expdp (fixed SCN)
[OCI Object Storage]
    ↓ impdp
[OCI DBCS Oracle SE]  ←  OCI GoldenGate Extract / Data Pump / Replicat (continuous delta)
```

## 8-Phase Plan Summary

| Phase | Name | Timing |
|-------|------|--------|
| 0 | Suitability & environment check | D-14 to D-7 |
| 1 | Source DB prep (AWS RDS) | D-7 to D-5 |
| 2 | Target DB prep (OCI DBCS) | D-7 to D-5 |
| 3 | OCI GoldenGate configuration | D-5 to D-3 |
| 4 | Initial data load (expdp → impdp) | D-3 to D-1 |
| 5 | Delta synchronization | D-1 to D-Day |
| 6 | Validation (136 items) | D-1 to D-Day |
| 7 | Cut-over | D-Day |
| 8 | Post-migration stabilization | D+1 to D+7 |

## Validation Framework

The `validation_plan.xlsx` tracks 136 items across 5 domains:

| Category | Items |
|----------|-------|
| 01_GG_Process | 28 — GoldenGate pre-checks, Extract, Pump, Replicat, monitoring |
| 02_Static_Schema | 38 — Tables, indexes, constraints, sequences, invalid objects |
| 03_Data_Validation | 25 — Row counts, checksums, LOB data, NLS params, referential integrity |
| 04_Special_Objects | 42 — MVs, Triggers, DB Links, DBMS_JOB→SCHEDULER, partitions |
| 05_Migration_Caution | 26 — Oracle SE limits, GoldenGate restrictions, DDL replication |

**Go/No-Go criteria:** All HIGH-priority items must PASS; WARN items must be analyzed and mitigated; no critical FAIL items.

## Key Oracle SE Constraints

- `ENABLE_GOLDENGATE_REPLICATION = TRUE` must be set manually on RDS
- Supplemental Logging (MIN) required; ALL COLUMNS logging for tables without PKs
- Streams Pool ≥ 256 MB (RDS parameter group)
- No BITMAP indexes (SE unsupported)
- DDL replication limited to TABLE objects only
- LAG target: < 30 seconds sustained for 24+ hours before cut-over

## Network Requirements

- FastConnect or Site-to-Site VPN between AWS and OCI
- RDS Security Group: allow OCI GG source IP → TCP 1521

## Rollback Window

Source RDS instance is retained for 2 weeks post-cut-over to allow rollback if needed.
