# Genomics SQL Demo

A hands-on SQL learning project using real genomics data structures — variants, genes, samples, and ANNOVAR annotations.

## What's in here

```
SQL/
├── setup.sql                        # Create and populate the practice database
├── exercises.sql                    # 25 guided queries + 5 challenges
├── answers.sql                      # Challenge answers
├── redshift_setup.sql               # Same schema adapted for AWS Redshift
├── redshift_queries.sql             # Redshift-specific features (window functions, COPY)
├── SQL-knowledge.txt                # Notes on SQL concepts
│
├── answeralspractice/
│   ├── load_annovar.py              # Load ANNOVAR output into SQLite
│   └── snv_filters.sql             # SNV filtering queries on ANNOVAR data
│
└── loading/
    ├── 01_vcf_to_tsv.sh             # Convert VCF to TSV using bcftools
    ├── 02_upload_to_s3.sh           # Upload processed files to S3
    ├── 03_redshift_load.sql         # COPY commands for loading into Redshift
    ├── 04_pipeline.py               # End-to-end VCF → S3 → Redshift pipeline
    └── 05_real_public_datasets.sql  # Load ClinVar, GTEx, TCGA from public S3
```

## Getting started

**1. Set up the practice database (SQLite)**

```bash
sqlite3 genomics.db < setup.sql
sqlite3 genomics.db
```

**2. Run the exercises**

```sql
.read exercises.sql
```

Or paste queries one by one at the `sqlite>` prompt.

**3. Load your own ANNOVAR file**

```bash
cd answeralspractice
python3 load_annovar.py
sqlite3 annovar_practice.db
.read snv_filters.sql
```

## Practice database schema

Four tables modelled after real genomics databases:

| Table | Description |
|---|---|
| `genes` | 12 genes (BRCA1, TP53, EGFR, KRAS...) with coordinates |
| `variants` | 15 variants with rsIDs, allele frequencies, clinical significance |
| `samples` | 12 patients with age, sex, population, cancer type |
| `sample_variants` | Genotype calls linking samples to variants |

## SNV filtering (ANNOVAR)

`snv_filters.sql` contains 10 progressive filters for a real ANNOVAR multi-sample output:

1. SNVs only
2. Exonic SNVs
3. Nonsynonymous (missense)
4. Rare variants (gnomAD AF < 1%)
5. Damaging predictions (SIFT, PolyPhen2)
6. High CADD score (≥ 20)
7. Stopgain / nonsense
8. Splicing variants
9. **Full standard pipeline filter** (all criteria combined)
10. Per-gene summary

## Redshift

The `redshift_setup.sql` and `loading/` folder cover moving from local SQLite to AWS Redshift:
- Schema design with DISTKEY and SORTKEY for genomic range queries
- COPY command patterns for loading from S3
- Incremental loading with staging tables
- Joining your cohort against public datasets (ClinVar, gnomAD)

## Requirements

- SQLite 3 (pre-installed on macOS)
- Python 3 + pandas (for `load_annovar.py`)
- bcftools (for VCF processing scripts)
- AWS CLI + boto3 (for S3/Redshift scripts)
