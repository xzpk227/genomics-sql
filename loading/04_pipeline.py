"""
============================================================
 Full bioinformatics pipeline: VCF → S3 → Redshift
 
 This is what a bioinformatician would actually write to
 automate the entire loading process end-to-end.
 
 Install:  pip install boto3 redshift-connector pandas
============================================================
"""

import os
import gzip
import boto3
import redshift_connector
import pandas as pd
from datetime import date
from pathlib import Path


# ── Config ───────────────────────────────────────────────────
S3_BUCKET   = "my-genomics-bucket"
S3_PREFIX   = f"data/brca_cohort/{date.today()}"
IAM_ROLE    = "arn:aws:iam::123456789012:role/RedshiftS3ReadRole"
REGION      = "us-east-1"

REDSHIFT_HOST = "my-cluster.abc123.us-east-1.redshift.amazonaws.com"
REDSHIFT_DB   = "genomics_db"
REDSHIFT_USER = os.environ["REDSHIFT_USER"]      # never hardcode credentials
REDSHIFT_PASS = os.environ["REDSHIFT_PASSWORD"]
REDSHIFT_PORT = 5439


# ── Step 1: Parse a simple VCF into a DataFrame ──────────────
def parse_vcf(vcf_path: str) -> pd.DataFrame:
    """
    Read a VCF file and return a flat DataFrame.
    Skips header lines starting with ##.
    """
    rows = []
    opener = gzip.open if vcf_path.endswith(".gz") else open

    with opener(vcf_path, "rt") as fh:
        for line in fh:
            if line.startswith("##"):
                continue                          # skip meta-info lines
            if line.startswith("#CHROM"):
                headers = line.lstrip("#").strip().split("\t")
                continue
            fields = line.strip().split("\t")
            row = dict(zip(headers, fields))

            # Parse INFO field into a dict
            info = {}
            for item in row.get("INFO", "").split(";"):
                if "=" in item:
                    k, v = item.split("=", 1)
                    info[k] = v

            rows.append({
                "chromosome":   row["CHROM"],
                "position":     int(row["POS"]),
                "variant_id":   row["ID"] if row["ID"] != "." else None,
                "ref_allele":   row["REF"],
                "alt_allele":   row["ALT"],
                "variant_type": "SNV" if len(row["REF"]) == len(row["ALT"]) else
                                "insertion" if len(row["ALT"]) > len(row["REF"]) else
                                "deletion",
                "af_global":    float(info["AF"]) if "AF" in info else None,
                "significance": info.get("CLNSIG", None),   # ClinVar field
            })

    df = pd.DataFrame(rows)
    print(f"Parsed {len(df):,} variants from {vcf_path}")
    return df


# ── Step 2: Upload TSV to S3 ─────────────────────────────────
def upload_to_s3(df: pd.DataFrame, table_name: str) -> str:
    """
    Write DataFrame to gzipped TSV and upload to S3.
    Returns the S3 URI.
    """
    local_path = Path(f"/tmp/{table_name}.tsv.gz")

    # Write gzipped TSV (Redshift COPY handles this natively)
    df.to_csv(local_path, sep="\t", index=False, compression="gzip")
    print(f"Written {local_path} ({local_path.stat().st_size / 1024:.1f} KB)")

    s3_key = f"{S3_PREFIX}/{table_name}.tsv.gz"
    s3 = boto3.client("s3", region_name=REGION)
    s3.upload_file(
        str(local_path),
        S3_BUCKET,
        s3_key,
        ExtraArgs={"ServerSideEncryption": "AES256"}   # encrypt at rest
    )

    s3_uri = f"s3://{S3_BUCKET}/{s3_key}"
    print(f"Uploaded to {s3_uri}")
    return s3_uri


