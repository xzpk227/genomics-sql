-- ============================================================
--  CHALLENGE ANSWERS  —  try exercises.sql first!
-- ============================================================

-- C1. Which gene has the most variants?
SELECT g.gene_name, COUNT(v.variant_id) AS variant_count
FROM genes g
JOIN variants v ON g.gene_id = v.gene_id
GROUP BY g.gene_name
ORDER BY variant_count DESC
LIMIT 1;

-- C2. Female breast cancer patients with a pathogenic variant
SELECT s.sample_id,
       s.patient_age,
       s.population,
       g.gene_name,
       v.variant_id
FROM sample_variants sv
JOIN samples  s ON sv.sample_id  = s.sample_id
JOIN variants v ON sv.variant_id = v.variant_id
JOIN genes    g ON v.gene_id     = g.gene_id
WHERE s.sex       = 'F'
  AND s.phenotype = 'breast_cancer'
  AND v.significance = 'Pathogenic';

-- C3. Variants where African AF > European AF
SELECT v.variant_id,
       g.gene_name,
       v.af_afr,
       v.af_eur,
       ROUND(v.af_afr - v.af_eur, 6) AS afr_minus_eur
FROM variants v
JOIN genes g ON v.gene_id = g.gene_id
WHERE v.af_afr > v.af_eur
ORDER BY afr_minus_eur DESC;

-- C4. Average read depth per genotype
SELECT genotype,
       ROUND(AVG(read_depth), 1) AS avg_depth,
       COUNT(*) AS call_count
FROM sample_variants
GROUP BY genotype;

-- C5. Samples carrying variants in more than one gene
SELECT s.sample_id,
       s.phenotype,
       COUNT(DISTINCT g.gene_id) AS genes_with_variants
FROM sample_variants sv
JOIN samples  s ON sv.sample_id  = s.sample_id
JOIN variants v ON sv.variant_id = v.variant_id
JOIN genes    g ON v.gene_id     = g.gene_id
GROUP BY s.sample_id
HAVING COUNT(DISTINCT g.gene_id) > 1
ORDER BY genes_with_variants DESC;
