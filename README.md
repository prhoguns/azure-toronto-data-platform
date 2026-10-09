# Azure Toronto Data Platform

_Portfolio sprint timeline: January–September 2026. Reported results retain their actual run dates._

The Azure-native version of [toronto-open-data-pipeline](https://github.com/prhoguns/toronto-open-data-pipeline):
**Data Factory → ADLS Gen2 → Databricks (PySpark, Delta, medallion) → Synapse serverless SQL or Microsoft Fabric → Power BI**,
deployed with Bicep or Terraform. Same source data, same gold star schema, same numbers.

| | |
|---|---|
| Infrastructure | [`infra/main.bicep`](infra/main.bicep) or [`infra/terraform/`](infra/terraform/): ADLS Gen2, Data Factory, Databricks + Unity Catalog access connector, Synapse (serverless), Key Vault, managed-identity RBAC |
| Orchestration | [`adf/`](adf/): pipeline, datasets, linked services, daily trigger, as ADF Git-integration JSON |
| Transformation | [`databricks/notebooks/`](databricks/notebooks/): bronze → silver → gold in PySpark, with data-quality asserts |
| Serving | [`synapse/sql/`](synapse/sql/): external data source + `gold.*` views over Delta, T-SQL sample queries · optional [Fabric Lakehouse](#microsoft-fabric-serving-layer) over the same files |
| Verification | [`tests/run_local.py`](tests/run_local.py): runs the notebooks on plain Spark in Docker against the real files |

Architecture and cost notes: [docs/architecture.md](docs/architecture.md)

## Verified without a subscription

The notebooks are ordinary Python. `tests/run_local.py` strips the Databricks magics and executes them on a
local Spark 4.0 runtime against the three real City of Toronto files:

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

CI checks both infrastructure versions on every push: `az bicep build` and `az bicep lint` for
Bicep; `terraform fmt`, `validate` and `test` (against a mocked Azure provider) plus Checkov for
Terraform.

## Bicep and Terraform

The platform is defined twice, resource for resource, so it can be deployed by a team that
standardises on either tool. Both create the same resources with the same names and the same
access model:

| | Bicep | Terraform |
|---|---|---|
| ADLS Gen2, 4 containers, TLS 1.2, no public access | ✓ | ✓ |
| Storage account keys and local users disabled; Entra ID + RBAC only | ✓ | ✓ |
| Data Factory, Synapse and Databricks reach the lake with managed identities | ✓ | ✓ |
| Unity Catalog access connector (Databricks' identity for the lake), Premium workspace | ✓ | ✓ |
| Synapse accepts Entra ID logins only; no SQL password | ✓ | ✓ |
| Key Vault with RBAC, soft delete and purge protection | ✓ | ✓ |
| Tests | build + lint | 8 plan/apply tests against mocked providers (3 for the optional Fabric layer) |

Porting to Terraform found three gaps in the original Bicep, now fixed in both:

- **The notebooks could not reach the lake.** They are written for Unity Catalog, but the
  workspace was on the Standard tier (Unity Catalog needs Premium) and there was no access
  connector, the managed identity Unity Catalog uses as its storage credential.
- **"No stored keys" was not quite true.** Storage account keys were still enabled, and Synapse
  had a SQL admin password passed in at deploy time. Keys are now disabled, and Synapse is
  Entra-ID-only, so neither exists.
- **Key Vault could be purged immediately after deletion.** Purge protection is now on.

The Terraform tests pin these properties (for example, a test fails if storage keys are turned
back on).

## Microsoft Fabric serving layer

Microsoft now positions Fabric as the successor to Synapse for analytics, and Synapse is no longer
getting new features. [`infra/terraform/fabric.tf`](infra/terraform/fabric.tf) adds a Fabric path
next to Synapse, switched on with `enable_fabric = true`:

- An **F2 Fabric capacity** (the smallest; pause it when idle, it bills while running) and a
  workspace with its own **workspace identity**.
- A **Lakehouse whose tables are OneLake shortcuts** to the four gold Delta folders. Nothing is copied
  or re-pipelined: Databricks keeps writing gold, and Synapse and Fabric read the same files.
- Lake access through the workspace identity with **Storage Blob Data Reader**, so the "no keys,
  managed identities only" rule still holds, and Fabric can read but not write.
- [`fabric/sql/01_views.sql`](fabric/sql/01_views.sql) recreates the `gold.*` views on the SQL
  analytics endpoint with the same names, so Power BI reports move by changing the connection, and
  Power BI can use **Direct Lake** instead of DirectQuery or Import.

Synapse stays in place so the two can run side by side and their row counts can be compared before
cutting over. Three Terraform tests cover it with a mocked Fabric provider: off by default, an
admin is required, and the shortcuts, identity and read-only role are wired as described.

## Deploy

```bash
az login
./infra/deploy.sh                        # Bicep, ~10 min; writes infra/outputs.json
# or
terraform -chdir=infra/terraform init && terraform -chdir=infra/terraform apply
./scripts/publish_adf.sh                 # pushes adf/ definitions to the factory
```

Then, once:

1. Databricks: Repos → add this repository; the pipeline references `/Repos/toronto/databricks/notebooks/...`.
2. Synapse Studio → SQL script: run `synapse/sql/01_setup.sql` (fill in the storage account name) then `02_views.sql`.
3. ADF Studio: author the `df_unpivot_profiles` data flow (Unpivot transformation; see `adf/README.md`), publish, enable trigger `tr_daily_0600`.
4. Databricks: create a Unity Catalog storage credential from the access connector
   (`databricksAccessConnectorId` output) and an external location for the lake.
5. Power BI: connect to the Synapse serverless endpoint (`infra/outputs.json → synapseServerlessEndpoint`), database `toronto`, schema `gold`, signing in with Entra ID.
6. Fabric (if `enable_fabric = true`, Terraform only): run `fabric/sql/01_views.sql` on the Lakehouse SQL endpoint
   (`fabric_lakehouse_sql_endpoint` output), then point Power BI at it, or build a Direct Lake semantic model on the Lakehouse.

Tear down: `az group delete -n rg-toronto-data --yes` (Bicep) or `terraform -chdir=infra/terraform destroy`.

## Not done yet

- Private networking. Every service keeps a public endpoint, protected by Entra ID and RBAC
  rather than by the network. Private endpoints, a managed VNet for Synapse and VNet injection for
  Databricks are the next step, and account for most of the Checkov checks skipped with a reason
  in `infra/terraform/main.tf` (21 passed, 0 failed, 23 skipped). Customer-managed keys are the rest.
- Neither version has been deployed to a subscription yet; both are validated and tested offline.
  The Fabric layer is Terraform-only for now, and is likewise tested against a mocked provider, not a live tenant.

## Layout

```
infra/       main.bicep · main.bicepparam · deploy.sh · terraform/ (same platform + optional Fabric, with tests)
adf/         linkedService/ dataset/ pipeline/ trigger_daily.json
databricks/  notebooks/00_config · 01_bronze_to_silver · 01b_..._neighbourhoods · 02_silver_to_gold
synapse/     sql/01_setup · 02_views · 03_sample_queries
fabric/      sql/01_views (same gold.* views on the Lakehouse SQL endpoint)
tests/       run_local.py (Spark-in-Docker verification)
docs/        architecture.md
```

## Acknowledgments

AI tools assisted with documentation and repository organization.
