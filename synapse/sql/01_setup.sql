-- Run once against the Synapse serverless SQL endpoint (master, then the new database).
-- Serverless has no storage of its own: everything below is metadata over the gold Delta tables in ADLS.

CREATE DATABASE toronto;
GO
USE toronto;
GO

-- Managed identity of the workspace was granted Storage Blob Data Contributor in infra/main.bicep.
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong password, stored in Key Vault>';
GO
CREATE DATABASE SCOPED CREDENTIAL lake_msi WITH IDENTITY = 'Managed Identity';
GO
CREATE EXTERNAL DATA SOURCE gold WITH (
    LOCATION = 'abfss://gold@<storageAccountName>.dfs.core.windows.net/',
    CREDENTIAL = lake_msi
);
GO
CREATE SCHEMA gold;
GO
