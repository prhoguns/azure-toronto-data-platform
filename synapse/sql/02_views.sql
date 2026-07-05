-- Views over the Delta tables Databricks writes. Power BI connects to these (DirectQuery or Import).
USE toronto;
GO

CREATE OR ALTER VIEW gold.dim_date AS
SELECT * FROM OPENROWSET(BULK 'dim_date/', DATA_SOURCE = 'gold', FORMAT = 'DELTA') AS r;
GO
CREATE OR ALTER VIEW gold.dim_neighbourhood AS
SELECT * FROM OPENROWSET(BULK 'dim_neighbourhood/', DATA_SOURCE = 'gold', FORMAT = 'DELTA') AS r;
GO
CREATE OR ALTER VIEW gold.fct_crime_incidents AS
SELECT * FROM OPENROWSET(BULK 'fct_crime_incidents/', DATA_SOURCE = 'gold', FORMAT = 'DELTA') AS r;
GO
CREATE OR ALTER VIEW gold.agg_crime_monthly_neighbourhood AS
SELECT * FROM OPENROWSET(BULK 'agg_crime_monthly_neighbourhood/', DATA_SOURCE = 'gold', FORMAT = 'DELTA') AS r;
GO

-- Called by the last Data Factory activity. Views over Delta pick up new data automatically;
-- the procedure exists so the pipeline has an explicit "refresh" step to extend (statistics, cache warm-up).
CREATE OR ALTER PROCEDURE gold.refresh_views AS
BEGIN
    SELECT 'dim_date' AS v, COUNT(*) AS n FROM gold.dim_date
    UNION ALL SELECT 'dim_neighbourhood', COUNT(*) FROM gold.dim_neighbourhood
    UNION ALL SELECT 'fct_crime_incidents', COUNT(*) FROM gold.fct_crime_incidents
    UNION ALL SELECT 'agg_crime_monthly_neighbourhood', COUNT(*) FROM gold.agg_crime_monthly_neighbourhood;
END;
GO