# ── Step 3: Load from S3 into Redshift ───────────────────────
def redshift_copy(cursor, table: str, s3_uri: str, columns: list[str]):
    """
    Run a COPY command to load data from S3 into Redshift.
    Uses a staging table to avoid duplicates on re-runs.
    """
    staging = f"{table}_staging"
    col_list = ", ".join(columns)

    # Load into staging first
    copy_sql = f"""
        COPY genomics.{staging} ({col_list})
        FROM '{s3_uri}'
        IAM_ROLE '{IAM_ROLE}'
        FORMAT AS CSV
        DELIMITER '\\t'
        IGNOREHEADER 1
        GZIP
        NULL AS ''
        MAXERROR 100
        REGION '{REGION}';
    """
    print(f"Running COPY into {staging}...")
    cursor.execute(copy_sql)

    # Upsert: delete existing rows, insert new ones
    cursor.execute(f"""
        DELETE FROM genomics.{table}
        WHERE variant_id IN (SELECT variant_id FROM genomics.{staging});
    """)
    cursor.execute(f"INSERT INTO genomics.{table} SELECT * FROM genomics.{staging};")
    cursor.execute(f"TRUNCATE genomics.{staging};")

    # Check for load errors
    cursor.execute("""
        SELECT filename, line_number, colname, err_reason
        FROM stl_load_errors
        ORDER BY starttime DESC
        LIMIT 5;
    """)
    errors = cursor.fetchall()
    if errors:
        print("⚠ Load errors detected:")
        for e in errors:
            print(f"  {e}")
    else:
        print(f"✓ {table} loaded successfully")


# ── Step 4: Validate the load ────────────────────────────────
def validate_load(cursor):
    """
    Quick sanity checks after loading.
    A bioinformatician would check:
      - row counts are reasonable
      - no unexpected NULLs in key columns
      - allele frequencies are in [0, 1]
    """
    checks = {
        "total variants":
            "SELECT COUNT(*) FROM genomics.variants",
        "variants missing gene_id":
            "SELECT COUNT(*) FROM genomics.variants WHERE gene_id IS NULL",
        "invalid allele frequency (>1)":
            "SELECT COUNT(*) FROM genomics.variants WHERE af_global > 1",
        "pathogenic variant count":
            "SELECT COUNT(*) FROM genomics.variants WHERE significance = 'Pathogenic'",
        "variants per chromosome":
            "SELECT chromosome, COUNT(*) FROM genomics.variants GROUP BY chromosome ORDER BY 2 DESC",
    }

    print("\n── Validation ──────────────────────────────────────")
    for label, sql in checks.items():
        cursor.execute(sql)
        result = cursor.fetchall()
        print(f"  {label}: {result}")


# ── Main pipeline ────────────────────────────────────────────
def run_pipeline(vcf_path: str):
    print(f"\n{'='*60}")
    print(f" Pipeline start: {vcf_path}")
    print(f"{'='*60}\n")

    # 1. Parse VCF
    variants_df = parse_vcf(vcf_path)

    # 2. Upload to S3
    s3_uri = upload_to_s3(variants_df, "variants")

    # 3. Connect to Redshift and load
    conn = redshift_connector.connect(
        host=REDSHIFT_HOST,
        database=REDSHIFT_DB,
        user=REDSHIFT_USER,
        password=REDSHIFT_PASS,
        port=REDSHIFT_PORT,
    )
    conn.autocommit = False

    try:
        cursor = conn.cursor()

        redshift_copy(
            cursor,
            table="variants",
            s3_uri=s3_uri,
            columns=["chromosome", "position", "variant_id",
                     "ref_allele", "alt_allele", "variant_type",
                     "af_global", "significance"]
        )

        # 4. Validate
        validate_load(cursor)

        # 5. Update stats
        cursor.execute("ANALYZE genomics.variants;")

        conn.commit()
        print("\n✓ Pipeline complete")

    except Exception as e:
        conn.rollback()
        print(f"\n✗ Pipeline failed: {e}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    import sys
    vcf_file = sys.argv[1] if len(sys.argv) > 1 else "input/sample_cohort.vcf.gz"
    run_pipeline(vcf_file)
