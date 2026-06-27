#!/usr/bin/env bash
# One-shot deployment. Needs: az CLI logged in, AZ_ADMIN_OBJECT_ID and SYNAPSE_SQL_PASSWORD exported.
set -euo pipefail
RG="${RG:-rg-toronto-data}"
LOCATION="${LOCATION:-canadacentral}"

: "${AZ_ADMIN_OBJECT_ID:=$(az ad signed-in-user show --query id -o tsv)}"
: "${SYNAPSE_SQL_PASSWORD:?export SYNAPSE_SQL_PASSWORD first}"
export AZ_ADMIN_OBJECT_ID SYNAPSE_SQL_PASSWORD

az group create -n "$RG" -l "$LOCATION" -o none
az deployment group create -g "$RG" -f "$(dirname "$0")/main.bicep" -p "$(dirname "$0")/main.bicepparam" \
  --query properties.outputs -o json | tee "$(dirname "$0")/outputs.json"

echo
echo "Next: scripts/publish_adf.sh to push the pipeline, then import databricks/notebooks/ into the workspace."
