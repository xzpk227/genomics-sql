"""
Run all SNV filters and save each result to a CSV file.
Usage: python3 run_filters.py
"""

import sqlite3
import pandas as pd
from pathlib import Path

DB   = "annovar_practice.db"
OUT  = Path("results")
OUT.mkdir(exist_ok=True)

# ── Define all filters ───────────────────────────────────────
# Each entry: (filename, description, SQL query)
FILTERS = [

    ("01_all_snvs",
     "All SNVs (no indels)",
     """
     SELECT chr, start, ref, alt, gene, func_refgene, gnomad_af
     FROM variants
     WHERE variant_type = 'SNV'
     """),

    ("02_exonic_snvs",
     "Exonic SNVs only",
     """
     SELECT chr, start, ref, alt, gene, exonic_func, aa_change, gnomad_af
     FROM variants
     WHERE variant_type  = 'SNV'
       AND func_refgene  = 'exonic'
     ORDER BY chr, start
     """),

    ("03_nonsynonymous",
     "Nonsynonymous (missense) SNVs",
     """
     SELECT chr, start, ref, alt, gene, exonic_func, aa_change,
            gnomad_af, sift_pred, polyphen2_pred, cadd_phred
     FROM variants
     WHERE variant_type = 'SNV'
       AND exonic_func  = 'nonsynonymous SNV'
     ORDER BY cadd_phred DESC
     """),

    ("04_rare",
     "Rare nonsynonymous SNVs (gnomAD AF < 1%)",
     """
     SELECT chr, start, ref, alt, gene, exonic_func,
            gnomad_af, cadd_phred
     FROM variants
     WHERE variant_type = 'SNV'
       AND exonic_func  = 'nonsynonymous SNV'
       AND (gnomad_af < 0.01 OR gnomad_af IS NULL)
     ORDER BY gnomad_af ASC
     """),

    ("05_damaging_predictions",
     "Damaging by SIFT and PolyPhen2",
     """
     SELECT chr, start, ref, alt, gene, aa_change,
            gnomad_af, sift_pred, polyphen2_pred, cadd_phred
     FROM variants
     WHERE variant_type  = 'SNV'
       AND exonic_func   = 'nonsynonymous SNV'
       AND sift_pred     = 'D'
       AND polyphen2_pred IN ('D', 'P')
     ORDER BY cadd_phred DESC
     """),

    ("06_high_cadd",
     "High CADD score (phred >= 20)",
     """
     SELECT chr, start, ref, alt, gene, exonic_func, aa_change,
            gnomad_af, cadd_phred, sift_pred, polyphen2_pred
     FROM variants
     WHERE variant_type = 'SNV'
       AND cadd_phred   >= 20
     ORDER BY cadd_phred DESC
     """),

    ("07_stopgain",
     "Stopgain / nonsense variants",
     """
     SELECT chr, start, ref, alt, gene, aa_change,
            gnomad_af, cadd_phred
     FROM variants
     WHERE variant_type = 'SNV'
       AND exonic_func  = 'stopgain'
     ORDER BY gnomad_af ASC
     """),

    ("08_splicing",
     "Splicing variants",
     """
     SELECT chr, start, ref, alt, gene, func_refgene,
            gnomad_af, cadd_phred
     FROM variants
     WHERE variant_type  = 'SNV'
       AND func_refgene LIKE '%splicing%'
     ORDER BY cadd_phred DESC
     """),

    ("09_standard_pipeline",
     "Full standard pipeline filter (all criteria combined)",
     """
     SELECT chr, start, ref, alt, gene,
            func_refgene, exonic_func, aa_change,
            ROUND(gnomad_af, 6)   AS gnomad_af,
            sift_pred, polyphen2_pred,
            ROUND(cadd_phred, 1)  AS cadd_phred,
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
     ORDER BY cadd_phred DESC
     """),

    ("10_per_gene_summary",
     "Per-gene summary of damaging variants",
     """
     SELECT
         gene,
         COUNT(*)                                           AS total_snvs,
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
     """),
]


# ── Run all filters ──────────────────────────────────────────
def run():
    conn = sqlite3.connect(DB)
    print(f"Connected to {DB}\n")
    print(f"{'Filter':<35} {'Rows':>8}  Output")
    print("-" * 70)

    for name, description, sql in FILTERS:
        df = pd.read_sql(sql, conn)
        out_path = OUT / f"{name}.csv"
        df.to_csv(out_path, index=False)
        print(f"{description:<35} {len(df):>8}  {out_path}")

    conn.close()
    print(f"\nDone. All results saved to: {OUT}/")

if __name__ == "__main__":
    run()
