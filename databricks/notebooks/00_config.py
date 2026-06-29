# Databricks notebook source
# MAGIC %md
# MAGIC # Config
# MAGIC Shared paths and helpers. On Databricks, `LAKE` is the ADLS Gen2 account mounted via Unity Catalog
# MAGIC external location or `abfss://`. Locally (tests/), it is a folder on disk so the same notebooks run on plain Spark.

# COMMAND ----------

import os

LAKE = os.getenv("LAKE_ROOT", "abfss://bronze@tordata.dfs.core.windows.net").rstrip("/")
BRONZE = os.getenv("BRONZE_ROOT", LAKE)
SILVER = os.getenv("SILVER_ROOT", LAKE.replace("bronze@", "silver@"))
GOLD = os.getenv("GOLD_ROOT", LAKE.replace("bronze@", "gold@"))

# Delta on Databricks; parquet when running on a bare Spark without the Delta jar (local tests).
TABLE_FORMAT = os.getenv("TABLE_FORMAT", "delta")


def write(df, path: str, partition_by: list[str] | None = None, mode: str = "overwrite") -> None:
    w = df.write.format(TABLE_FORMAT).mode(mode)
    if partition_by:
        w = w.partitionBy(*partition_by)
    if TABLE_FORMAT == "delta":
        w = w.option("overwriteSchema", "true")
    w.save(path)


def read(path: str):
    return spark.read.format(TABLE_FORMAT).load(path)  # noqa: F821 - `spark` is injected by Databricks / tests
