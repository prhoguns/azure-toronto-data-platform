# Local verification

The notebooks are plain Python, so they run on any Spark. This executes them against the real
City of Toronto files in a container, without an Azure subscription:

```bash
# inputs: the three files produced by the sister project's extract step
# (https://github.com/prhoguns/toronto-open-data-pipeline: data/raw/*.csv)
docker run --rm -v "$PWD":/app -v /path/to/raw:/raw -w /app apache/spark-py:v3.4.0 \
  /opt/spark/bin/spark-submit tests/run_local.py \
  /raw/major_crime_indicators_20260922.csv /raw/neighbourhoods_20260922.csv /raw/neighbourhood_profiles_20260922.csv
```

`TABLE_FORMAT=parquet` is used locally because the stock Spark image has no Delta jar; on
Databricks the same code writes Delta.
