-- Run on the Lakehouse SQL analytics endpoint (terraform output fabric_lakehouse_sql_endpoint).
-- The four shortcuts appear as dbo tables. These views give them the same gold.* names the
-- Synapse views use, so Power BI reports and the sample queries work unchanged on either engine.
-- No OPENROWSET or external data source: Fabric reads the shortcut's Delta log directly.

CREATE SCHEMA gold;
GO

CREATE OR ALTER VIEW gold.dim_date AS SELECT * FROM dbo.dim_date;
GO
CREATE OR ALTER VIEW gold.dim_neighbourhood AS SELECT * FROM dbo.dim_neighbourhood;
GO
CREATE OR ALTER VIEW gold.fct_crime_incidents AS SELECT * FROM dbo.fct_crime_incidents;
GO
CREATE OR ALTER VIEW gold.agg_crime_monthly_neighbourhood AS SELECT * FROM dbo.agg_crime_monthly_neighbourhood;
GO

-- Same row counts as Synapse's gold.refresh_views, as a migration check:
-- both engines read the same Delta files, so the numbers must match.
SELECT 'dim_date' AS v, COUNT(*) AS n FROM gold.dim_date
UNION ALL SELECT 'dim_neighbourhood', COUNT(*) FROM gold.dim_neighbourhood
UNION ALL SELECT 'fct_crime_incidents', COUNT(*) FROM gold.fct_crime_incidents
UNION ALL SELECT 'agg_crime_monthly_neighbourhood', COUNT(*) FROM gold.agg_crime_monthly_neighbourhood;
