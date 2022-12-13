# Seq-N-Slide: sequencing data analysis pipelines

[![DOI](https://zenodo.org/badge/66501450.svg)](https://zenodo.org/badge/latestdoi/66501450)

Automated workflows for common sequencing-based (Illumina) protocols, such as RNA-seq, ChIP-seq, ATAC-seq, WGBS/RRBS methylation, whole genome/exome/targeted variant detection, and contaminant screening.

For more information, see the full documentation at https://igordot.github.io/sns

Modified to identify Clonal Hematopoetic mutations (CHIP) in WES sequencing data using Panel of Normals. The pipeline was modified using GATK Best practices.  

<img width="786" alt="GATK_best_practices_Mutect2" src="https://user-images.githubusercontent.com/26681884/207418325-22d6807b-2605-4836-a0dd-7daaeaddb162.png">

This pipeline was developed to generate output similar to Terra's CHIP workflow https://app.terra.bio/#workspaces/terra-outreach/CHIP-Detection-Mutect2.
The Mutect2-GATK4 workflow is designed to perform somatic variant calling on a single tumor-normal pair. This CHIP workflow has been configured to run in tumor-only mode with a PON. Users need to run WES variant calling followed by wes-pairs-snv. 

Somatic variant calling for single nucleotide variants (SNVs) and indels is performed by Mutect2 on BAM files along with the PON. General population frequencies are incorporated from gnomAD. Raw somatic SNVs and indels are then filtered using FilterMutectCalls.

Variants are annotated (using Annovar and filtered using a Rscript) as having CHIP if the output VCF contains one or more of a pre-specified list of putative CHIP variants (see: Bick et al, 2020)

