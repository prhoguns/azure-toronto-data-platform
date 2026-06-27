using './main.bicep'

param prefix = 'tordata'
param adminObjectId = readEnvironmentVariable('AZ_ADMIN_OBJECT_ID')
param synapseSqlPassword = readEnvironmentVariable('SYNAPSE_SQL_PASSWORD')
