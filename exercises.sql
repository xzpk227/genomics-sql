-- ============================================================
--  GENOMICS SQL EXERCISES  —  practice file
--  Run:  sqlite3 genomics.db
--  Then: .read exercises.sql   (runs all)
--  Or paste queries one by one at the sqlite3 prompt
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  LEVEL 1 — SELECT & WHERE  (basic exploration)
-- ════════════════════════════════════════════════════════════

-- Q1. See all genes in the database
SELECT * FROM genes;

-- Q2. List only gene names and their chromosomes
SELECT gene_name, chromosome FROM genes;

-- Q3. Which genes are on chromosome 17?
SELECT gene_name, start_pos, end_pos
FROM genes
WHERE chromosome = 'chr17';

-- Q4. Which genes are on the minus (-) strand?
SELECT gene_name, chromosome, strand
FROM genes
WHERE strand = '-';

-- Q5. Show only protein-coding genes
SELECT gene_name, chromosome, biotype
FROM genes
WHERE biotype = 'protein_coding';

-- Q6. How long is each gene? (end - start)
SELECT gene_name,
       chromosome,
       (end_pos - start_pos) AS gene_length_bp
FROM genes
ORDER BY gene_length_bp DESC;


-- ════════════════════════════════════════════════════════════
--  LEVEL 2 — AGGREGATION  (summarizing data)
-- ════════════════════════════════════════════════════════════

-- Q7. How many genes are on each chromosome?
SELECT chromosome, COUNT(*) AS gene_count
FROM genes
GROUP BY chromosome
ORDER BY gene_count DESC;

-- Q8. How many variants are there per significance category?
SELECT significance, COUNT(*) AS count
FROM variants
GROUP BY significance
ORDER BY count DESC;

-- Q9. What is the average global allele frequency of pathogenic variants?
SELECT AVG(af_global) AS avg_af_pathogenic
FROM variants
WHERE significance = 'Pathogenic';

-- Q10. How many samples per phenotype?
SELECT phenotype, COUNT(*) AS sample_count
FROM samples
GROUP BY phenotype
ORDER BY sample_count DESC;

-- Q11. Average age of patients per phenotype
SELECT phenotype,
       ROUND(AVG(patient_age), 1) AS avg_age,
       MIN(patient_age) AS youngest,
       MAX(patient_age) AS oldest
FROM samples
GROUP BY phenotype;

-- Q12. How many variants per variant type (SNV, insertion, deletion)?
SELECT variant_type, COUNT(*) AS count
FROM variants
GROUP BY variant_type;


-- ════════════════════════════════════════════════════════════
--  LEVEL 3 — JOINs  (connecting tables)
-- ════════════════════════════════════════════════════════════

-- Q13. Show each variant with its gene name
SELECT v.variant_id,
       g.gene_name,
       v.chromosome,
       v.position,
       v.significance
FROM variants v
JOIN genes g ON v.gene_id = g.gene_id;

-- Q14. Show all pathogenic variants with gene name and position
SELECT g.gene_name,
       v.variant_id,
       v.position,
       v.ref_allele,
       v.alt_allele,
       v.significance
FROM variants v
JOIN genes g ON v.gene_id = g.gene_id
WHERE v.significance = 'Pathogenic'
ORDER BY g.gene_name;

-- Q15. Which samples carry which variants? (3-table join)
SELECT s.sample_id,
       s.phenotype,
       g.gene_name,
       v.variant_id,
       sv.genotype,
       v.significance
FROM sample_variants sv
JOIN samples  s ON sv.sample_id  = s.sample_id
JOIN variants v ON sv.variant_id = v.variant_id
JOIN genes    g ON v.gene_id     = g.gene_id
ORDER BY s.sample_id;

-- Q16. Breast cancer patients carrying BRCA1 variants
SELECT s.sample_id,
       s.patient_age,
       s.population,
       v.variant_id,
       sv.genotype,
       v.significance
FROM sample_variants sv
JOIN samples  s ON sv.sample_id  = s.sample_id
JOIN variants v ON sv.variant_id = v.variant_id
JOIN genes    g ON v.gene_id     = g.gene_id
WHERE g.gene_name = 'BRCA1'
  AND s.phenotype = 'breast_cancer';

-- Q17. Genes that have NO variants in our database (LEFT JOIN trick)
SELECT g.gene_name, g.chromosome
FROM genes g
LEFT JOIN variants v ON g.gene_id = v.gene_id
WHERE v.variant_id IS NULL;


