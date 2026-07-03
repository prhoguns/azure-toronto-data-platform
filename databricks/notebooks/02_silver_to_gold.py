# Databricks notebook source
# MAGIC %md
# MAGIC # 02 · Silver → Gold
# MAGIC Gold is the star schema Synapse serverless and Power BI read: a date dimension, a neighbourhood dimension,
# MAGIC the incident fact (2014 onward) and a monthly aggregate with rate per 1,000 residents.

# COMMAND ----------

# MAGIC %run ./00_config

# COMMAND ----------

from pyspark.sql import functions as F

incidents = read(f"{SILVER}/crime_incidents")
neighbourhoods = read(f"{SILVER}/neighbourhoods")

# COMMAND ----------

# dim_date: generated, not loaded
dim_date = (
    spark.sql("select explode(sequence(to_date('2014-01-01'), add_months(trunc(current_date(), 'year'), 24), interval 1 day)) as date_day")  # noqa: F821
    .select(
        F.date_format("date_day", "yyyyMMdd").cast("int").alias("date_key"),
        "date_day",
        F.year("date_day").alias("year"),
        F.quarter("date_day").alias("quarter"),
        F.month("date_day").alias("month"),
        F.date_format("date_day", "MMM").alias("month_abbr"),
        F.trunc("date_day", "month").alias("month_start"),
        F.dayofweek("date_day").alias("day_of_week"),
        F.date_format("date_day", "EEE").alias("day_abbr"),
        F.dayofweek("date_day").isin(1, 7).alias("is_weekend"),
    )
)
write(dim_date, f"{GOLD}/dim_date")

# COMMAND ----------

dim_neighbourhood = neighbourhoods.select(
    "neighbourhood_id", "neighbourhood_name", "tsns_classification", "is_improvement_area", "population_2021", "median_income_2020"
)
write(dim_neighbourhood, f"{GOLD}/dim_neighbourhood")

# COMMAND ----------

fct = (
    incidents.filter(F.col("occurrence_date") >= F.lit("2014-01-01"))
    .select(
        F.col("source_row_id").alias("crime_incident_key"),
        "event_id",
        F.date_format("occurrence_date", "yyyyMMdd").cast("int").alias("occurrence_date_key"),
        "occurrence_date",
        "occurrence_hour",
        F.date_format("report_date", "yyyyMMdd").cast("int").alias("report_date_key"),
        "report_date",
        F.datediff("report_date", "occurrence_date").alias("days_to_report"),
        "neighbourhood_id",
        "police_division",
        "mci_category",
        "offence",
        "location_type",
        "premises_type",
        "longitude",
        "latitude",
        "occurrence_year",
    )
)
write(fct, f"{GOLD}/fct_crime_incidents", partition_by=["occurrence_year"])

# COMMAND ----------

agg = (
    fct.filter(F.col("neighbourhood_id").isNotNull())
    .groupBy(F.trunc("occurrence_date", "month").alias("month_start"), "neighbourhood_id", "mci_category")
    .agg(F.count("*").alias("incidents"))
    .join(dim_neighbourhood, "neighbourhood_id")
    .withColumn("incidents_per_1000", F.round(F.col("incidents") * 1000.0 / F.col("population_2021"), 3))
    .select("month_start", "neighbourhood_id", "neighbourhood_name", "is_improvement_area", "mci_category", "incidents", "population_2021", "incidents_per_1000")
)
write(agg, f"{GOLD}/agg_crime_monthly_neighbourhood")

print(f"gold: dim_date={dim_date.count():,} dim_neighbourhood={dim_neighbourhood.count():,} fct={fct.count():,} agg={agg.count():,}")
