# Architecture

```mermaid
flowchart LR
    CKAN[open.toronto.ca<br/>CKAN HTTP] -->|ADF Copy| B[(ADLS Gen2<br/>bronze/)]
    B -->|Databricks 01, 01b| S[(silver/<br/>Delta, typed, partitioned)]
    S -->|Databricks 02| G[(gold/<br/>Delta star schema)]
    G -->|OPENROWSET| SYN[Synapse serverless SQL<br/>gold.* views]
    SYN --> PBI[Power BI]
    G -.->|OneLake shortcuts, optional| FAB[Fabric Lakehouse<br/>SQL endpoint, gold.* views]
    FAB -.->|Direct Lake| PBI
    ADF[Data Factory<br/>pl_toronto_open_data<br/>daily 06:00 ET] -. orchestrates .-> B & S & G & SYN
    KV[Key Vault] -. secrets .-> ADF
```

## Medallion layers

| Layer | Format | Grain | Who writes | Rule |
|---|---|---|---|---|
| bronze | CSV as downloaded, `table/run_date/` | source | Data Factory | never modified; a new run_date folder per day |
| silver | Delta, partitioned by `occurrence_year` | one row per offence per event | notebook 01 / 01b | typed, trimmed, de-duplicated; data-quality asserts fail the job |
| gold | Delta | star schema + aggregates | notebook 02 | business rules (2014 cut-off, rate per 1,000) live here only |

## Cost profile

Everything is pay-per-use or free tier: ADLS LRS (cents), ADF (a few pipeline runs a day), Databricks
job cluster of one `Standard_DS3_v2` for ~5 minutes/day on the Premium tier (required for Unity Catalog), Synapse **serverless** (no dedicated pool, billed per TB scanned;
the gold tables are ~40 MB). Expect well under CAD $10/month. Tear down with `az group delete -n rg-toronto-data`.

## Security

- No keys anywhere: Data Factory, Synapse and the Databricks access connector (Unity Catalog's
  storage credential) use system-assigned managed identities, granted Storage Blob Data
  Contributor on the lake. Storage account keys and local users are disabled, so nothing else can
  get in.
- Synapse accepts Entra ID logins only; there is no SQL admin password.
- Storage: HNS on, public blob access off, TLS 1.2 minimum, infrastructure encryption.
- Key Vault with RBAC authorization and purge protection.
- The same controls are defined in both `infra/main.bicep` and `infra/terraform/`.
