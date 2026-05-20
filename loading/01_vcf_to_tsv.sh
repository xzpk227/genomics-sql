#!/bin/bash
# ============================================================
#  STEP 1: Convert VCF → TSV for Redshift loading
#
#  A bioinformatician typically starts with a VCF file from
#  GATK, DeepVariant, or a public source like gnomAD/ClinVar.
#  Redshift can't read VCF directly — we flatten it to TSV first.
#
#  Tools needed: bcftools  (brew install bcftools)
# ============================================================

VCF_FILE="input/sample_cohort.vcf.gz"
OUT_TSV="output/variants_flat.tsv"

# ── Basic VCF → TSV with bcftools query ─────────────────────
# %CHROM  = chromosome
# %POS    = position
# %ID     = rsID (or . if unknown)
# %REF    = reference allele
# %ALT    = alternate allele
# %FILTER = PASS or filter reason
# %INFO/AF = allele frequency from INFO field
# [%GT]   = genotype per sample (bracket = per-sample field)

bcftools query \
  -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t%FILTER\t%INFO/AF\t%INFO/DP\n' \
  -r chr17,chr13,chr7 \
  --include 'FILTER="PASS"' \
  "$VCF_FILE" \
  | awk 'BEGIN{OFS="\t"; print "chromosome","position","variant_id","ref_allele","alt_allele","filter","af_global","read_depth"}
         {print $1,$2,($3=="."?"rs_unknown_"NR:$3),$4,$5,$6,$7,$8}' \
  > "$OUT_TSV"

echo "Rows written: $(wc -l < $OUT_TSV)"


# ── Multi-sample VCF: extract per-sample genotypes ──────────
# This produces one row per (sample, variant) — matches our
# sample_variants table structure

SAMPLES_TSV="output/sample_variants_flat.tsv"

bcftools query \
  -f '[%SAMPLE\t%CHROM\t%POS\t%ID\t%GT\t%DP\t%GQ\n]' \
  --include 'FILTER="PASS" && GT!="./."' \
  "$VCF_FILE" \
  | awk 'BEGIN{OFS="\t"; print "sample_id","chromosome","position","variant_id","genotype","read_depth","qual_score"}
         {
           # Normalize genotype: 0/0→HOM_REF, 0/1→HET, 1/1→HOM_ALT
           gt = $5
           if (gt == "0/0" || gt == "0|0") gt = "HOM_REF"
           else if (gt == "0/1" || gt == "1/0" || gt == "0|1" || gt == "1|0") gt = "HET"
           else if (gt == "1/1" || gt == "1|1") gt = "HOM_ALT"
           print $1,$2,$3,($4=="."?"rs_unknown_"NR:$4),gt,$6,$7
         }' \
  > "$SAMPLES_TSV"

echo "Sample-variant rows: $(wc -l < $SAMPLES_TSV)"


# ── Compress for S3 upload (Redshift COPY loves gzip) ────────
gzip -k "$OUT_TSV"
gzip -k "$SAMPLES_TSV"

echo "Ready to upload:"
echo "  output/variants_flat.tsv.gz"
echo "  output/sample_variants_flat.tsv.gz"
