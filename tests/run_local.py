"""Run the Databricks notebooks on a local Spark, end to end, against real files.

Usage (see tests/README.md for the Docker one-liner):
    python tests/run_local.py <crime.csv> <neighbourhoods.csv> <neighbourhood_profiles_long.csv>

It lays the inputs out in a temporary bronze/ folder the way Data Factory would
(<table>/<run_date>/<file>.csv), points the notebooks at local silver/ and gold/ folders in
parquet format, and executes 01b, 01, 02 in order with a SparkSession injected as `spark`.
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
from pathlib import Path

from pyspark.sql import SparkSession

NOTEBOOKS = Path(__file__).resolve().parents[1] / "databricks" / "notebooks"
ORDER = ["01b_bronze_to_silver_neighbourhoods.py", "01_bronze_to_silver.py", "02_silver_to_gold.py"]


def notebook_source(name: str) -> str:
    """Databricks notebooks are plain .py with '# MAGIC' and '# COMMAND' comment lines; strip them and inline 00_config."""
    lines = []
    for line in (NOTEBOOKS / name).read_text().splitlines():
        if line.startswith("# MAGIC %run"):
            lines.append((NOTEBOOKS / "00_config.py").read_text())
        elif line.startswith(("# MAGIC", "# COMMAND", "# Databricks notebook source")):
            continue
        else:
            lines.append(line)
    return "\n".join(lines)


def main(crime_csv: str, hoods_csv: str, profiles_csv: str) -> None:
    lake = Path(tempfile.mkdtemp(prefix="lake_"))
    run_date = "2026-09-22"
    for table, src in (("major_crime_indicators", crime_csv), ("neighbourhoods", hoods_csv), ("neighbourhood_profiles", profiles_csv)):
        dest = lake / "bronze" / table / run_date
        dest.mkdir(parents=True)
        shutil.copy(src, dest / Path(src).name)

    os.environ.update(
        {
            "BRONZE_ROOT": str(lake / "bronze"),
            "SILVER_ROOT": str(lake / "silver"),
            "GOLD_ROOT": str(lake / "gold"),
            "TABLE_FORMAT": "parquet",
            "RUN_DATE": run_date,
        }
    )
    spark = SparkSession.builder.master("local[*]").appName("toronto-local-test").config("spark.sql.shuffle.partitions", "8").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")

    for nb in ORDER:
        print(f"\n=== {nb}")
        exec(compile(notebook_source(nb), nb, "exec"), {"spark": spark, "os": os, "__name__": "__notebook__"})

    print("\n=== gold sample: top 5 neighbourhoods by 2024 incidents per 1,000")
    (
        spark.read.parquet(str(lake / "gold" / "agg_crime_monthly_neighbourhood"))
        .filter("month_start >= '2024-01-01' and month_start < '2025-01-01'")
        .groupBy("neighbourhood_name", "population_2021")
        .sum("incidents")
        .withColumnRenamed("sum(incidents)", "incidents_2024")
        .selectExpr("neighbourhood_name", "population_2021", "incidents_2024", "round(incidents_2024 * 1000.0 / population_2021, 1) as per_1000")
        .orderBy("per_1000", ascending=False)
        .show(5, truncate=False)
    )
    print(f"lake written to {lake}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
