#!/usr/bin/env python3
"""
Synthetic Data Generator for GCS Billing Export & I/O Telemetry Showback.

Supports:
1. Standard Google Cloud Detailed Billing Export format:
   Table name: gcp_billing_export_resource_v1_<BILLING_ACCOUNT_ID> (with underscores).
2. Modes:
   - `telemetry-only`: Generate only client I/O telemetry rows (for environments with active GCP Cloud Billing export).
   - `all` (default): Generate both telemetry rows and mock detailed billing export rows (for sandbox/demo).
   - `billing-only`: Generate only mock detailed billing export rows.
3. Direct ingestion into BigQuery (`--load-bq`) or SQL script generation (`--output-sql`).
"""

import argparse
import datetime
import json
import math
import random
import sys
from typing import List, Dict, Any, Tuple

# Target GCS Buckets
BUCKETS = [
    "prod-lakehouse-analytics-us-central1",
    "prod-data-lake-raw-us-central1",
]

# Workload Engines and User Group Information (UGI) / Teams
WORKLOAD_TEMPLATES = [
    {
        "engine": "Spark",
        "app_prefix": "app-20260828-",
        "ugi": "data-engineering@company.internal",
        "paths": [
            "/data/warehouse/sales/year=2026/month=08",
            "/data/warehouse/inventory/snapshot_date=2026-08-28",
            "/data/warehouse/customers/v2",
        ],
        "read_bytes_range": (50_000_000_000, 500_000_000_000),  # 50 GB to 500 GB
        "write_bytes_range": (10_000_000_000, 100_000_000_000), # 10 GB to 100 GB
        "ops_range": (5_000, 50_000),
    },
    {
        "engine": "Presto",
        "app_prefix": "presto_q_",
        "ugi": "analytics-team@company.internal",
        "paths": [
            "/data/raw/user_events/dt=2026-08-28",
            "/data/raw/ad_clicks/dt=2026-08-28",
            "/data/warehouse/sales/year=2026/month=08",
        ],
        "read_bytes_range": (100_000_000_000, 800_000_000_000), # 100 GB to 800 GB
        "write_bytes_range": (1_000_000, 50_000_000),           # Small outputs
        "ops_range": (20_000, 200_000),
    },
    {
        "engine": "Ray",
        "app_prefix": "ray-train-job-",
        "ugi": "ml-team@company.internal",
        "paths": [
            "/data/ml/features/user_embeddings/v1",
            "/data/ml/checkpoints/model_v4",
        ],
        "read_bytes_range": (200_000_000_000, 1_200_000_000_000), # 200 GB to 1.2 TB
        "write_bytes_range": (20_000_000_000, 150_000_000_000),
        "ops_range": (10_000, 80_000),
    },
    {
        "engine": "Hive",
        "app_prefix": "hive_job_",
        "ugi": "bi-reporting@company.internal",
        "paths": [
            "/data/warehouse/financial_reports/2026_q3",
        ],
        "read_bytes_range": (20_000_000_000, 150_000_000_000),
        "write_bytes_range": (5_000_000_000, 30_000_000_000),
        "ops_range": (2_000, 15_000),
    },
]

# GCP GCS SKU Configurations
GCS_SKUS = [
    {
        "id": "6C80-5C9B-0536",
        "description": "Standard Storage",
        "unit": "gibibyte month",
        "rate": 0.020 / (30 * 24), # $0.02 per GB/month broken down to hourly rate
        "is_op": False,
    },
    {
        "id": "A120-BD32-1100",
        "description": "Class A Operations",
        "unit": "requests",
        "rate": 0.05 / 10000, # $0.05 per 10,000 requests
        "is_op": True,
    },
    {
        "id": "B982-9901-44A1",
        "description": "Class B Operations",
        "unit": "requests",
        "rate": 0.004 / 10000, # $0.004 per 10,000 requests
        "is_op": True,
    },
    {
        "id": "C091-E210-9981",
        "description": "Network Inter-Region Egress",
        "unit": "gibibyte",
        "rate": 0.01, # $0.01 per GB
        "is_op": False,
    },
]

