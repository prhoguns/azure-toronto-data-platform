# Databricks notebook source
# MAGIC %md
# MAGIC # 01 · Bronze → Silver
# MAGIC Bronze holds the raw CSV exactly as Data Factory copied it from open.toronto.ca.
# MAGIC Silver is the typed, de-duplicated, partitioned version. No business logic yet.

# COMMAND ----------

# MAGIC %run ./00_config

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql import types as T

RUN_DATE = dbutils.widgets.get("run_date") if "dbutils" in dir() else os.getenv("RUN_DATE", "latest")  # noqa: F821

# COMMAND ----------

raw = (
    spark.read.option("header", True)  # noqa: F821
    .option("inferSchema", False)
    .csv(f"{BRONZE}/major_crime_indicators/{RUN_DATE}/*.csv")
)
print(f"bronze rows: {raw.count():,}")

# COMMAND ----------

silver = (
    raw.select(
        F.col("_id").cast(T.LongType()).alias("source_row_id"),
        F.trim("EVENT_UNIQUE_ID").alias("event_id"),
        F.to_date("REPORT_DATE").alias("report_date"),
        F.to_date("OCC_DATE").alias("occurrence_date"),
        F.col("OCC_YEAR").cast(T.IntegerType()).alias("occurrence_year"),
        F.col("OCC_HOUR").cast(T.IntegerType()).alias("occurrence_hour"),
        F.trim("OCC_DOW").alias("occurrence_dow"),
        F.trim("DIVISION").alias("police_division"),
        F.trim("LOCATION_TYPE").alias("location_type"),
        F.trim("PREMISES_TYPE").alias("premises_type"),
        F.trim("OFFENCE").alias("offence"),
        F.trim("MCI_CATEGORY").alias("mci_category"),
        F.when(F.col("HOOD_158").isin("NSA", ""), None).otherwise(F.col("HOOD_158").cast(T.IntegerType())).alias("neighbourhood_id"),
        F.trim("NEIGHBOURHOOD_158").alias("neighbourhood_name_raw"),
        F.col("LONG_WGS84").cast(T.DoubleType()).alias("longitude"),
        F.col("LAT_WGS84").cast(T.DoubleType()).alias("latitude"),
    )
    .dropDuplicates(["source_row_id"])
    .withColumn("_ingested_at", F.current_timestamp())
)

# COMMAND ----------

# Data quality gates - fail the job rather than write bad silver.
n = silver.count()
assert n > 0, "no rows"
assert silver.filter(F.col("event_id").isNull()).count() == 0, "null event_id"
assert silver.filter(F.col("occurrence_date").isNull()).count() == 0, "unparseable OCC_DATE"
bad_cat = silver.filter(~F.col("mci_category").isin("Assault", "Auto Theft", "Break and Enter", "Robbery", "Theft Over")).count()
assert bad_cat == 0, f"{bad_cat} rows with unexpected mci_category"
print(f"silver rows: {n:,} - quality gates passed")

# COMMAND ----------

write(silver, f"{SILVER}/crime_incidents", partition_by=["occurrence_year"])
