#!/usr/bin/env bash
# Push the ADF JSON definitions to the factory created by infra/deploy.sh.
set -euo pipefail
RG="${RG:-rg-toronto-data}"
ADF=$(jq -r .dataFactoryName.value infra/outputs.json)
for f in adf/linkedService/*.json; do az datafactory linked-service create -g "$RG" --factory-name "$ADF" --name "$(jq -r .name "$f")" --properties "$(jq .properties "$f")" -o none; done
for f in adf/dataset/*.json;       do az datafactory dataset create        -g "$RG" --factory-name "$ADF" --name "$(jq -r .name "$f")" --properties "$(jq .properties "$f")" -o none; done
for f in adf/pipeline/*.json;      do az datafactory pipeline create       -g "$RG" --factory-name "$ADF" --name "$(jq -r .name "$f")" --pipeline "$(jq .properties "$f")" -o none; done
az datafactory trigger create -g "$RG" --factory-name "$ADF" --name tr_daily_0600 --properties "$(jq .properties adf/trigger_daily.json)" -o none
echo "published to $ADF"