-- ════════════════════════════════════════════════════════════
--  LEVEL 4 — SUBQUERIES & CTEs
-- ════════════════════════════════════════════════════════════

-- Q18. Genes that have at least one pathogenic variant (subquery)
SELECT gene_name, chromosome
FROM genes
WHERE gene_id IN (
    SELECT gene_id
    FROM variants
    WHERE significance = 'Pathogenic'
);

-- Q19. Variants rarer than the average global allele frequency
SELECT variant_id, gene_id, af_global, significance
FROM variants
WHERE af_global < (SELECT AVG(af_global) FROM variants)
ORDER BY af_global;

-- Q20. Same query using a CTE (WITH clause) — easier to read
WITH avg_af AS (
    SELECT AVG(af_global) AS mean_af FROM variants
)
SELECT v.variant_id, g.gene_name, v.af_global, v.significance
FROM variants v
JOIN genes g ON v.gene_id = g.gene_id
CROSS JOIN avg_af
WHERE v.af_global < avg_af.mean_af
ORDER BY v.af_global;

-- Q21. Count pathogenic variants per gene using a CTE
WITH pathogenic AS (
    SELECT gene_id, COUNT(*) AS path_count
    FROM variants
    WHERE significance = 'Pathogenic'
    GROUP BY gene_id
)
SELECT g.gene_name, p.path_count
FROM genes g
JOIN pathogenic p ON g.gene_id = p.gene_id
ORDER BY p.path_count DESC;


-- ════════════════════════════════════════════════════════════
--  LEVEL 5 — REAL ANALYSIS QUERIES
-- ════════════════════════════════════════════════════════════

-- Q22. Population frequency comparison for BRCA1 variants
--      (African vs European allele frequency)
SELECT v.variant_id,
       v.position,
       v.significance,
       v.af_afr,
       v.af_eur,
       ROUND(v.af_afr - v.af_eur, 6) AS afr_eur_diff
FROM variants v
JOIN genes g ON v.gene_id = g.gene_id
WHERE g.gene_name = 'BRCA1'
ORDER BY ABS(v.af_afr - v.af_eur) DESC;

-- Q23. For each cancer type, how many unique pathogenic variants were found?
SELECT s.phenotype,
       COUNT(DISTINCT sv.variant_id) AS unique_pathogenic_variants
FROM sample_variants sv
JOIN samples  s ON sv.sample_id  = s.sample_id
JOIN variants v ON sv.variant_id = v.variant_id
WHERE v.significance = 'Pathogenic'
GROUP BY s.phenotype
ORDER BY unique_pathogenic_variants DESC;

-- Q24. Samples with HIGH-QUALITY (qual_score = 99) pathogenic calls
SELECT s.sample_id,
       s.phenotype,
       s.population,
       g.gene_name,
       v.variant_id,
       sv.read_depth,
       sv.qual_score
FROM sample_variants sv
JOIN samples  s ON sv.sample_id  = s.sample_id
JOIN variants v ON sv.variant_id = v.variant_id
JOIN genes    g ON v.gene_id     = g.gene_id
WHERE v.significance = 'Pathogenic'
  AND sv.qual_score  = 99.0
ORDER BY g.gene_name, s.sample_id;

-- Q25. Genomic range query — all variants between two positions on chr17
SELECT v.variant_id,
       g.gene_name,
       v.position,
       v.ref_allele,
       v.alt_allele,
       v.significance
FROM variants v
JOIN genes g ON v.gene_id = g.gene_id
WHERE v.chromosome = 'chr17'
  AND v.position BETWEEN 7000000 AND 44000000
ORDER BY v.position;


-- ════════════════════════════════════════════════════════════
--  CHALLENGE QUESTIONS  (try these yourself first!)
-- ════════════════════════════════════════════════════════════

-- C1. Which gene has the most variants in our database?

-- C2. List all female breast cancer patients who carry a pathogenic variant.
--     Show: sample_id, age, population, gene_name, variant_id

-- C3. Find variants where the African allele frequency is higher than
--     the European allele frequency. Show the difference.

-- C4. What is the average read depth per genotype category
--     (HET, HOM_ALT, HOM_REF)?

-- C5. Which samples carry variants in more than one gene?
--     (Hint: COUNT DISTINCT gene_id per sample)
