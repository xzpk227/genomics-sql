-- ============================================================
--  SNV FILTERING QUERIES ON YOUR ANNOVAR DATA
--  Database: annovar_practice.db
--  Open with: sqlite3 annovar_practice.db
--  Then run:  .read snv_filters.sql
-- ============================================================

-- First, turn on nice formatting
.headers on
.mode column


-- ════════════════════════════════════════════════════════════
--  STEP 0: Understand what's in your data
-- ════════════════════════════════════════════════════════════

-- How many variants total, and by type?
SELECT variant_type, COUNT(*) AS count
FROM variants
GROUP BY variant_type;

-- What functional categories exist?
SELECT func_refgene, COUNT(*) AS count
FROM variants
GROUP BY func_refgene
ORDER BY count DESC;

-- What exonic functions exist?
SELECT exonic_func, COUNT(*) AS count
FROM variants
WHERE exonic_func IS NOT NULL
GROUP BY exonic_func
ORDER BY count DESC;


-- ════════════════════════════════════════════════════════════
--  FILTER 1: Keep only SNVs (exclude indels)
-- ════════════════════════════════════════════════════════════

SELECT chr, start, ref, alt, gene, func_refgene, gnomad_af
FROM variants
WHERE variant_type = 'SNV'
LIMIT 10;


-- ════════════════════════════════════════════════════════════
--  FILTER 2: Exonic SNVs only
--  (removes intronic, UTR, intergenic — focus on coding)
-- ════════════════════════════════════════════════════════════

SELECT chr, start, ref, alt, gene, exonic_func, aa_change, gnomad_af
FROM variants
WHERE variant_type   = 'SNV'
  AND func_refgene   = 'exonic'
ORDER BY chr, start
LIMIT 20;

-- How many exonic SNVs?
SELECT COUNT(*) AS exonic_snv_count
FROM variants
WHERE variant_type = 'SNV'
  AND func_refgene = 'exonic';


-- ════════════════════════════════════════════════════════════
--  FILTER 3: Nonsynonymous SNVs
--  (amino acid changes — the ones that matter functionally)
-- ════════════════════════════════════════════════════════════

SELECT chr, start, ref, alt, gene, exonic_func, aa_change,
       gnomad_af, sift_pred, polyphen2_pred, cadd_phred
FROM variants
WHERE variant_type = 'SNV'
  AND exonic_func  = 'nonsynonymous SNV'
ORDER BY cadd_phred DESC NULLS LAST
LIMIT 20;


-- ════════════════════════════════════════════════════════════
--  FILTER 4: Rare variants (gnomAD AF > 10%)
--  Standard filter for disease-relevant variants
-- ════════════════════════════════════════════════════════════

SELECT chr, start, ref, alt, gene, exonic_func,
       gnomad_af, cadd_phred
FROM variants
WHERE variant_type = 'SNV'
  AND exonic_func  = 'nonsynonymous SNV'
  AND (gnomad_af > 0.1)
ORDER BY gnomad_af ASC NULLS FIRST
LIMIT 20;


-- ════════════════════════════════════════════════════════════
--  FILTER 5: Damaging predictions
--  SIFT: D = Deleterious
--  PolyPhen2: D = Probably Damaging, P = Possibly Damaging
-- ════════════════════════════════════════════════════════════

SELECT chr, start, ref, alt, gene, aa_change,
       gnomad_af, sift_pred, polyphen2_pred, cadd_phred
FROM variants
WHERE variant_type  = 'SNV'
  AND exonic_func   = 'nonsynonymous SNV'
  AND sift_pred     = 'D'
  AND polyphen2_pred IN ('D', 'P')
ORDER BY cadd_phred DESC NULLS LAST
LIMIT 20;


-- ════════════════════════════════════════════════════════════
--  FILTER 6: High CADD score (phred >= 20 = top 1% most deleterious)
-- ════════════════════════════════════════════════════════════

SELECT chr, start, ref, alt, gene, exonic_func, aa_change,
       gnomad_af, cadd_phred, sift_pred, polyphen2_pred
FROM variants
WHERE variant_type = 'SNV'
  AND cadd_phred   >= 20
