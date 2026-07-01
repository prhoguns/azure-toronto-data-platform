# Databricks notebook source
# MAGIC %md
# MAGIC # 01b · Bronze → Silver: neighbourhoods
# MAGIC Boundaries CSV joined to the 2021 census profile (already unpivoted to long format by Data Factory's
# MAGIC Excel-to-CSV copy, one row per neighbourhood per metric).

# COMMAND ----------

# MAGIC %run ./00_config

# COMMAND ----------

from pyspark.sql import functions as F

RUN_DATE = dbutils.widgets.get("run_date") if "dbutils" in dir() else os.getenv("RUN_DATE", "latest")  # noqa: F821

bounds = spark.read.option("header", True).csv(f"{BRONZE}/neighbourhoods/{RUN_DATE}/*.csv")  # noqa: F821
profiles = spark.read.option("header", True).csv(f"{BRONZE}/neighbourhood_profiles/{RUN_DATE}/*.csv")  # noqa: F821

# COMMAND ----------

METRICS = {
    "Total - Age groups of the population - 25% sample data": "population_2021",
    "Median total income in 2020 ($)": "median_income_2020",
}
pivoted = (
    profiles.filter(F.col("metric").isin(list(METRICS)))
    .withColumn("metric", F.col("metric"))
    .groupBy(F.col("neighbourhood_number").cast("int").alias("neighbourhood_id"))
    .pivot("metric", list(METRICS))
    .agg(F.first("value"))
)
for src, dst in METRICS.items():
    pivoted = pivoted.withColumnRenamed(src, dst).withColumn(dst, F.col(dst).cast("double").cast("int"))

silver = bounds.select(
    F.col("AREA_SHORT_CODE").cast("int").alias("neighbourhood_id"),
    F.trim("AREA_NAME").alias("neighbourhood_name"),
    F.trim("CLASSIFICATION").alias("tsns_classification"),
    F.col("CLASSIFICATION").startswith("Neighbourhood Improvement").alias("is_improvement_area"),
).join(pivoted, "neighbourhood_id", "left")

assert silver.count() == 158, f"expected 158 neighbourhoods, got {silver.count()}"
assert silver.filter(F.col("population_2021").isNull()).count() == 0, "neighbourhood without population"
write(silver, f"{SILVER}/neighbourhoods")
print("silver neighbourhoods: 158 rows")
