-- ============================================================
--  GENOMICS DATABASE — Redshift Version
--  Differences from SQLite:
--    - Strict data types (VARCHAR, FLOAT, INT)
--    - DISTKEY: which column to distribute rows across nodes
--    - SORTKEY: which column to sort within each node (speeds up range queries)
--    - No CHECK constraints (Redshift accepts syntax but doesn't enforce)
--    - Schema prefix: genomics.tablename
-- ============================================================

CREATE SCHEMA IF NOT EXISTS genomics;


-- ── TABLE 1: genes ──────────────────────────────────────────
-- DISTKEY(chromosome): queries filtering by chromosome go to one node
-- SORTKEY(chromosome, start_pos): genomic range queries are much faster
CREATE TABLE genomics.genes (
    gene_id     VARCHAR(20)  NOT NULL,
    gene_name   VARCHAR(50)  NOT NULL,
    chromosome  VARCHAR(10)  NOT NULL,
    start_pos   BIGINT       NOT NULL,
    end_pos     BIGINT       NOT NULL,
    strand      CHAR(1),
    biotype     VARCHAR(30),
    PRIMARY KEY (gene_id)
)
DISTKEY(chromosome)
SORTKEY(chromosome, start_pos);


-- ── TABLE 2: variants ───────────────────────────────────────
-- DISTKEY(chromosome): co-locate with genes on same chromosome
-- SORTKEY(chromosome, position): fast range queries (BED-style lookups)
CREATE TABLE genomics.variants (
    variant_id    VARCHAR(20)  NOT NULL,
    gene_id       VARCHAR(20),
    chromosome    VARCHAR(10)  NOT NULL,
    position      BIGINT       NOT NULL,
    ref_allele    VARCHAR(50)  NOT NULL,
    alt_allele    VARCHAR(50)  NOT NULL,
    variant_type  VARCHAR(20),
    significance  VARCHAR(30),
    af_global     FLOAT,
    af_afr        FLOAT,
    af_eur        FLOAT,
    PRIMARY KEY (variant_id)
)
DISTKEY(chromosome)
SORTKEY(chromosome, position);


-- ── TABLE 3: samples ────────────────────────────────────────
-- DISTSTYLE ALL: small lookup table, copy to every node
--   so joins never require network shuffling
CREATE TABLE genomics.samples (
    sample_id   VARCHAR(20)  NOT NULL,
    patient_age INT,
    sex         CHAR(1),
    population  VARCHAR(10),
    phenotype   VARCHAR(50),
    PRIMARY KEY (sample_id)
)
DISTSTYLE ALL;


-- ── TABLE 4: sample_variants ────────────────────────────────
-- DISTKEY(sample_id): queries per-sample stay on one node
-- SORTKEY(sample_id, variant_id): fast per-sample lookups
CREATE TABLE genomics.sample_variants (
    sample_id   VARCHAR(20)  NOT NULL,
    variant_id  VARCHAR(20)  NOT NULL,
    genotype    VARCHAR(10),
    read_depth  INT,
    qual_score  FLOAT,
    PRIMARY KEY (sample_id, variant_id)
)
DISTKEY(sample_id)
SORTKEY(sample_id, variant_id);


-- ============================================================
--  LOADING DATA — two options
-- ============================================================

-- OPTION A: COPY from S3 (recommended for large data)
-- Upload your TSV/CSV files to S3 first, then:
/*
COPY genomics.genes
FROM 's3://your-bucket/genomics/genes.tsv'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
DELIMITER '\t'
IGNOREHEADER 1
REGION 'us-east-1';

COPY genomics.variants
FROM 's3://your-bucket/genomics/variants.tsv'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
DELIMITER '\t'
IGNOREHEADER 1
REGION 'us-east-1';
*/

-- OPTION B: INSERT directly (fine for small practice data)
INSERT INTO genomics.genes VALUES
('ENSG00000012048', 'BRCA1',   'chr17', 43044295,  43125483, '-', 'protein_coding'),
('ENSG00000141510', 'TP53',    'chr17',  7668402,   7687550, '-', 'protein_coding'),
('ENSG00000146648', 'EGFR',    'chr7',  55019017,  55211628, '+', 'protein_coding'),
('ENSG00000139618', 'BRCA2',   'chr13', 32315086,  32400268, '+', 'protein_coding'),
('ENSG00000157764', 'BRAF',    'chr7', 140719327, 140924929, '-', 'protein_coding'),
('ENSG00000133703', 'KRAS',    'chr12', 25205246,   25250929,'-', 'protein_coding'),
('ENSG00000171862', 'PTEN',    'chr10', 89692905,   89728532,'+', 'protein_coding'),
('ENSG00000181143', 'MUC16',   'chr19',  8959519,   9092018, '+', 'protein_coding'),
('ENSG00000155657', 'TTN',     'chr2', 178525989, 178807423, '-', 'protein_coding'),
('ENSG00000012174', 'MBTPS2',  'chrX', 102423498, 102468907, '+', 'protein_coding'),
('ENSG00000229807', 'XIST',    'chrX',  73820651,  73852753, '+', 'lncRNA'),
('ENSG00000223972', 'DDX11L1', 'chr1',     11869,     14412, '+', 'pseudogene');

INSERT INTO genomics.variants VALUES
('rs80357906',   'ENSG00000012048', 'chr17', 43071077, 'A', 'T',  'SNV',       'Pathogenic',        0.00001,  0.00002,  0.000008),
('rs80357374',   'ENSG00000012048', 'chr17', 43094692, 'G', 'A',  'SNV',       'Pathogenic',        0.000005, 0.000001, 0.000009),
('rs1799950',    'ENSG00000012048', 'chr17', 43106487, 'C', 'T',  'SNV',       'Benign',            0.012,    0.008,    0.015),
('rs28934578',   'ENSG00000141510', 'chr17',  7674220, 'C', 'T',  'SNV',       'Pathogenic',        0.000003, 0.000001, 0.000004),
('rs1042522',    'ENSG00000141510', 'chr17',  7676154, 'C', 'G',  'SNV',       'Benign',            0.49,     0.73,     0.44),
('rs121913529',  'ENSG00000146648', 'chr7',  55152040, 'G', 'A',  'SNV',       'Likely_Pathogenic', 0.000002, 0.000001, 0.000003),
('rs121913530',  'ENSG00000146648', 'chr7',  55152040, 'G', 'T',  'SNV',       'Likely_Pathogenic', 0.000001, 0.0,      0.000002),
('rs113488022',  'ENSG00000157764', 'chr7', 140753336, 'A', 'T',  'SNV',       'Pathogenic',        0.0001,   0.00005,  0.00012),
('rs121913227',  'ENSG00000133703', 'chr12', 25245350, 'C', 'A',  'SNV',       'Pathogenic',        0.00003,  0.00001,  0.00004),
('rs121913529b', 'ENSG00000133703', 'chr12', 25245351, 'C', 'T',  'SNV',       'VUS',               0.00001,  0.00002,  0.000005),
('rs121909218',  'ENSG00000171862', 'chr10', 89711875, 'G', 'A',  'SNV',       'Pathogenic',        0.000004, 0.000002, 0.000005),
('rs2299939',    'ENSG00000171862', 'chr10', 89725043, 'C', 'T',  'SNV',       'Benign',            0.22,     0.18,     0.25),
('rs397507247',  'ENSG00000139618', 'chr13', 32338763, 'A', 'AT', 'insertion', 'Pathogenic',        0.000002, 0.000001, 0.000003),
('rs81002830',   'ENSG00000139618', 'chr13', 32340300, 'T', '-',  'deletion',  'Pathogenic',        0.000001, 0.0,      0.000002),
('rs206076',     'ENSG00000139618', 'chr13', 32379652, 'G', 'A',  'SNV',       'Benign',            0.31,     0.28,     0.33);

INSERT INTO genomics.samples VALUES
('S001', 45, 'F', 'EUR', 'breast_cancer'),
('S002', 62, 'M', 'EUR', 'lung_cancer'),
('S003', 38, 'F', 'AFR', 'breast_cancer'),
('S004', 55, 'M', 'EAS', 'colorectal_cancer'),
('S005', 70, 'F', 'EUR', 'ovarian_cancer'),
('S006', 48, 'M', 'AFR', 'control'),
('S007', 33, 'F', 'SAS', 'breast_cancer'),
('S008', 61, 'M', 'EUR', 'control'),
('S009', 52, 'F', 'AMR', 'breast_cancer'),
('S010', 44, 'M', 'EAS', 'lung_cancer'),
('S011', 67, 'F', 'EUR', 'control'),
('S012', 29, 'M', 'AFR', 'colorectal_cancer');

INSERT INTO genomics.sample_variants VALUES
('S001', 'rs80357906',  'HET',     45, 99.0),
('S001', 'rs1042522',   'HOM_ALT', 52, 99.0),
('S001', 'rs1799950',   'HET',     38, 95.0),
('S003', 'rs80357906',  'HET',     60, 99.0),
('S003', 'rs80357374',  'HET',     55, 98.5),
('S007', 'rs80357906',  'HOM_ALT', 40, 97.0),
('S009', 'rs80357906',  'HET',     48, 99.0),
('S002', 'rs113488022', 'HET',     70, 99.0),
('S002', 'rs121913529', 'HET',     65, 98.0),
('S010', 'rs113488022', 'HET',     55, 99.0),
('S004', 'rs121913227', 'HET',     80, 99.0),
('S012', 'rs121913227', 'HET',     72, 99.0),
('S005', 'rs121909218', 'HET',     44, 99.0),
('S005', 'rs397507247', 'HET',     39, 96.0),
('S001', 'rs397507247', 'HET',     41, 97.0),
('S008', 'rs1042522',   'HET',     50, 99.0),
('S011', 'rs2299939',   'HOM_ALT', 58, 99.0),
('S006', 'rs206076',    'HET',     62, 99.0);
