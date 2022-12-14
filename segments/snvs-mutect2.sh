#!/bin/bash


# call variants with Mutect2 (2.1 part of GATK 4)

# ML-Week of September 12, removed all mention of Sample Normal
# FS-November 4th, edited Mary's mutect 2 script to make it similar to Terra's CHIP script

# script filename
script_path="${BASH_SOURCE[0]}"
script_name=$(basename "$script_path")
segment_name=${script_name/%.sh/}
echo -e "\n ========== SEGMENT: $segment_name ========== \n" >&2

# check for correct number of arguments
if [ ! $# == 4 ] ; then
	echo -e "\n $script_name ERROR: WRONG NUMBER OF ARGUMENTS SUPPLIED \n" >&2
	echo -e "\n USAGE: $script_name project_dir tumor_sample_name tumor_bam threads \n" >&2
	if [ $# -gt 0 ] ; then echo -e "\n ARGS: $* \n" >&2 ; fi
	exit 1
fi

# arguments
proj_dir=$(readlink -f "$1")
sample_t=$2
bam_t=$3
threads=$4


#########################


# check that inputs exist

if [ ! -d "$proj_dir" ] ; then
	echo -e "\n $script_name ERROR: PROJ DIR $proj_dir DOES NOT EXIST \n" >&2
	exit 1
fi

if [ ! -s "$bam_t" ] ; then
	echo -e "\n $script_name ERROR: BAM $bam_t DOES NOT EXIST \n" >&2
	exit 1
fi

code_dir=$(dirname $(dirname "$script_path"))

genome_dir=$(bash ${code_dir}/scripts/get-set-setting.sh "${proj_dir}/settings.txt" GENOME-DIR)

if [ ! -d "$genome_dir" ] ; then
	echo -e "\n $script_name ERROR: GENOME DIR $genome_dir DOES NOT EXIST \n" >&2
	exit 1
fi

ref_fasta=$(bash ${code_dir}/scripts/get-set-setting.sh "${proj_dir}/settings.txt" REF-FASTA)

if [ ! -s "$ref_fasta" ] ; then
	echo -e "\n $script_name ERROR: FASTA $ref_fasta DOES NOT EXIST \n" >&2
	exit 1
fi

found_bed=$(find "$proj_dir" -maxdepth 1 -type f -iname "*.bed" | grep -v "probes" | sort | head -1)
bed=$(bash "${code_dir}/scripts/get-set-setting.sh" "${proj_dir}/settings.txt" EXP-TARGETS-BED "$found_bed")

if [ ! -s "$bed" ] ; then
	echo -e "\n $script_name ERROR: BED $bed DOES NOT EXIST \n" >&2
	exit 1
fi


#########################


# settings and files

sample="${sample_t}"

summary_dir="${proj_dir}/summary"
mkdir -p "$summary_dir"
contamination_csv="${summary_dir}/${sample_t}.VCF-Mutect2-contamination.csv"

vcf_dir="${proj_dir}/VCF-Mutect2"
mkdir -p "$vcf_dir"

mutect_logs_dir="${proj_dir}/logs-${segment_name}"
mkdir -p "$mutect_logs_dir"

vcf_unfiltered="${mutect_logs_dir}/${sample_t}.unfiltered.vcf"
idx_unfiltered="${vcf_unfiltered}.idx"

vcf_filtered="${vcf_dir}/${sample_t}.original.vcf.gz"
idx_filtered="${vcf_filtered}.tbi"

vcf_fixed="${vcf_dir}/${sample_t}.vcf"

pileup_table_t="${mutect_logs_dir}/${sample_t}.t.pileup.txt"
contamination_table="${mutect_logs_dir}/${sample_t}.contamination.txt"
stats="${mutect_logs_dir}/${sample_t}.unfiltered.vcf.stats"
bam_output="${mutect_logs_dir}/${sample_t}.bamout.bam"
f1r2_counts="${mutect_logs_dir}/${sample_t}.f1r2.tar.gz"
artifact_prior="${mutect_logs_dir}/${sample_t}.artifact_prior.tar.gz"
segment_table="${mutect_logs_dir}/${sample_t}.segments.table"

# FS 11/04/2022 Included stats in settings and files


# annotation command (next segment)
annot_cmd="bash ${code_dir}/segments/annot-annovar.sh $proj_dir $sample $vcf_fixed"

# unload all loaded modulefiles
module purge
module add default-environment


#########################


# check for output

# skip to annotation if final VCF exists already
if [ -s "$vcf_fixed" ] ; then
	echo -e "\n $script_name SKIP SAMPLE $sample \n" >&2
	echo -e "\n CMD: $annot_cmd \n"
	($annot_cmd)
	exit 0
fi

# delete unfiltered VCF (likely incomplete since the final fixed VCF was not generated)
if [ -s "$vcf_unfiltered" ] ; then
	echo -e "\n $script_name WARNING: POTENTIALLY CORRUPT VCF $vcf_unfiltered EXISTS \n" >&2
	rm -fv "$vcf_unfiltered"
	rm -fv "$idx_unfiltered"
fi

# delete filtered VCF (likely incomplete since the final fixed VCF was not generated)
if [ -s "$vcf_filtered" ] ; then
	echo -e "\n $script_name WARNING: POTENTIALLY CORRUPT VCF $vcf_filtered EXISTS \n" >&2
	rm -fv "$vcf_filtered"
	rm -fv "$idx_filtered"
fi


#########################


# GATK settings

# known variants
genome_build=$(basename "$genome_dir")
if [[ "$genome_build" == "hg19" ]] ; then
	germline_resource_arg="--germline-resource ${genome_dir}/gatk-bundle/af-only-gnomad.raw.sites.hg19.vcf.gz"
	pileup_variants="${genome_dir}/gatk-bundle/small_exac_common_3.hg19.vcf.gz"
elif [[ "$genome_build" == "hg38" ]] ; then
	germline_resource_arg="--germline-resource ${genome_dir}/gatk-bundle/af-only-gnomad.hg38.vcf.gz"
	pileup_variants="${genome_dir}/gatk-bundle/small_exac_common_3.hg38.vcf.gz"
else
	germline_resource_arg=""
	pileup_variants=""
fi


#########################


# GATK Mutect2

module add python/cpu/3.6.5

# command
gatk_bin="${proj_dir}/gatk-4.1.6.0/gatk"

echo
echo " * GATK: $(readlink -f $gatk_bin) "
echo " * GATK version: $($gatk_bin Mutect2 --version 2>&1 | grep "v4") "
echo " * sample T : $sample_t "
echo " * BAM T : $bam_t "
echo " * intervals BED: $bed "
echo " * VCF unfiltered: $vcf_unfiltered "
echo

# --native-pair-hmm-threads: how many threads should a native pairHMM implementation use
# --max-reads-per-alignment-start: maximum number of reads to retain per alignment start position (50)
# --dont-use-soft-clipped-bases: do not analyze soft clipped bases in the reads
# --germline-resource: population vcf of germline sequencing containing allele fractions

mutect_cmd="
$gatk_bin --java-options \"-Xms8G -Xmx8G\" Mutect2 \
--seconds-between-progress-updates 600 \
--native-pair-hmm-threads $threads \
--reference $ref_fasta \
$germline_resource_arg \
--intervals $bed \
--input $bam_t \
--tumor-sample $sample_t \
--panel-of-normals ${proj_dir}/1000g_pon.hg38.vcf.gz \
--bam-output $bam_output \
--f1r2-tar-gz $f1r2_counts \
--downsampling-stride 20 \
--max-suspicious-reads-per-alignment-start 6 \
--max-reads-per-alignment-start 6 \
--output $vcf_unfiltered \
"
echo -e "\n CMD: $mutect_cmd \n"
eval "$mutect_cmd"

# ML—Week of September 12, changed to panel of normal comparison (from comparison with Sample Normal)
# FS 11/04/2022 Removed --dont-use-soft-clipped-bases argument, removed --max-reads-per-alignment-start 100, removed interval padding
# FS 11/04/2022 Added --bam-output $bam_output, --f1r2-tar-gz 
#########################


# check that output generated

# check if VCF file is present
if [ ! -s "$vcf_unfiltered" ] ; then
	echo -e "\n $script_name ERROR: VCF $vcf_unfiltered NOT GENERATED \n" >&2
	exit 1
fi

# check if VCF index is present (should be present if VCF is complete)
if [ ! -s "$idx_unfiltered" ] ; then
	echo -e "\n $script_name ERROR: VCF IDX $idx_unfiltered NOT GENERATED \n" >&2
	# delete VCF since something went wrong and it might be corrupted
	rm -fv "$vcf_unfiltered"
	exit 1
fi


#########################


# estimate cross-sample contamination for genomes with available resources

# GetPileupSummaries: tabulates read counts that support ref and alt alleles for the sites in the resource
# CalculateContamination: calculate the fraction of reads coming from cross-sample contamination

# if [ -n "$pileup_variants" ] ; then

	# tabulates pileup metrics for T
	pileup_t_cmd="
	$gatk_bin --java-options \"-Xms8G -Xms8G\" GetPileupSummaries \
	--verbosity WARNING \
	--variant $pileup_variants \
	--intervals $bed \
  	--reference $ref_fasta \
	--input $bam_t \
	--output $pileup_table_t \
	"
	echo -e "\n CMD: $pileup_t_cmd \n"
	eval "$pileup_t_cmd"

# FS 11042022 Removed --interval-padding 100 from GetPileupSummaries
# FS 11042022 Added --reference $ref_fasta
#
# LearnReadOrientationModel - Learn the prior probability of read orientation artifact from the output of CollectF1R2Counts of Mutect2
	 learn_read_orientation_model_t_cmd="
	 $gatk_bin --java-options \"-Xms8G -Xms8G\" LearnReadOrientationModel \
	 --verbosity WARNING \
	 --input $f1r2_counts \
	 --output $artifact_prior \
	 "
	 echo -e "\n CMD: $learn_read_orientation_model_t_cmd \n"
  	 eval "$learn_read_orientation_model_t_cmd"

# # #FS 11042022 Added LearnReadOrientationModel tool
#
# 	# the resulting table provides the fraction contamination, one line per sample
 	contamination_cmd="
 	$gatk_bin --java-options \"-Xms8G -Xms8G\" CalculateContamination \
 	--verbosity WARNING \
 	--input $pileup_table_t \
 	--output $contamination_table \
	--tumor-segmentation $segment_table \
	"
 	echo -e "\n CMD: $contamination_cmd \n"
 	eval "$contamination_cmd"

# #FS 11042022 Added --tumor-segmentation $segment_table

#
#
# 	# check if contamination table is present
 	if [ ! -s "$contamination_table" ] ; then
 		echo -e "\n $script_name ERROR: CONTAMINATION TABLE $contamination_table NOT GENERATED \n" >&2
 		# delete pileups since something went wrong and they might be corrupted
# 		rm -fv "$pileup_table_t"
 		exit 1
 	fi
#
# 	# set the parameter for next step
 	contamination_arg="--contamination-table $contamination_table"
#
# 	# contamination summary
 	contamination_score=$(cat "$contamination_table" | grep -v 'contamination' | head -1 | cut -f 2)
 	echo "contamination original: $contamination_score"
 	contamination_score=$(printf "%.5f" "$contamination_score")
 	echo "contamination rounded: $contamination_score"
 	contamination_header="#SAMPLE,contamination"
 	echo "${contamination_header}" > "$contamination_csv"
 	echo "${sample},${contamination_score}" >> "$contamination_csv"
 	sleep 5
 	cat ${summary_dir}/*.VCF-Mutect2-contamination.csv | LC_ALL=C sort -t ',' -k1,1 | uniq > "${proj_dir}/summary.VCF-Mutect2-contamination.csv"


#
#
# #########################
#
#
# # GATK FilterMutectCalls
#
echo
echo " * VCF unfiltered: $vcf_unfiltered "
 echo " * VCF filtered: $vcf_filtered "
 echo
#
# # --unique-alt-read-count: filter a variant if fewer than this many unique reads supporting the alternate allele (0)
# #ML-Week of September 12, changed the --unique-alt-read-count and --min-allele-fraction arguments (lowered threshold)
#
mutect_filter_cmd="
$gatk_bin --java-options \"-Xms8G -Xms8G\" FilterMutectCalls \
--verbosity WARNING \
--reference $ref_fasta \
--variant $vcf_unfiltered \
$contamination_arg \
--tumor-segmentation $segment_table \
--ob-priors $artifact_prior \
--filtering-stats $stats \
--output $vcf_filtered \
"
 echo -e "\n CMD: $mutect_filter_cmd \n"
 eval "$mutect_filter_cmd"


# #########################
#
#
# # check that output generated
#
 # check if VCF file is present
 if [ ! -s "$vcf_filtered" ] ; then
 	echo -e "\n $script_name ERROR: VCF $vcf_filtered NOT GENERATED \n" >&2
 	exit 1
 fi
#
# check if VCF index is present (should be present if VCF is complete)
 if [ ! -s "$idx_filtered" ] ; then
	echo -e "\n $script_name ERROR: VCF IDX $idx_filtered NOT GENERATED \n" >&2
 	# delete VCF since something went wrong and it might be corrupted
 	rm -fv "$vcf_filtered"
 	exit 1
 fi


# #########################
#
#
 # adjust VCF for ANNOVAR compatibility (http://annovar.openbioinformatics.org/en/latest/articles/VCF/) module add samtools/1.9

 echo
 echo " * samtools: $(readlink -f $(which samtools)) "
 echo " * samtools version: $(samtools --version | head -1) "
 echo " * VCF filtered: $vcf_filtered "
 echo " * VCF fixed: $vcf_fixed "
 echo

 # 1) keep header and only passing variants
 # 2) split multi-allelic variants calls into separate lines (uses VCF 4.2 specification)
 # 3) perform indel left-normalization (start position shifted to the left until it is no longer possible to do so)

 fix_vcf_cmd="
 zcat $vcf_filtered \
 > $vcf_fixed
 "
 echo -e "\n CMD: $fix_vcf_cmd \n"
 eval "$fix_vcf_cmd"


 #########################


 # check that output generated

 if [ ! -s "$vcf_fixed" ] ; then
 	echo -e "\n $script_name ERROR: VCF $vcf_fixed NOT GENERATED \n" >&2
 	exit 1
 fi


 #########################


 # clean up

# rm -fv "$vcf_unfiltered"
# rm -fv "$idx_unfiltered"
# rm -fv "$pileup_table_t"

 #########################


# annotate

 echo -e "\n CMD: $annot_cmd \n"
 ($annot_cmd)


 #########################

# end
