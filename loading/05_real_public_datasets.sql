-- ============================================================
--  Loading REAL public genomics datasets into Redshift
--
--  These are actual public S3 buckets maintained by AWS or
--  the data providers. No download needed — COPY reads
--  directly from the public bucket.
--
--  NOTE: Your Redshift cluster must be in us-east-1 for most
--  of these, or use COPY with REGION specified.
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  1. ClinVar — clinical variant significance
--     Source: AWS Open Data Registry
--     Updated monthly by NCBI
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS genomics.clinvar (
    allele_id        BIGINT,
    variant_type     VARCHAR(50),
    gene_symbol      VARCHAR(50),
    clinical_sig     VARCHAR(200),   -- Pathogenic, Benign, VUS, etc.
    review_status    VARCHAR(100),
    chromosome       VARCHAR(10),
    start_pos        BIGINT,
    stop_pos         BIGINT,
    ref_allele       VARCHAR(500),
    alt_allele       VARCHAR(500),
    rs_id            VARCHAR(20),
    assembly         VARCHAR(10)     -- GRCh37 or GRCh38
)
DISTKEY(chromosome)
SORTKEY(chromosome, start_pos);

COPY genomics.clinvar
FROM 's3://aws-roda-hcls-datalake/clinvar/variant_summary/variant_summary.txt.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
NULL AS 'na'
MAXERROR 1000
REGION 'us-east-1';

-- Quick check: how many pathogenic variants per gene?
SELECT gene_symbol,
       COUNT(*) AS pathogenic_count
FROM genomics.clinvar
WHERE clinical_sig ILIKE '%pathogenic%'
  AND assembly = 'GRCh38'
GROUP BY gene_symbol
ORDER BY pathogenic_count DESC
LIMIT 20;


-- ════════════════════════════════════════════════════════════
--  2. dbSNP — variant IDs and basic annotations
--     Useful for mapping rsIDs to genomic positions
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS genomics.dbsnp (
    rs_id        VARCHAR(20),
    chromosome   VARCHAR(10),
    position     BIGINT,
    ref_allele   VARCHAR(500),
    alt_allele   VARCHAR(500),
    variant_type VARCHAR(30),
    af_global    FLOAT
)
DISTKEY(chromosome)
SORTKEY(chromosome, position);

-- dbSNP is huge (~900M rows for human) — load one chromosome at a time
COPY genomics.dbsnp
FROM 's3://aws-roda-hcls-datalake/dbsnp/GRCh38/chr17.vcf.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
NULL AS '.'
MAXERROR 5000
REGION 'us-east-1';


-- ════════════════════════════════════════════════════════════
--  3. GTEx — gene expression by tissue
--     Useful for: "is this gene expressed in breast tissue?"
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS genomics.gtex_expression (
    gene_id      VARCHAR(20),
    gene_name    VARCHAR(50),
    tissue       VARCHAR(100),
    median_tpm   FLOAT,       -- transcripts per million
    sample_count INT
)
DISTSTYLE ALL               -- small enough to broadcast to all nodes
SORTKEY(gene_name, tissue);

COPY genomics.gtex_expression
FROM 's3://my-genomics-bucket/reference/gtex_median_tpm.tsv.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
REGION 'us-east-1';

-- Query: BRCA1 expression across tissues
SELECT tissue, median_tpm
FROM genomics.gtex_expression
WHERE gene_name = 'BRCA1'
ORDER BY median_tpm DESC;


-- ════════════════════════════════════════════════════════════
--  4. TCGA — cancer sample metadata
--     Useful for: linking variants to cancer subtypes
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS genomics.tcga_samples (
    case_id          VARCHAR(50),
    project          VARCHAR(20),   -- TCGA-BRCA, TCGA-LUAD, etc.
    sample_type      VARCHAR(50),   -- Primary Tumor, Normal, etc.
    primary_site     VARCHAR(100),
    age_at_diagnosis INT,
    sex              CHAR(1),
    vital_status     VARCHAR(20),
    days_to_death    INT
)
DISTSTYLE ALL
SORTKEY(project, primary_site);

COPY genomics.tcga_samples
FROM 's3://my-genomics-bucket/reference/tcga_clinical.tsv.gz'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftS3ReadRole'
FORMAT AS CSV
DELIMITER '\t'
IGNOREHEADER 1
GZIP
NULL AS '--'
REGION 'us-east-1';


-- ════════════════════════════════════════════════════════════
--  CROSS-DATABASE QUERY: join your variants with ClinVar
--  This is the real power — your cohort data + public reference
-- ════════════════════════════════════════════════════════════

-- Which variants in your cohort are classified as Pathogenic in ClinVar?
SELECT
    sv.sample_id,
    s.phenotype,
    v.variant_id,
    v.chromosome,
    v.position,
    cv.gene_symbol,
    cv.clinical_sig,
    cv.review_status
FROM genomics.sample_variants sv
JOIN genomics.variants  v  ON sv.variant_id = v.variant_id
JOIN genomics.samples   s  ON sv.sample_id  = s.sample_id
JOIN genomics.clinvar   cv ON v.chromosome  = cv.chromosome
                           AND v.position   = cv.start_pos
                           AND v.ref_allele = cv.ref_allele
                           AND v.alt_allele = cv.alt_allele
WHERE cv.clinical_sig ILIKE '%pathogenic%'
  AND cv.assembly = 'GRCh38'
ORDER BY cv.gene_symbol, sv.sample_id;


-- Variants in your cohort that are NOT yet in ClinVar
-- (potential novel findings worth investigating)
SELECT
    v.variant_id,
    v.chromosome,
    v.position,
    v.ref_allele,
    v.alt_allele,
    COUNT(sv.sample_id) AS carrier_count
FROM genomics.variants v
JOIN genomics.sample_variants sv ON v.variant_id = sv.variant_id
LEFT JOIN genomics.clinvar cv
    ON v.chromosome  = cv.chromosome
   AND v.position    = cv.start_pos
   AND v.ref_allele  = cv.ref_allele
   AND v.alt_allele  = cv.alt_allele
WHERE cv.allele_id IS NULL          -- not found in ClinVar
  AND sv.genotype IN ('HET', 'HOM_ALT')
GROUP BY v.variant_id, v.chromosome, v.position, v.ref_allele, v.alt_allele
HAVING COUNT(sv.sample_id) >= 2     -- seen in at least 2 samples
ORDER BY carrier_count DESC;
