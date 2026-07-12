"""Download the 2021 census profile workbook and unpivot it to long CSV (what the ADF data flow produces in Azure)."""
import csv
import io
import sys
import urllib.request

import openpyxl

URL = "https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/6e19a90f-971c-46b3-852c-0c48c436d1fc/resource/19d4a806-7385-4889-acf2-256f1e079060/download/nbhd_2021_census_profile_full_158model.xlsx"

wb = openpyxl.load_workbook(io.BytesIO(urllib.request.urlopen(URL).read()), read_only=True)
ws = wb["hd2021_census_profile"]
rows = ws.iter_rows(values_only=True)
names, numbers = next(rows)[1:], next(rows)[1:]
with open(sys.argv[1], "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["neighbourhood_number", "neighbourhood_name", "metric", "value"])
    for row in rows:
        if row[0] is None:
            continue
        for num, name, val in zip(numbers, names, row[1:]):
            if num is not None:
                w.writerow([num, name, str(row[0]).strip(), val])
print("wrote", sys.argv[1])
