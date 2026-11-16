"""
Prepare invoice-level data from the two Online Retail II CSV files.

Input : online_retail_II_2009_2010.csv and online_retail_II_2010_2011.csv
        (semicolon separated, dates like 1.12.2010 08:26)
Output: data/invoices.csv  (one row per invoice)

Usage : python prep/prepare_invoices.py <folder_with_raw_csvs> <output_csv>
"""
import sys
import pandas as pd

raw_dir, out_path = sys.argv[1], sys.argv[2]

def read(name):
    return pd.read_csv(f"{raw_dir}/{name}", sep=";", encoding="utf-8-sig", dtype=str)

first = read("online_retail_II_2009_2010.csv")
second = read("online_retail_II_2010_2011.csv")
print(f"rows read: {len(first):,} + {len(second):,}")

# 1. The two files share invoices from 1 to 9 December 2010 (identical rows).
#    Keep them once.
overlap = set(first.Invoice) & set(second.Invoice)
df = pd.concat([first, second[~second.Invoice.isin(overlap)]], ignore_index=True)
print(f"after removing {len(overlap):,} duplicated invoices: {len(df):,} rows")

df["quantity"] = pd.to_numeric(df["Quantity"])
df["price"] = pd.to_numeric(df["Price"])
df["invoice_date"] = pd.to_datetime(df["InvoiceDate"], format="%d.%m.%Y %H:%M")
df["customer_id"] = df["Customer ID"]

# 2. RFM needs a customer, so rows without Customer ID are dropped.
n = len(df)
df = df[df.customer_id.notna()]
print(f"dropped rows without Customer ID: {n - len(df):,}")

# 3. Keep real products only: product stock codes start with 5 digits.
#    Drops POST, M, D, C2, ADJUST, BANK CHARGES, DOT, CRUK, TEST and similar.
n = len(df)
df = df[df.StockCode.str.match(r"^\d{5}")]
print(f"dropped non-product lines: {n - len(df):,}")

# 4. Drop zero or negative prices.
n = len(df)
df = df[df.price > 0]
print(f"dropped zero-price lines: {n - len(df):,}")

df["line_value"] = df.quantity * df.price
df["is_return"] = df.Invoice.str.startswith("C").astype(int)

# 5. One row per invoice. A few invoices span a minute or two, so take the
#    earliest time. A few customers appear under two countries, so take the
#    country of their most recent invoice.
inv = (df.groupby("Invoice")
         .agg(customer_id=("customer_id", "first"),
              invoice_date=("invoice_date", "min"),
              country=("Country", "first"),
              line_count=("StockCode", "size"),
              units=("quantity", "sum"),
              invoice_value=("line_value", "sum"),
              is_return=("is_return", "first"))
         .reset_index()
         .rename(columns={"Invoice": "invoice_no"}))

latest_country = (inv.sort_values("invoice_date")
                     .groupby("customer_id").country.last())
inv["country"] = inv.customer_id.map(latest_country)

inv["customer_id"] = inv.customer_id.astype(int)
inv["invoice_value"] = inv.invoice_value.round(2)
inv = inv.sort_values(["invoice_date", "invoice_no"])
inv["invoice_date"] = inv.invoice_date.dt.strftime("%Y-%m-%d %H:%M:%S")
inv.to_csv(out_path, index=False)

sales = inv[inv.is_return == 0]
print(f"invoices: {len(inv):,} ({len(sales):,} sales, {int(inv.is_return.sum()):,} returns)")
print(f"customers with a sale: {sales.customer_id.nunique():,}")
print(f"sales revenue: {sales.invoice_value.sum():,.2f}")
