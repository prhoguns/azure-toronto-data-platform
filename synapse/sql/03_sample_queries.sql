-- T-SQL versions of the questions in https://github.com/prhoguns/toronto-crime-sql-analytics, for the serverless endpoint.
USE toronto;
GO

-- Yearly trend per category
SELECT d.[year], f.mci_category, COUNT(*) AS incidents
FROM gold.fct_crime_incidents f
JOIN gold.dim_date d ON d.date_key = f.occurrence_date_key
GROUP BY d.[year], f.mci_category
ORDER BY d.[year], f.mci_category;

-- Top 10 neighbourhoods by 2024 rate per 1,000 residents
SELECT TOP 10 neighbourhood_name, population_2021, SUM(incidents) AS incidents_2024,
       ROUND(SUM(incidents) * 1000.0 / population_2021, 1) AS per_1000
FROM gold.agg_crime_monthly_neighbourhood
WHERE month_start >= '2024-01-01' AND month_start < '2025-01-01'
GROUP BY neighbourhood_name, population_2021
ORDER BY per_1000 DESC;

-- Trailing 12-month auto theft
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(occurrence_date), MONTH(occurrence_date), 1) AS month_start, COUNT(*) AS auto_thefts
    FROM gold.fct_crime_incidents
    WHERE mci_category = 'Auto Theft'
    GROUP BY DATEFROMPARTS(YEAR(occurrence_date), MONTH(occurrence_date), 1)
)
SELECT month_start, auto_thefts,
       AVG(auto_thefts) OVER (ORDER BY month_start ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS trailing_12m_avg
FROM monthly
ORDER BY month_start;
