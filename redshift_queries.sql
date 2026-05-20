-- ============================================================
--  REDSHIFT GENOMICS QUERIES
--  All queries use the genomics. schema prefix
--  Syntax is identical to exercises.sql — just add the prefix
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  SAME QUERIES AS SQLITE — just add schema prefix
-- ════════════════════════════════════════════════════════════

-- Gene lengths
SELECT gene_name,
       chromosome,
       (end_pos - start_pos) AS gene_length_bp
FROM genomics.genes
ORDER BY gene_length_bp DESC;

-- Pathogenic variants with gene name
SELECT g.gene_name,
       v.variant_id,
       v.position,
       v.significance
FROM genomics.variants v
JOIN genomics.genes g ON v.gene_id = g.gene_id
WHERE v.significance = 'Pathogenic'
ORDER BY g.gene_name;


-- ════════════════════════════════════════════════════════════
--  REDSHIFT-SPECIFIC FEATURES
-- ════════════════════════════════════════════════════════════

-- ── 1. WINDOW FUNCTIONS ─────────────────────────────────────
-- Rank variants within each gene by global allele frequency
SELECT g.gene_name,
       v.variant_id,
       v.af_global,
       v.significance,
       RANK() OVER (
           PARTITION BY v.gene_id
           ORDER BY v.af_global DESC
       ) AS freq_rank_in_gene
FROM genomics.variants v
JOIN genomics.genes g ON v.gene_id = g.gene_id;

-- Running total of variants per chromosome (ordered by position)
SELECT chromosome,
       position,
       variant_id,
       COUNT(*) OVER (
           PARTITION BY chromosome
           ORDER BY position
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS cumulative_variant_count
FROM genomics.variants
ORDER BY chromosome, position;

-- ── 2. LISTAGG — aggregate strings (Redshift-specific) ──────
-- List all variant IDs per gene as a comma-separated string
SELECT g.gene_name,
       LISTAGG(v.variant_id, ', ')
           WITHIN GROUP (ORDER BY v.position) AS variant_list
FROM genomics.variants v
JOIN genomics.genes g ON v.gene_id = g.gene_id
GROUP BY g.gene_name;

-- ── 3. DATE/TIME (useful for sample metadata) ───────────────
-- Redshift uses TIMESTAMP, not SQLite's TEXT dates
-- Example: if samples had a collection_date column
-- SELECT sample_id,
--        DATEDIFF('year', collection_date, GETDATE()) AS years_ago
-- FROM genomics.samples;

-- ── 4. NVL / COALESCE — handle NULLs ────────────────────────
-- Replace NULL allele frequencies with 0
SELECT variant_id,
       NVL(af_global, 0) AS af_global,
       NVL(af_afr, 0)    AS af_afr,
       NVL(af_eur, 0)    AS af_eur
FROM genomics.variants;

-- ── 5. APPROXIMATE COUNT (fast on huge tables) ──────────────
-- On millions of rows, exact COUNT DISTINCT is slow
-- Redshift has an approximate version:
SELECT APPROXIMATE COUNT(DISTINCT variant_id) AS approx_unique_variants
FROM genomics.sample_variants;


-- ════════════════════════════════════════════════════════════
--  PERFORMANCE: EXPLAIN PLAN
--  Paste EXPLAIN before any query to see how Redshift executes it
-- ════════════════════════════════════════════════════════════

EXPLAIN
SELECT g.gene_name, COUNT(v.variant_id) AS variant_count
FROM genomics.variants v
JOIN genomics.genes g ON v.gene_id = g.gene_id
GROUP BY g.gene_name;

-- Look for:
--   DS_DIST_NONE  → no data movement needed (good, DISTKEY matched)
--   DS_BCAST_INNER → small table broadcast (fine for DISTSTYLE ALL)
--   DS_DIST_BOTH  → both sides shuffled (bad, consider changing DISTKEY)


-- ════════════════════════════════════════════════════════════
--  LOADING REAL GENOMICS DATA FROM S3
--  (gnomAD, ClinVar, TCGA are all available as public S3 datasets)
-- ════════════════════════════════════════════════════════════

-- Step 1: Create an IAM role with S3 read access and attach to Redshift cluster
-- Step 2: Upload your VCF/TSV to S3
-- Step 3: COPY into Redshift

/*
-- Load a gnomAD-style variants TSV from S3
COPY genomics.variants (
    variant_id, gene_id, chromosome, position,
    ref_allele, alt_allele, variant_type, significance,
    af_global, af_afr, af_eur
)
FROM 's3://your-bucket/gnomad/variants_chr17.tsv.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
REGION 'us-east-1'
MAXERROR 10;
*/


-- ════════════════════════════════════════════════════════════
--  USEFUL SYSTEM TABLES (Redshift-specific)
-- ════════════════════════════════════════════════════════════

-- See all your tables
SELECT tablename, tableowner
FROM pg_tables
WHERE schemaname = 'genomics';

-- Check table size (rows and MB)
SELECT stv_tbl_perm.name AS table_name,
       SUM(stv_tbl_perm.rows) AS row_count,
       SUM(stv_tbl_perm.rows * stv_tbl_perm.col_width) / 1024 / 1024 AS size_mb
FROM stv_tbl_perm
JOIN pg_class ON pg_class.oid = stv_tbl_perm.id
JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_namespace.nspname = 'genomics'
GROUP BY stv_tbl_perm.name
ORDER BY size_mb DESC;

-- Check distribution skew (are rows evenly spread across nodes?)
SELECT trim(name) AS table_name,
       slice,
       num_values
FROM svv_diskusage
WHERE name IN ('genes','variants','samples','sample_variants')
ORDER BY table_name, slice;
