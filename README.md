# Seq-N-Slide: sequencing data analysis pipelines (CHIP variant calling with Panel of normals)

[![DOI](https://zenodo.org/badge/66501450.svg)](https://zenodo.org/badge/latestdoi/66501450)

Automated workflows for common sequencing-based (Illumina) protocols, such as RNA-seq, ChIP-seq, ATAC-seq, WGBS/RRBS methylation, whole genome/exome/targeted variant detection, and contaminant screening.

For more information, see the full documentation at https://igordot.github.io/sns

Modified to identify Clonal Hematopoetic mutations (CHIP) in WES sequencing data using Panel of Normals. The pipeline was modified using GATK Best practices.  

<img width="786" alt="GATK_best_practices_Mutect2" src="https://user-images.githubusercontent.com/26681884/207418325-22d6807b-2605-4836-a0dd-7daaeaddb162.png">

This pipeline was developed to generate output similar to Terra's CHIP workflow https://app.terra.bio/#workspaces/terra-outreach/CHIP-Detection-Mutect2.
The Mutect2-GATK4 workflow is designed to perform somatic variant calling on a single tumor-normal pair. This CHIP workflow has been configured to run in tumor-only mode with a PON. Users need to run WES variant calling followed by wes-pairs-snv. 

Somatic variant calling for single nucleotide variants (SNVs) and indels is performed by Mutect2 on BAM files along with the PON. General population frequencies are incorporated from gnomAD. Raw somatic SNVs and indels are then filtered using FilterMutectCalls.

Variants are annotated (using Annovar and filtered using a Rscript) as having CHIP if the output VCF contains one or more of a pre-specified list of putative CHIP variants (see: Bick et al, 2020)

##Usage
Inorder to run the CHIP somatic mutation pipeline, process the fastq files using WES route on SNS. 

Route: wes
Alignment and variant detection for whole genome/exome/targeted sequencing data.

Segments:

Trim adapters and low quality bases (Trimmomatic).
Align to the reference genome (BWA-MEM).
Remove duplicate reads (Sambamba).
Realign and recalibrate (GATK).
Determine fragment size distribution.
Determine capture efficiency and depth of coverage (GATK).
Call point mutations and small insertions/deletions (GATK HaplotypeCaller and LoFreq).
For somatic variant detection, follow with wes-pairs-snv.

Usage
Set up a new analysis (common across all routes). If running for the first time, check the detailed usage instructions for an explanation of every step.

cd <project dir>
git clone --depth 1 https://github.com/igordot/sns
sns/generate-settings <genome>
sns/gather-fastqs <fastq dir>
Add a BED file defining the genomic regions targeted for capture to the project directory. The targeted regions (or primary targets) are the regions your capture kit attempts to cover, usually exons of genes of interest.

Run wes route.

sns/run wes
  
  
Once the samples have been processed, you can proceed with CHIP variant calling. 
  - Rename the sns folder in the project directory to "sns-og" 
  - Download the sns scripts from https://github.com/shaikhfarheen03/sns-chip using the following command git clone --depth 1 https://github.com/shaikhfarheen03/sns-chip
  - Download the zip file (https://github.com/shaikhfarheen03/sns-chip/blob/main/CHIP_PON_whitelist_filter.zip) to the project directory. This zip file contains pon and whitelist R script.
  - Download the gatk version 4.1.6.0 to the project directory using this commnd wget https://github.com/broadinstitute/gatk/releases/download/4.1.6.0/gatk-4.1.6.0.zip
  - Install R packages data.table (version1.14.6) and bioMart(2.54.0) on bigpurple in your local R directory. 
  - Modify the samples.csv and remove the #normal header and NAs. Make sure you only have #tumor and tumor samples listed in the samplesheet.
  - Run the script using the sns/run wes-pairs-snv command.
  - Once complete the output will be generated in the Mutect2-annot folder. You'll find 4 csv files for each sample. 
  - Concatenate the wl output
  - Filte variants using this artcle, https://ashpublications.org/blood/article-abstract/doi/10.1182/blood.2022018825/494152/A-practical-approach-to-curate-clonal?redirectedFrom=fulltext
