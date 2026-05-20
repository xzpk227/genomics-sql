-- ============================================================
--  GENOMICS SQL PRACTICE DATABASE
-- ============================================================

-- ── TABLE 1: genes ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS genes (
    gene_id     TEXT PRIMARY KEY,
    gene_name   TEXT NOT NULL,
    chromosome  TEXT NOT NULL,
    start_pos   INTEGER NOT NULL,
    end_pos     INTEGER NOT NULL,
    strand      TEXT CHECK(strand IN ('+', '-')),
    biotype     TEXT   -- protein_coding, lncRNA, pseudogene, etc.
);

INSERT INTO genes VALUES
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


-- ── TABLE 2: variants ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS variants (
    variant_id   TEXT PRIMARY KEY,
    gene_id      TEXT REFERENCES genes(gene_id),
    chromosome   TEXT NOT NULL,
    position     INTEGER NOT NULL,
    ref_allele   TEXT NOT NULL,
    alt_allele   TEXT NOT NULL,
    variant_type TEXT,   -- SNV, insertion, deletion
    significance TEXT,   -- Pathogenic, Benign, VUS
    af_global    REAL,   -- allele frequency global
    af_afr       REAL,   -- allele frequency African
    af_eur       REAL    -- allele frequency European
);

INSERT INTO variants VALUES
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


-- ── TABLE 3: samples ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS samples (
    sample_id   TEXT PRIMARY KEY,
    patient_age INTEGER,
    sex         TEXT CHECK(sex IN ('M','F')),
    population  TEXT,   -- EUR, AFR, EAS, SAS, AMR
    phenotype   TEXT    -- cancer type or 'control'
);

INSERT INTO samples VALUES
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


-- ── TABLE 4: sample_variants (genotype calls) ───────────────
CREATE TABLE IF NOT EXISTS sample_variants (
    sample_id   TEXT REFERENCES samples(sample_id),
    variant_id  TEXT REFERENCES variants(variant_id),
    genotype    TEXT,    -- HOM_REF, HET, HOM_ALT
    read_depth  INTEGER,
    qual_score  REAL,
    PRIMARY KEY (sample_id, variant_id)
);

INSERT INTO sample_variants VALUES
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
