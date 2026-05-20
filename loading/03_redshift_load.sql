-- ============================================================
--  STEP 3: Load data into Redshift from S3
--
--  Run these in order. Each section covers a real scenario
--  a bioinformatician would encounter.
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  SCENARIO A: Load a single processed variants TSV
--  (e.g., after running your VCF pipeline on one cohort)
-- ════════════════════════════════════════════════════════════

COPY genomics.variants (
    chromosome,
    position,
    variant_id,
    ref_allele,
    alt_allele,
    variant_type,
    significance,
    af_global
)
FROM 's3://my-genomics-bucket/data/brca_cohort/2026-05-17/variants_flat.tsv.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1          -- skip the header row
GZIP                    -- file is gzip compressed
NULL AS '.'             -- VCF uses '.' for missing values → load as NULL
EMPTYASNULL             -- empty string → NULL
MAXERROR 100            -- tolerate up to 100 bad rows before failing
REGION 'us-east-1';


-- ════════════════════════════════════════════════════════════
--  SCENARIO B: Load per-sample genotypes (sample_variants)
-- ════════════════════════════════════════════════════════════

COPY genomics.sample_variants (
    sample_id,
    variant_id,
    genotype,
    read_depth,
    qual_score
)
FROM 's3://my-genomics-bucket/data/brca_cohort/2026-05-17/sample_variants_flat.tsv.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
NULL AS '.'
MAXERROR 50
REGION 'us-east-1';


-- ════════════════════════════════════════════════════════════
--  SCENARIO C: Load from a MANIFEST
--  Use this when your VCF was split per chromosome (common
--  in WGS pipelines — one file per chrom = parallelism)
-- ════════════════════════════════════════════════════════════

COPY genomics.variants
FROM 's3://my-genomics-bucket/data/brca_cohort/2026-05-17/variants_manifest.json'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
NULL AS '.'
MANIFEST                -- tells Redshift this is a manifest file
REGION 'us-east-1';


-- ════════════════════════════════════════════════════════════
--  SCENARIO D: Load a public dataset directly
--  gnomAD, ClinVar, and TCGA are available as public S3 buckets
-- ════════════════════════════════════════════════════════════

-- ClinVar variant summary (tab-delimited, publicly available)
-- Source: s3://aws-roda-hcls-datalake/clinvar/
CREATE TABLE IF NOT EXISTS genomics.clinvar_raw (
    allele_id          INT,
    variant_type       VARCHAR(50),
    name               VARCHAR(500),
    gene_id            VARCHAR(20),
    gene_symbol        VARCHAR(50),
    hgnc_id            VARCHAR(20),
    clinical_sig       VARCHAR(100),
    review_status      VARCHAR(100),
    last_evaluated     VARCHAR(20),
    rs_db_snp          VARCHAR(20),
    chromosome         VARCHAR(10),
    start_pos          BIGINT,
    stop_pos           BIGINT,
    ref_allele         VARCHAR(200),
    alt_allele         VARCHAR(200),
    origin             VARCHAR(50),
    assembly           VARCHAR(20)
)
DISTKEY(chromosome)
SORTKEY(chromosome, start_pos);

COPY genomics.clinvar_raw
FROM 's3://aws-roda-hcls-datalake/clinvar/variant_summary/variant_summary.txt.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
NULL AS 'na'
MAXERROR 500
REGION 'us-east-1';


-- ════════════════════════════════════════════════════════════
--  SCENARIO E: Incremental load (new samples added each week)
--  Use a staging table → deduplicate → merge into main table
-- ════════════════════════════════════════════════════════════

-- 1. Create a staging table (same structure, no constraints)
CREATE TABLE genomics.variants_staging (LIKE genomics.variants);

-- 2. Load new data into staging
COPY genomics.variants_staging
FROM 's3://my-genomics-bucket/data/brca_cohort/2026-05-24/variants_flat.tsv.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
NULL AS '.'
REGION 'us-east-1';

-- 3. Delete any rows in main table that exist in staging (avoid duplicates)
DELETE FROM genomics.variants
WHERE variant_id IN (SELECT variant_id FROM genomics.variants_staging);

-- 4. Insert new + updated rows from staging
INSERT INTO genomics.variants
SELECT * FROM genomics.variants_staging;

-- 5. Clean up staging
TRUNCATE genomics.variants_staging;


-- ════════════════════════════════════════════════════════════
--  AFTER LOADING: always run these
-- ════════════════════════════════════════════════════════════

-- Update table statistics so the query planner works correctly
ANALYZE genomics.variants;
ANALYZE genomics.sample_variants;

-- Reclaim space from deleted rows (like VACUUM in PostgreSQL)
VACUUM genomics.variants;

-- Quick sanity check
SELECT
    'variants'        AS tbl, COUNT(*) AS rows FROM genomics.variants
UNION ALL SELECT
    'sample_variants' AS tbl, COUNT(*) AS rows FROM genomics.sample_variants
UNION ALL SELECT
    'samples'         AS tbl, COUNT(*) AS rows FROM genomics.samples
UNION ALL SELECT
    'genes'           AS tbl, COUNT(*) AS rows FROM genomics.genes;


-- ════════════════════════════════════════════════════════════
--  CHECK FOR LOAD ERRORS
--  Redshift logs every rejected row — always check this
-- ════════════════════════════════════════════════════════════

SELECT query, filename, line_number, colname, err_reason
FROM stl_load_errors
ORDER BY starttime DESC
LIMIT 20;
