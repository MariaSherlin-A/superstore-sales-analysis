"""Load the cleaned Superstore data into SQLite as a small star schema.

Tables
  dim_customer (customer_id PK, customer_name, segment)
  dim_product  (product_id PK, product_name, category, sub_category)
  fact_sales   (one row per order line, with foreign keys to both dimensions)

Run from the project root:  python sql/load_to_sqlite.py
"""
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / "data" / "processed" / "superstore_clean.csv"
DB = ROOT / "data" / "superstore.db"

df = pd.read_csv(CSV, dtype={"postal_code": str})

dim_customer = (df[["customer_id", "customer_name", "segment"]]
                .drop_duplicates("customer_id"))
# A few product IDs appear with two slightly different names in the source;
# keep the first name seen so product_id stays a unique key.
dim_product = (df[["product_id", "product_name", "category", "sub_category"]]
               .drop_duplicates("product_id"))
fact_sales = df[["row_id", "order_id", "order_date", "ship_date", "ship_mode", "ship_days",
                 "customer_id", "product_id", "country", "region", "state", "city", "postal_code",
                 "sales", "quantity", "discount", "profit"]]

DB.unlink(missing_ok=True)
with sqlite3.connect(DB) as con:
    con.executescript("""
    CREATE TABLE dim_customer (
        customer_id   TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        segment       TEXT NOT NULL
    );
    CREATE TABLE dim_product (
        product_id   TEXT PRIMARY KEY,
        product_name TEXT NOT NULL,
        category     TEXT NOT NULL,
        sub_category TEXT NOT NULL
    );
    CREATE TABLE fact_sales (
        row_id      INTEGER PRIMARY KEY,
        order_id    TEXT NOT NULL,
        order_date  TEXT NOT NULL,   -- ISO yyyy-mm-dd
        ship_date   TEXT NOT NULL,
        ship_mode   TEXT,
        ship_days   INTEGER,
        customer_id TEXT REFERENCES dim_customer(customer_id),
        product_id  TEXT REFERENCES dim_product(product_id),
        country TEXT, region TEXT, state TEXT, city TEXT, postal_code TEXT,
        sales    REAL NOT NULL,
        quantity INTEGER NOT NULL,
        discount REAL NOT NULL,
        profit   REAL NOT NULL
    );
    CREATE INDEX ix_sales_date ON fact_sales(order_date);
    """)
    dim_customer.to_sql("dim_customer", con, if_exists="append", index=False)
    dim_product.to_sql("dim_product", con, if_exists="append", index=False)
    fact_sales.to_sql("fact_sales", con, if_exists="append", index=False)
    for t in ["dim_customer", "dim_product", "fact_sales"]:
        print(f"{t:<13} {con.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]:>6,} rows")
print(f"Database written to {DB.relative_to(ROOT)}")