ORDER BY cadd_phred DESC
LIMIT 20;


-- ════════════════════════════════════════════════════════════
--  FILTER 7: Stopgain / nonsense variants
--  These truncate the protein — often high impact
-- ════════════════════════════════════════════════════════════

SELECT chr, start, ref, alt, gene, aa_change,
       gnomad_af, cadd_phred
FROM variants
WHERE variant_type = 'SNV'
  AND exonic_func  = 'stopgain'
ORDER BY gnomad_af ASC NULLS FIRST;


-- ════════════════════════════════════════════════════════════
--  FILTER 8: Splicing variants
--  Can disrupt mRNA splicing even outside exons
-- ════════════════════════════════════════════════════════════

SELECT chr, start, ref, alt, gene, func_refgene,
       gnomad_af, cadd_phred
FROM variants
WHERE variant_type  = 'SNV'
  AND func_refgene LIKE '%splicing%'
ORDER BY cadd_phred DESC NULLS LAST
LIMIT 20;


-- ════════════════════════════════════════════════════════════
--  FILTER 9: THE STANDARD PIPELINE FILTER
--  Combines all the above — this is what most papers use
--
--  Criteria:
--    1. SNV only
--    2. Exonic OR splicing
--    3. NOT synonymous
--    4. Rare (AF > 0.1)
--    5. Damaging (SIFT=D OR PolyPhen=D/P OR CADD>=20)
-- ════════════════════════════════════════════════════════════

SELECT
    chr,
    start,
    ref,
    alt,
    gene,
    func_refgene,
    exonic_func,
    aa_change,
    ROUND(gnomad_af, 6)  AS gnomad_af,
    sift_pred,
    polyphen2_pred,
    ROUND(cadd_phred, 1) AS cadd_phred,
    ROUND(revel_score, 3) AS revel_score
FROM variants
WHERE variant_type = 'SNV'
  AND (func_refgene = 'exonic' OR func_refgene LIKE '%splicing%')
  AND exonic_func NOT IN ('synonymous SNV', 'unknown')
  AND exonic_func IS NOT NULL
  AND (gnomad_af < 0.01 OR gnomad_af IS NULL)
  AND (
      sift_pred      = 'D'
   OR polyphen2_pred IN ('D', 'P')
   OR cadd_phred     >= 20
  )
ORDER BY cadd_phred DESC NULLS LAST;

-- Count how many pass the full filter
SELECT COUNT(*) AS variants_passing_all_filters
FROM variants
WHERE variant_type = 'SNV'
  AND (func_refgene = 'exonic' OR func_refgene LIKE '%splicing%')
  AND exonic_func NOT IN ('synonymous SNV', 'unknown')
  AND exonic_func IS NOT NULL
  AND (gnomad_af < 0.01 OR gnomad_af IS NULL)
  AND (
      sift_pred      = 'D'
   OR polyphen2_pred IN ('D', 'P')
   OR cadd_phred     >= 20
  );


-- ════════════════════════════════════════════════════════════
--  FILTER 10: Per-gene summary of damaging variants
-- ════════════════════════════════════════════════════════════

SELECT
    gene,
    COUNT(*)                                          AS total_snvs,
    SUM(CASE WHEN exonic_func = 'nonsynonymous SNV'
             THEN 1 ELSE 0 END)                       AS missense,
    SUM(CASE WHEN exonic_func = 'stopgain'
             THEN 1 ELSE 0 END)                       AS stopgain,
    SUM(CASE WHEN func_refgene LIKE '%splicing%'
             THEN 1 ELSE 0 END)                       AS splicing,
    SUM(CASE WHEN cadd_phred >= 20
             THEN 1 ELSE 0 END)                       AS high_cadd,
    ROUND(MIN(gnomad_af), 6)                          AS min_af,
    ROUND(AVG(cadd_phred), 1)                         AS avg_cadd
FROM variants
WHERE variant_type = 'SNV'
  AND gene IS NOT NULL
GROUP BY gene
HAVING total_snvs > 1
ORDER BY stopgain DESC, high_cadd DESC
LIMIT 30;