def format_billing_table_name(billing_account_id: str) -> str:
    """Format billing account ID to Google's standard BigQuery billing export table name."""
    clean_id = billing_account_id.replace("-", "_")
    return f"gcp_billing_export_resource_v1_{clean_id}"

def generate_data(
    days: int = 14,
    project_id: str = "my-gcp-project-id",
    billing_account_id: str = "01A2B3-C4D5E6-F78901",
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Generates synthetic hourly telemetry events and correlated mock GCP billing records."""
    start_time = datetime.datetime.now(datetime.timezone.utc).replace(minute=0, second=0, microsecond=0) - datetime.timedelta(days=days)
    hours_count = days * 24

    billing_rows: List[Dict[str, Any]] = []
    telemetry_rows: List[Dict[str, Any]] = []

    print(f"Generating synthetic data for {days} days ({hours_count} hours)...")

    for h in range(hours_count):
        billing_hour = start_time + datetime.timedelta(hours=h)
        usage_end_time = billing_hour + datetime.timedelta(hours=1)
        timestamp_str = billing_hour.strftime("%Y-%m-%d %H:%M:%S+00")

        # For each bucket, simulate active workloads and billing SKU records
        for bucket in BUCKETS:
            bucket_total_bytes = 0
            bucket_total_ops = 0

            active_workloads = random.sample(WORKLOAD_TEMPLATES, random.randint(2, 4))
            for i, wl in enumerate(active_workloads):
                app_id = f"{wl['app_prefix']}{(h % 100):03d}_{i+1}"
                parent_dir = random.choice(wl["paths"])
                read_bytes = random.randint(*wl["read_bytes_range"])
                write_bytes = random.randint(*wl["write_bytes_range"])
                total_bytes = read_bytes + write_bytes
                ops_count = random.randint(*wl["ops_range"])

                bucket_total_bytes += total_bytes
                bucket_total_ops += ops_count

                telemetry_rows.append({
                    "application_id": app_id,
                    "engine": wl["engine"],
                    "ugi": wl["ugi"],
                    "parent_directory": parent_dir,
                    "operation_type": "READ" if read_bytes > write_bytes else "WRITE",
                    "bytes_transferred": total_bytes,
                    "operation_count": ops_count,
                    "source_zone": "us-central1-a",
                    "destination_bucket": bucket,
                    "event_timestamp": timestamp_str,
                })

            # Calculate billing SKU costs based on aggregate volume
            for sku in GCS_SKUS:
                if sku["is_op"]:
                    if "Class A" in sku["description"]:
                        usage_amount = float(bucket_total_ops * 0.3)
                    else:
                        usage_amount = float(bucket_total_ops * 0.7)
                    cost = round(usage_amount * sku["rate"], 4)
                elif "Storage" in sku["description"]:
                    usage_amount = float(bucket_total_bytes / (1024**3))
                    cost = round(usage_amount * sku["rate"], 4)
                else: # Inter-Region Egress
                    usage_amount = float((bucket_total_bytes * 0.25) / (1024**3))
                    cost = round(usage_amount * sku["rate"], 4)

                billing_rows.append({
                    "billing_account_id": billing_account_id,
                    "service": {"id": "95A4-CED9-C0B2", "description": "Google Cloud Storage"},
                    "sku": {"id": sku["id"], "description": sku["description"]},
                    "usage_start_time": timestamp_str,
                    "usage_end_time": usage_end_time.strftime("%Y-%m-%d %H:%M:%S+00"),
                    "project": {
                        "id": project_id,
                        "number": "123456789012",
                        "name": project_id,
                        "labels": [{"key": "environment", "value": "production"}]
                    },
                    "labels": [{"key": "managed_by", "value": "terraform"}],
                    "system_labels": [],
                    "location": {"location": "us-central1", "country": "US", "region": "us-central1", "zone": "us-central1-a"},
                    "export_time": timestamp_str,
                    "cost": cost,
                    "currency": "USD",
                    "currency_conversion_rate": 1.0,
                    "usage": {
                        "amount": round(usage_amount, 2),
                        "unit": sku["unit"],
                        "amount_in_pricing_units": round(usage_amount, 2),
                        "pricing_unit": sku["unit"]
                    },
                    "credits": [],
                    "invoice": {"month": billing_hour.strftime("%Y%m")},
                    "cost_type": "regular",
                    "cost_at_list": cost,
                    "resource": {"name": bucket, "global_name": f"//storage.googleapis.com/{bucket}", "id": bucket},
                    "tags": []
                })

    return billing_rows, telemetry_rows

def write_sql_script(
    telemetry_rows: List[Dict],
    billing_rows: List[Dict],
    output_file: str,
    project_id: str,
    billing_ds: str,
    obs_ds: str,
    billing_account_id: str,
    mode: str = "all",
    max_chunk_size: int = 750_000
) -> List[str]:
    """Writes formatted SQL insert script, splitting into parts if exceeding BigQuery query size limits."""
    import os
    billing_table_name = format_billing_table_name(billing_account_id)
    statements = []

    # 1. Telemetry Data
    if mode in ("all", "telemetry-only"):
        batch_size = 50
        for i in range(0, len(telemetry_rows), batch_size):
            batch = telemetry_rows[i:i+batch_size]
            val_strings = [
                f"('{r['application_id']}', '{r['engine']}', '{r['ugi']}', '{r['parent_directory']}', '{r['operation_type']}', {r['bytes_transferred']}, {r['operation_count']}, '{r['source_zone']}', '{r['destination_bucket']}', TIMESTAMP('{r['event_timestamp']}'))"
                for r in batch
            ]
            stmt = (
                f"INSERT INTO `{project_id}.{obs_ds}.client_io_aggregated_events` "
                f"(application_id, engine, ugi, parent_directory, operation_type, bytes_transferred, operation_count, source_zone, destination_bucket, event_timestamp)\n"
                f"VALUES\n" + ",\n".join(val_strings) + ";"
            )
            statements.append(stmt)

    # 2. Mock Billing Export Table DDL & Data (Sandbox / Simulation Mode)
    if mode in ("all", "billing-only"):
        ddl = f"""CREATE TABLE IF NOT EXISTS `{project_id}.{billing_ds}.{billing_table_name}` (
  billing_account_id STRING,
  service STRUCT<id STRING, description STRING>,
  sku STRUCT<id STRING, description STRING>,
  usage_start_time TIMESTAMP,
  usage_end_time TIMESTAMP,
  project STRUCT<id STRING, number STRING, name STRING, labels ARRAY<STRUCT<key STRING, value STRING>>>,
  labels ARRAY<STRUCT<key STRING, value STRING>>,
  system_labels ARRAY<STRUCT<key STRING, value STRING>>,
  location STRUCT<location STRING, country STRING, region STRING, zone STRING>,
  export_time TIMESTAMP,
  cost NUMERIC,
  currency STRING,
  currency_conversion_rate FLOAT64,
  usage STRUCT<amount FLOAT64, unit STRING, amount_in_pricing_units FLOAT64, pricing_unit STRING>,
  credits ARRAY<STRUCT<name STRING, amount FLOAT64, full_name STRING, id STRING, type STRING>>,
  invoice STRUCT<month STRING>,
  cost_type STRING,
  cost_at_list NUMERIC,
  resource STRUCT<name STRING, global_name STRING, id STRING>,
  tags ARRAY<STRUCT<key STRING, value STRING, inherited BOOL, namespace STRING>>
)
PARTITION BY DATE(usage_start_time);"""
        statements.append(ddl)

        batch_size = 50
        for i in range(0, len(billing_rows), batch_size):
            batch = billing_rows[i:i+batch_size]
            val_strings = []
            for r in batch:
                val_strings.append(
                    f"('{r['billing_account_id']}', "
                    f"STRUCT('{r['service']['id']}', '{r['service']['description']}'), "
                    f"STRUCT('{r['sku']['id']}', '{r['sku']['description']}'), "
                    f"TIMESTAMP('{r['usage_start_time']}'), TIMESTAMP('{r['usage_end_time']}'), "
                    f"STRUCT('{r['project']['id']}', '{r['project']['number']}', '{r['project']['name']}', ARRAY<STRUCT<key STRING, value STRING>>[]), "
                    f"ARRAY<STRUCT<key STRING, value STRING>>[], ARRAY<STRUCT<key STRING, value STRING>>[], "
                    f"STRUCT('{r['location']['location']}', '{r['location']['country']}', '{r['location']['region']}', '{r['location']['zone']}'), "
                    f"TIMESTAMP('{r['export_time']}'), {r['cost']}, '{r['currency']}', {r['currency_conversion_rate']}, "
                    f"STRUCT({r['usage']['amount']}, '{r['usage']['unit']}', {r['usage']['amount_in_pricing_units']}, '{r['usage']['pricing_unit']}'), "
                    f"ARRAY<STRUCT<name STRING, amount FLOAT64, full_name STRING, id STRING, type STRING>>[], "
                    f"STRUCT('{r['invoice']['month']}'), '{r['cost_type']}', {r['cost_at_list']}, "
                    f"STRUCT('{r['resource']['name']}', '{r['resource']['global_name']}', '{r['resource']['id']}'), "
                    f"ARRAY<STRUCT<key STRING, value STRING, inherited BOOL, namespace STRING>>[])"
                )
            stmt = (
                f"INSERT INTO `{project_id}.{billing_ds}.{billing_table_name}` "
                f"(billing_account_id, service, sku, usage_start_time, usage_end_time, project, labels, system_labels, location, export_time, cost, currency, currency_conversion_rate, usage, credits, invoice, cost_type, cost_at_list, resource, tags)\n"
                f"VALUES\n" + ",\n".join(val_strings) + ";"
            )
            statements.append(stmt)

    # Partition statements into chunks that comply with BigQuery query size limit
    chunks = []
    current_chunk = []
    current_len = 0
    for stmt in statements:
        stmt_len = len(stmt) + 2
        if current_chunk and (current_len + stmt_len > max_chunk_size):
            chunks.append("\n\n".join(current_chunk) + "\n")
            current_chunk = [stmt]
            current_len = stmt_len
        else:
            current_chunk.append(stmt)
            current_len += stmt_len
    if current_chunk:
        chunks.append("\n\n".join(current_chunk) + "\n")

    base, ext = os.path.splitext(output_file)
    # Clean up any existing split parts or old oversized output
    import glob
    for old_part in glob.glob(f"{base}_part*{ext}"):
        try:
            os.remove(old_part)
        except OSError:
            pass

    generated_files = []
    if len(chunks) == 1:
        with open(output_file, "w") as f:
            f.write(
                f"-- ============================================================================\n"
                f"-- Synthetic Data Script for GCS Observability & Billing Showback\n"
                f"-- Mode: {mode} | Target Project: {project_id}\n"
                f"-- ============================================================================\n\n"
            )
            f.write(chunks[0])
        generated_files.append(output_file)
    else:
        if os.path.exists(output_file):
            try:
                os.remove(output_file)
            except OSError:
                pass
        for idx, chunk_sql in enumerate(chunks, start=1):
            part_path = f"{base}_part{idx}{ext}"
            with open(part_path, "w") as f:
                f.write(
                    f"-- ============================================================================\n"
                    f"-- Synthetic Data Script for GCS Observability & Billing Showback (Part {idx} of {len(chunks)})\n"
                    f"-- Mode: {mode} | Target Project: {project_id}\n"
                    f"-- Query Size: {len(chunk_sql)/1024:.1f} KB (BigQuery limit: 1024 KB)\n"
                    f"-- ============================================================================\n\n"
                )
                f.write(chunk_sql)
            generated_files.append(part_path)

    return generated_files


def main():
    import subprocess
    parser = argparse.ArgumentParser(description="Generate synthetic GCP GCS billing and telemetry data.")
    parser.add_argument("--days", type=int, default=14, help="Number of days of data to generate (default: 14)")
    parser.add_argument("--project-id", type=str, default="my-gcp-project-id", help="Target GCP Project ID")
    parser.add_argument("--billing-account-id", type=str, default="01A2B3-C4D5E6-F78901", help="GCP Billing Account ID")
    parser.add_argument("--billing-dataset", type=str, default="billing_export_sim", help="Billing export dataset ID")
    parser.add_argument("--obs-dataset", type=str, default="billing_observability_dataset", help="Observability dataset ID")
    parser.add_argument("--mode", choices=["all", "telemetry-only", "billing-only"], default="all", help="Data generation mode: 'telemetry-only' (for live GCP billing export), 'all' (sandbox), 'billing-only'")
    parser.add_argument("--output-sql", type=str, default="scripts/synthetic_data_inserts.sql", help="File path to save output SQL script")
    parser.add_argument("--max-chunk-kb", type=int, default=750, help="Maximum size per SQL part file in KB (default: 750, limit: 1024)")
    parser.add_argument("--execute-bq", action="store_true", help="Directly execute generated SQL files using the 'bq' CLI")
    parser.add_argument("--load-bq", action="store_true", help="Directly load data into BigQuery using python client (requires google-cloud-bigquery)")

    args = parser.parse_args()

    billing_rows, telemetry_rows = generate_data(
        days=args.days,
        project_id=args.project_id,
        billing_account_id=args.billing_account_id
    )

    generated_files = write_sql_script(
        telemetry_rows=telemetry_rows,
        billing_rows=billing_rows,
        output_file=args.output_sql,
        project_id=args.project_id,
        billing_ds=args.billing_dataset,
        obs_ds=args.obs_dataset,
        billing_account_id=args.billing_account_id,
        mode=args.mode,
        max_chunk_size=args.max_chunk_kb * 1024
    )

    if len(generated_files) == 1:
        print(f"Successfully generated {generated_files[0]}!")
    else:
        print(f"Successfully generated {len(generated_files)} SQL files (split to fit under BigQuery's 1024 KB limit):")
        for fpath in generated_files:
            print(f"  • {fpath}")

    if args.execute_bq:
        print(f"\nExecuting {len(generated_files)} file(s) in BigQuery via 'bq' CLI...")
        for fpath in generated_files:
            print(f"  ▶ Executing {fpath}...")
            with open(fpath, "r") as f_in:
                cmd = ["bq", "query", "--use_legacy_sql=false", "--label", "datacloud:ai-agent"]
                res = subprocess.run(cmd, stdin=f_in)
                if res.returncode != 0:
                    print(f"❌ Execution failed for {fpath}")
                    sys.exit(res.returncode)
        print("🎉 All synthetic data files loaded into BigQuery successfully!")
    else:
        print("\nNext step to load data into BigQuery:")
        if len(generated_files) > 1:
            print("  Run helper script: ./scripts/load_synthetic_data.sh")
            print("  Or run manually:")
            print("    for f in scripts/synthetic_data_inserts_part*.sql; do bq query --use_legacy_sql=false --label datacloud:ai-agent < \"$f\"; done")
        else:
            print(f"  bq query --use_legacy_sql=false --label datacloud:ai-agent < {generated_files[0]}")

    if args.load_bq:
        try:
            from google.cloud import bigquery
            print("Connecting to BigQuery client to upload data...")
            client = bigquery.Client(project=args.project_id)

            if args.mode in ("all", "telemetry-only"):
                telemetry_table_ref = f"{args.project_id}.{args.obs_dataset}.client_io_aggregated_events"
                errors1 = client.insert_rows_json(telemetry_table_ref, telemetry_rows)
                if errors1:
                    print(f"Errors inserting telemetry rows: {errors1}")
                else:
                    print(f"Successfully inserted {len(telemetry_rows)} telemetry rows into {telemetry_table_ref}")

            if args.mode in ("all", "billing-only"):
                billing_table_name = format_billing_table_name(args.billing_account_id)
                billing_table_ref = f"{args.project_id}.{args.billing_dataset}.{billing_table_name}"
                errors2 = client.insert_rows_json(billing_table_ref, billing_rows)
                if errors2:
                    print(f"Errors inserting billing rows: {errors2}")
                else:
                    print(f"Successfully inserted {len(billing_rows)} billing rows into {billing_table_ref}")
        except Exception as e:
            print(f"Could not insert directly into BigQuery Python SDK: {e}")

if __name__ == "__main__":
    main()
