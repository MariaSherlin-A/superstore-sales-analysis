"""Run every query in kpi_queries.sql and save each result to outputs/<name>.csv.

Run from the project root:  python sql/run_queries.py
"""
import re
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "superstore.db"
OUT = ROOT / "outputs"
OUT.mkdir(exist_ok=True)

sql_text = (ROOT / "sql" / "kpi_queries.sql").read_text(encoding="utf-8")
blocks = re.split(r"^-- name: (\S+)\s*$", sql_text, flags=re.M)[1:]

pd.set_option("display.width", 160, "display.max_columns", 20)
with sqlite3.connect(DB) as con:
    for name, query in zip(blocks[::2], blocks[1::2]):
        result = pd.read_sql_query(query, con)
        result.to_csv(OUT / f"{name}.csv", index=False)
        print(f"\n=== {name} ({len(result)} rows) ===")
        print(result.to_string(index=False))
