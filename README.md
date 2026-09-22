# Azure Toronto Data Platform

_Portfolio sprint timeline: January–September 2026. Reported results retain their actual run dates._

The Azure-native version of [toronto-open-data-pipeline](https://github.com/prhoguns/toronto-open-data-pipeline):
**Data Factory → ADLS Gen2 → Databricks (PySpark, Delta, medallion) → Synapse serverless SQL → Power BI**,
deployed with Bicep. Same source data, same gold star schema, same numbers.

| | |
|---|---|
| Infrastructure | [`infra/main.bicep`](infra/main.bicep): ADLS Gen2, Data Factory, Databricks, Synapse (serverless), Key Vault, managed-identity RBAC |
| Orchestration | [`adf/`](adf/): pipeline, datasets, linked services, daily trigger, as ADF Git-integration JSON |
| Transformation | [`databricks/notebooks/`](databricks/notebooks/): bronze → silver → gold in PySpark, with data-quality asserts |
| Serving | [`synapse/sql/`](synapse/sql/): external data source + `gold.*` views over Delta, T-SQL sample queries |
| Verification | [`tests/run_local.py`](tests/run_local.py): runs the notebooks on plain Spark in Docker against the real files |

Architecture and cost notes: [docs/architecture.md](docs/architecture.md)

## Verified without a subscription

The notebooks are ordinary Python. `tests/run_local.py` strips the Databricks magics and executes them on a
local Spark 3.4 container against the three real City of Toronto files:

```
=== 01b_bronze_to_silver_neighbourhoods.py
silver neighbourhoods: 158 rows
=== 01_bronze_to_silver.py
bronze rows: 452,949
silver rows: 452,949 - quality gates passed
=== 02_silver_to_gold.py
gold: dim_date=5,114 dim_neighbourhood=158 fct=451,229 agg=81,839
```

These row counts match the dbt build in the sister project exactly, which is the point: the
transformation logic is the same in both stacks; only the platform differs.

`az bicep build` validates the infrastructure template in CI on every push.

## Deploy

```bash
az login
export SYNAPSE_SQL_PASSWORD='<strong password>'
./infra/deploy.sh                        # ~10 min; writes infra/outputs.json
./scripts/publish_adf.sh                 # pushes adf/ definitions to the factory
```

Then, once:

1. Databricks: Repos → add this repository; the pipeline references `/Repos/toronto/databricks/notebooks/...`.
2. Synapse Studio → SQL script: run `synapse/sql/01_setup.sql` (fill in the storage account name) then `02_views.sql`.
3. ADF Studio: author the `df_unpivot_profiles` data flow (Unpivot transformation; see `adf/README.md`), publish, enable trigger `tr_daily_0600`.
4. Power BI: connect to the Synapse serverless endpoint (`infra/outputs.json → synapseServerlessEndpoint`), database `toronto`, schema `gold`.

Tear down: `az group delete -n rg-toronto-data --yes`.

## Layout

```
infra/       main.bicep · main.bicepparam · deploy.sh
adf/         linkedService/ dataset/ pipeline/ trigger_daily.json
databricks/  notebooks/00_config · 01_bronze_to_silver · 01b_..._neighbourhoods · 02_silver_to_gold
synapse/     sql/01_setup · 02_views · 03_sample_queries
tests/       run_local.py (Spark-in-Docker verification)
docs/        architecture.md
```

## Acknowledgments

AI tools assisted with documentation and repository organization.
