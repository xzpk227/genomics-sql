"""
Load ANNOVAR multi-sample output into SQLite for SQL practice.
Extracts the key columns most useful for SNV filtering.
"""

import sqlite3
import csv
import sys

INPUT_FILE = "answerals_sql_practice_sql.txt"
DB_FILE    = "annovar_practice.db"

# ── Column indices (0-based) we want to keep ────────────────
# These are the most useful columns for SNV filtering
COLS = {
    "chr":              0,
    "start":            1,
    "end":              2,
    "ref":              3,
    "alt":              4,
    "func_refgene":     5,   # intronic, exonic, splicing, UTR5, UTR3...
    "gene_refgene":     6,   # gene symbol
    "exonic_func":      8,   # synonymous, nonsynonymous, stopgain...
    "aa_change":        9,   # protein change e.g. p.Arg175His
    "cytoband":         10,
    "gnomad_af":        11,  # global allele frequency (gnomAD 3.1.2)
    "gnomad_af_afr":    17,  # African AF
    "gnomad_af_amr":    19,  # American AF
    "gnomad_af_eas":    21,  # East Asian AF
    "gnomad_af_nfe":    24,  # Non-Finnish European AF
    "gnomad_af_sas":    26,  # South Asian AF
    "rsid":             27,  # avsnp150 rsID
    "sift_pred":        31,  # D=Deleterious, T=Tolerated
    "polyphen2_pred":   37,  # D=Damaging, P=Possibly, B=Benign
    "cadd_phred":       82,  # CADD phred score (>20 = top 1%)
    "revel_score":      70,  # REVEL score (>0.5 = likely pathogenic)
    "clinvar_sig":      None, # will find dynamically
    "intervar":         None, # InterVar classification
    # Otherinfo columns = original VCF fields
    "vcf_filter":       140, # Otherinfo5 = FILTER (PASS or reason)
    "vcf_info":         141, # Otherinfo6 = INFO field
}

def find_col(headers, name):
    """Find column index by partial name match."""
    name_lower = name.lower()
    for i, h in enumerate(headers):
        if name_lower in h.lower():
            return i
    return None

def safe_float(val):
    try:
        f = float(val)
        return None if f == -1 else f
    except (ValueError, TypeError):
        return None

def load(input_file, db_file):
    print(f"Loading {input_file} → {db_file}")

    conn = sqlite3.connect(db_file)
    cur  = conn.cursor()

    # Drop and recreate table
    cur.execute("DROP TABLE IF EXISTS variants")
    cur.execute("""
        CREATE TABLE variants (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            chr             TEXT,
            start           INTEGER,
            end             INTEGER,
            ref             TEXT,
            alt             TEXT,
            variant_type    TEXT,   -- SNV, indel (derived)
            func_refgene    TEXT,   -- exonic, intronic, splicing...
            gene            TEXT,
            exonic_func     TEXT,   -- nonsynonymous SNV, synonymous SNV, stopgain...
            aa_change       TEXT,
            cytoband        TEXT,
            gnomad_af       REAL,
            gnomad_af_afr   REAL,
            gnomad_af_amr   REAL,
            gnomad_af_eas   REAL,
            gnomad_af_nfe   REAL,
            gnomad_af_sas   REAL,
            rsid            TEXT,
            sift_pred       TEXT,
            polyphen2_pred  TEXT,
            cadd_phred      REAL,
            revel_score     REAL,
            clinvar_sig     TEXT,
            intervar        TEXT,
            vcf_filter      TEXT,
            qual            REAL
        )
    """)

    with open(input_file, "r", encoding="utf-8") as fh:
        reader = csv.reader(fh, delimiter="\t")
        headers = next(reader)

        # Dynamically find ClinVar and InterVar columns
        clinvar_idx  = find_col(headers, "CLNSIG") or find_col(headers, "clinvar_clnsig")
        intervar_idx = find_col(headers, "InterVar_automated") or find_col(headers, "intervar")
        qual_idx     = find_col(headers, "Otherinfo4")  # QUAL field in VCF

        print(f"  Total columns: {len(headers)}")
        print(f"  ClinVar column: {clinvar_idx} ({headers[clinvar_idx] if clinvar_idx else 'not found'})")
        print(f"  InterVar column: {intervar_idx} ({headers[intervar_idx] if intervar_idx else 'not found'})")

        rows = []
        skipped = 0

        for line_num, row in enumerate(reader, start=2):
            if len(row) < 12:
                skipped += 1
                continue

            def get(idx):
                if idx is None or idx >= len(row):
                    return None
                v = row[idx].strip()
                return None if v in (".", "", "NA", "N/A") else v

            ref = get(3) or ""
            alt = get(4) or ""
            # Determine variant type
            if len(ref) == 1 and len(alt) == 1:
                vtype = "SNV"
            elif len(alt) > len(ref):
                vtype = "insertion"
            else:
                vtype = "deletion"

            rows.append((
                get(0),                      # chr
                int(row[1]) if row[1].isdigit() else None,  # start
                int(row[2]) if row[2].isdigit() else None,  # end
                ref,                         # ref
                alt,                         # alt
                vtype,                       # variant_type
                get(5),                      # func_refgene
                get(6),                      # gene
                get(8),                      # exonic_func
                get(9),                      # aa_change
                get(10),                     # cytoband
                safe_float(get(11)),         # gnomad_af
                safe_float(get(17)),         # gnomad_af_afr
                safe_float(get(19)),         # gnomad_af_amr
                safe_float(get(21)),         # gnomad_af_eas
                safe_float(get(24)),         # gnomad_af_nfe
                safe_float(get(26)),         # gnomad_af_sas
                get(27),                     # rsid
                get(31),                     # sift_pred
                get(37),                     # polyphen2_pred
                safe_float(get(82)),         # cadd_phred
                safe_float(get(70)),         # revel_score
                get(clinvar_idx),            # clinvar_sig
                get(intervar_idx),           # intervar
                get(140),                    # vcf_filter
                safe_float(get(qual_idx)),   # qual
            ))

            # Batch insert every 5000 rows
            if len(rows) >= 5000:
                cur.executemany("INSERT INTO variants VALUES (NULL,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
                rows = []

        # Insert remaining rows
        if rows:
            cur.executemany("INSERT INTO variants VALUES (NULL,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)

    conn.commit()

    # Quick summary
    cur.execute("SELECT COUNT(*) FROM variants")
    total = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM variants WHERE variant_type = 'SNV'")
    snvs = cur.fetchone()[0]
    cur.execute("SELECT COUNT(DISTINCT gene) FROM variants WHERE gene IS NOT NULL")
    genes = cur.fetchone()[0]

    print(f"\n✓ Loaded {total:,} variants ({snvs:,} SNVs) across {genes:,} genes")
    print(f"  Skipped {skipped} malformed rows")
    print(f"  Database: {db_file}")
    conn.close()

if __name__ == "__main__":
    load(INPUT_FILE, DB_FILE)
