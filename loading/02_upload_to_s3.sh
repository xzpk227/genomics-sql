#!/bin/bash
# ============================================================
#  STEP 2: Upload processed files to S3
#
#  Redshift's COPY command reads directly from S3.
#  Organize by data type and date for easy versioning.
# ============================================================

BUCKET="s3://my-genomics-bucket"
DATE=$(date +%Y-%m-%d)
PROJECT="brca_cohort"

# ── Upload flat variant files ────────────────────────────────
aws s3 cp output/variants_flat.tsv.gz \
    "$BUCKET/data/$PROJECT/$DATE/variants_flat.tsv.gz" \
    --sse AES256

aws s3 cp output/sample_variants_flat.tsv.gz \
    "$BUCKET/data/$PROJECT/$DATE/sample_variants_flat.tsv.gz" \
    --sse AES256

# ── Upload a manifest (optional but useful for large cohorts) ─
# A manifest tells Redshift exactly which files to load.
# Useful when you split a large VCF into per-chromosome files.

cat > output/variants_manifest.json << 'MANIFEST'
{
  "entries": [
    {"url": "s3://my-genomics-bucket/data/brca_cohort/2026-05-17/variants_chr1.tsv.gz",  "mandatory": true},
    {"url": "s3://my-genomics-bucket/data/brca_cohort/2026-05-17/variants_chr2.tsv.gz",  "mandatory": true},
    {"url": "s3://my-genomics-bucket/data/brca_cohort/2026-05-17/variants_chr17.tsv.gz", "mandatory": true},
    {"url": "s3://my-genomics-bucket/data/brca_cohort/2026-05-17/variants_chr13.tsv.gz", "mandatory": true}
  ]
}
MANIFEST

aws s3 cp output/variants_manifest.json \
    "$BUCKET/data/$PROJECT/$DATE/variants_manifest.json"

echo "Upload complete. Files at: $BUCKET/data/$PROJECT/$DATE/"
