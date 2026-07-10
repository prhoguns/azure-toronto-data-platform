# Data Factory assets

JSON definitions in the layout ADF's Git integration expects (`linkedService/`, `dataset/`, `pipeline/`).
Publish with `scripts/publish_adf.sh` or connect the factory to this repo in the ADF studio (Manage → Git configuration).

Pipeline `pl_toronto_open_data`:

```
CopyCrimeToBronze ──────────────────────────────► SilverCrime ──┐
CopyNeighbourhoodsToBronze ──────────────┐                      ├─► Gold ─► RefreshSynapseViews
CopyProfilesToBronze ─► UnpivotProfiles ─┴─► SilverNeighbourhoods┘
```

`df_unpivot_profiles` is a mapping data flow (Unpivot transformation: all neighbourhood columns → `neighbourhood_name`, `value`;
join to the "Neighbourhood Number" row). It is authored in the studio; the JSON export is checked in once created.
Until then, the sister project's Python unpivot (`toronto-open-data-pipeline/pipeline/extract.py`) produces the same long CSV.
