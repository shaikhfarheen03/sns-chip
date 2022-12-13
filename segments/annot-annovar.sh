#!/bin/bash


# annotate VCF using ANNOVAR


# script filename
script_path="${BASH_SOURCE[0]}"
script_name=$(basename "$script_path")
segment_name=${script_name/%.sh/}
echo -e "\n ========== SEGMENT: $segment_name ========== \n" >&2

# check for correct number of arguments
if [ ! $# == 3 ] ; then
	echo -e "\n $script_name ERROR: WRONG NUMBER OF ARGUMENTS SUPPLIED \n" >&2
	echo -e "\n USAGE: $script_name project_dir sample_name VCF_file \n" >&2
	if [ $# -gt 0 ] ; then echo -e "\n ARGS: $* \n" >&2 ; fi
	exit 1
fi

# arguments
proj_dir=$1
sample=$2
vcf_file=$3


#########################


# settings and files

vcf_type=$(basename "$(dirname "$vcf_file")")

# adjust segment name to reflect input variant type
segment_name="${vcf_type}-annot"

summary_dir="${proj_dir}/summary"
mkdir -p "$summary_dir"
summary_csv="${summary_dir}/${sample}.${segment_name}.csv"

annovar_dir="${proj_dir}/${segment_name}"
mkdir -p "$annovar_dir"

# clean up sample name for paired samples
sample_clean=${sample}

## Dec2022-FS: Updated the sample_clean variable

annovar_input="${annovar_dir}/${sample_clean}.avinput"
annovar_out_prefix="${annovar_dir}/${sample_clean}"
annovar_out_fixed="${annovar_out_prefix}.annot.txt"
annovar_combined="${annovar_out_prefix}.combined.txt"
vcf_table="${annovar_out_prefix}.vcf.txt"

# unload all loaded modulefiles
module purge
module add default-environment


#########################


# exit if output exits already

if [ -s "$annovar_combined" ] ; then
	echo -e "\n $script_name $segment_name SKIP SAMPLE $sample \n" >&2
	exit 0
fi


#########################


# check inputs and references

if [ ! -d "$proj_dir" ] ; then
	echo -e "\n $script_name ERROR: DIR $proj_dir DOES NOT EXIST \n" >&2
	exit 1
fi

if [ ! -s "$vcf_file" ] ; then
	echo -e "\n $script_name ERROR: VCF $vcf_file DOES NOT EXIST \n" >&2
	exit 1
fi

code_dir=$(dirname $(dirname "$script_path"))

genome_dir=$(bash "${code_dir}/scripts/get-set-setting.sh" "${proj_dir}/settings.txt" GENOME-DIR);

if [ ! -d "$genome_dir" ] ; then
	echo -e "\n $script_name ERROR: GENOME DIR $genome_dir DOES NOT EXIST \n" >&2
	exit 1
fi


#########################


# check if the VCF file has variants

# get number of variants (non-header lines)
num_variants=$(cat "$vcf_file" | grep -v '^#' | wc -l)

# create a blank summary file in case there are errors (such as no variants) before the segment completes
summary_header="#SAMPLE,total muts,coding muts,nonsyn muts"
echo "${summary_header}" > "$summary_csv"
echo "${sample_clean},${num_variants},X,X" >> "$summary_csv"

# exit if the VCF file does not contain variants
if [ "$num_variants" -eq 0 ] ; then
	echo -e "\n $script_name ERROR: VCF $vcf_file HAS NO VARIANTS \n" >&2
	exit 1
fi


#########################


# ANNOVAR genome-specific settings

# ANNOVAR directory
annovar_path="/gpfs/data/igorlab/software/annovar/annovar-170716"
annovar_db_path="/gpfs/data/igorlab/ref/annovar"

# genome build (used to define settings and as table_annovar.pl parameter)
genome_build=$(basename "$genome_dir")

# table_annovar output file (automatically named)
annovar_multianno="${annovar_out_prefix}.${genome_build}_multianno.txt"

# genome-specific settings (available annotations differ)
# protocol, operation, and argument must have the same number of fields/commas
# annovar_protocol, annovar_operation - table_annovar parameters
# annovar_cols_grep - column names to grep for the final fixed table

# Dec2022-FS: Modified the annotation databases by changing the annovar_protocol for hg38. Terra annotates using refgene and cosmic70. Updated annovar_operation to g and f. Updated the splicing threshold to 2. Updated the number of commas after splicing threshold. Updated the annovar_cols_grep command. 
if [[ "$genome_build" == "hg19" ]] ; then
	annovar_protocol="refGene,avsnp150,gnomad211_exome,kaviar_20150923,cosmic88,cosmic90,intervar_20180118,cadd13gt10,fathmm"
	annovar_operation="g,f,f,f,f,f,f,f,f"
	annovar_argument="'--splicing_threshold 10',,,,,,,,"
	annovar_cols_grep="^Ref|^Alt|refGene|avsnp|AF_popmax|cancer_AF|controls_AF|Kaviar_AF|cosmic|InterVar|CADD13_PHRED|FATHMM"
elif [[ "$genome_build" == "hg38" ]] ; then
	annovar_protocol="refGene,cosmic94"
	annovar_operation="g,f"
	annovar_argument="'--splicing_threshold 2',"
	annovar_cols_grep="^Ref|^Alt|refGene|cosmic"
elif [[ "$genome_build" == "mm10" ]] ; then
	annovar_protocol="refGene,snp142,snp142Common"
	annovar_operation="g,f,f"
	annovar_argument="'--splicing_threshold 10',,"
	annovar_cols_grep="^Ref|^Alt|refGene|snp"
elif [[ "$genome_build" == "dm3" ]] ; then
	annovar_protocol="refGene,ensGene"
	annovar_operation="g,g"
	annovar_argument="'--splicing_threshold 10','--splicing_threshold 10'"
	annovar_cols_grep="^Ref|^Alt|Gene"
elif [[ "$genome_build" == "dm6" ]] ; then
	annovar_protocol="refGene,ensGene"
	annovar_operation="g,g"
	annovar_argument="'--splicing_threshold 10','--splicing_threshold 10'"
	annovar_cols_grep="^Ref|^Alt|Gene"
elif [[ "$genome_build" == "canFam3" ]] ; then
	annovar_protocol="refGene,ensGene"
	annovar_operation="g,g"
	annovar_argument="'--splicing_threshold 10','--splicing_threshold 10'"
	annovar_cols_grep="^Ref|^Alt|Gene"
elif [[ "$genome_build" == "sacCer3" ]] ; then
	annovar_protocol="sgdGene,ensGene"
	annovar_operation="g,g"
	annovar_argument="'--splicing_threshold 10','--splicing_threshold 10'"
	annovar_cols_grep="^Ref|^Alt|Gene"
else
	echo -e "\n $script_name ERROR: UNKNOWN GENOME $genome_build \n" >&2
	exit 1
fi


#########################


# extract variant info (quality, depth, frequency) from a VCF in a table format for merging with annotations

module add r/3.6.1

echo
echo " * R: $(readlink -f $(which R)) "
echo " * R version: $(R --version | head -1) "
echo " * Rscript: $(readlink -f $(which Rscript)) "
echo " * Rscript version: $(Rscript --version 2>&1) "
echo

# test relevant R packages
Rscript --vanilla "${code_dir}/scripts/test-package.R" tidyverse
Rscript --vanilla "${code_dir}/scripts/test-package.R" glue
Rscript --vanilla "${code_dir}/scripts/test-package.R" vcfR

vcf_table_cmd="Rscript --vanilla ${code_dir}/scripts/vcf-table.R $sample $vcf_file $vcf_table"
echo -e "\n CMD: $vcf_table_cmd \n"
($vcf_table_cmd)

sleep 5


#########################


# check that vcf to table conversion completed

if [ ! -s "$vcf_table" ] ; then
	echo -e "\n $script_name ERROR: $vcf_table IS EMPTY \n" >&2
	exit 1
fi


#########################


# ANNOVAR convert2annovar - convert VCF to ANNOVAR input format

echo
echo " * convert2annovar path: $(readlink -f ${annovar_path}/convert2annovar.pl) "
echo " * ANNOVAR out dir: $annovar_dir "
echo " * convert2annovar out : $annovar_input "
echo

# 8/2013: vcf4 changed behavior (only first sample processed) and vcf4old introduced
# 7/2014: annovar can take vcf files as input, but output will be vcf

convert_cmd="
perl ${annovar_path}/convert2annovar.pl --format vcf4old --includeinfo $vcf_file > $annovar_input
"
echo -e "\n CMD: $convert_cmd \n"
eval "$convert_cmd"

sleep 5


#########################


# check that convert2annovar completed

if [ ! -s "$annovar_input" ] ; then
	echo -e "\n $script_name ERROR: $annovar_input IS EMPTY \n" >&2
	exit 1
fi


#########################


# ANNOVAR table_annovar - run a pipeline on a list of variants and summarize their functional effects

echo
echo " * table_annovar path: $(readlink -f ${annovar_path}/table_annovar.pl) "
echo " * ANNOVAR out dir: $annovar_dir "
echo " * table_annovar out prefix : $annovar_out_prefix "
echo " * table_annovar out : $annovar_multianno "
echo


# annotate with annovar (outputs $annovar_multianno)

## Dec2022 FS Using vcf_file as input instead of annovar_input to retain the PASS annotation for variants. Igor's originnal pipeline filters and annotates only the PASS variant calls.
table_cmd="
perl ${annovar_path}/table_annovar.pl $vcf_file ${annovar_db_path}/${genome_build}/ \
--outfile $annovar_out_prefix \
--buildver $genome_build \
--protocol $annovar_protocol \
--operation $annovar_operation \
--argument $annovar_argument \
--nastring . \
--vcfinput \
--remove
"
echo -e "\n CMD: $table_cmd \n"
eval "$table_cmd"

sleep 5


#########################


# check that table_annovar completed

if [ ! -s "$annovar_multianno" ] ; then
	echo -e "\n $script_name ERROR: $annovar_multianno IS EMPTY \n" >&2
	exit 1
fi


#########################

# Dec2022 FS - unload all loaded modulefiles
# The R script works with this specific version of R. 
# Adding R script path


module purge
module add default-environment

module add r/4.2.2
Rscript --vanilla ${proj_dir}/whitelist_filter_files/whitelist_filter_rscript.R $sample $proj_dir

# prepare ANNOVAR multianno table for merging with variant info from VCF

# get column names (add extra column that will become mutation ID)
#unfiltered_header=$(head -1 "$annovar_multianno" | awk -F $'\t' 'BEGIN {OFS=FS} {print "X", $0}')
# convert column names to comma-separated numbers
#annovar_keep_cols=$(echo "$unfiltered_header" \
#| tr '\t' '\n' \
#| grep -En "$annovar_cols_grep" \
#| cut -d ':' -f 1 \
#| tr '\n' ',')
# add column 1 (mutation ID) and remove trailing comma
#annovar_keep_cols=$(echo "1,$annovar_keep_cols" | rev | cut -c 2- | rev)

# add mutation ID, filter columns, and sort multianno table
# backslashes in awk to prevent variable expansion and retain quotes
#bash_cmd="
#cat $annovar_multianno \
#| awk -F $'\t' 'BEGIN {OFS=FS} {print \$1 \":\" \$2 \":\" \$4 \":\" \$5, \$0}' \
#| cut -f $annovar_keep_cols \
#| sed 's/Chr:Start:Ref:Alt/#MUT/g' \
#| sed 's/avsnp1/dbSNP_1/g' \
#| LC_ALL=C sort -k1,1 \
#> $annovar_out_fixed
#"
#echo -e "\n CMD: $bash_cmd \n"
#eval "$bash_cmd"

#sleep 5


#########################


# check that table_annovar completed

#if [ ! -s "$annovar_out_fixed" ] ; then
#	echo -e "\n $script_name ERROR: $annovar_out_fixed IS EMPTY \n" >&2
#	exit 1
#fi


#########################


# merge variant info from VCF with annotations from ANNOVAR

#join_cmd="
#LC_ALL=C join -a1 -t $'\t' \
#<(LC_ALL=C sort -k1,1 $vcf_table) \
#<(LC_ALL=C sort -k1,1 $annovar_out_fixed) \
#> $annovar_combined
#"
#echo -e "\n CMD: $join_cmd \n"
#eval "$join_cmd"

#sleep 5


#########################


# check that join completed

#if [ ! -s "$annovar_combined" ] ; then
#	echo -e "\n $script_name ERROR: $annovar_combined IS EMPTY \n" >&2
#	exit 1
#fi


#########################


# clean up

#rm -fv "$annovar_input"
#rm -fv "$annovar_out_fixed"


#########################


# summary

#total_muts=$(cat "$annovar_combined" | grep -v 'refGene' | wc -l)
#echo "total muts: $total_muts"

#coding_muts=$(cat "$annovar_combined" | grep -v 'refGene' | grep 'exon' | wc -l)
#echo "coding muts: $coding_muts"

#nonsyn_muts=$(cat "$annovar_combined" | grep -v 'refGene' | grep -E 'nonsynonymous|stopgain|stoploss|frameshift' | wc -l)
#echo "nonsynonymous muts: $coding_muts"

# summarize log file
#echo "${summary_header}" > "$summary_csv"
#echo "${sample_clean},${total_muts},${coding_muts},${nonsyn_muts}" >> "$summary_csv"

#sleep 5

# combine all sample summaries
#cat ${summary_dir}/*.${segment_name}.csv | LC_ALL=C sort -t ',' -k1,1 | uniq > "${proj_dir}/summary.${segment_name}.csv"


#########################


# combine annotations for all samples

# all mutations
#combine_all_cmd="
#cat ${annovar_dir}/*.combined.txt \
#| LC_ALL=C sort -k1,1 -k2,2 \
#| uniq \
#> ${annovar_dir}.all.txt
#"
#echo -e "\n CMD: $combine_all_cmd \n"
#eval "$combine_all_cmd"

#sleep 1

# coding mutations
#combine_coding_cmd="
#cat ${annovar_dir}.all.txt \
#| grep -E 'refGene|exon|splicing' \
#> ${annovar_dir}.coding.txt
#"
#echo -e "\n CMD: $combine_coding_cmd \n"
#eval "$combine_coding_cmd"

#sleep 1

# consequence mutations
#combine_nonsyn_cmd="
#cat ${annovar_dir}.all.txt \
#| grep -E 'refGene|splicing|nonsynonymous|stopgain|stoploss|frameshift' \
#> ${annovar_dir}.nonsyn.txt
#"
#echo -e "\n CMD: $combine_nonsyn_cmd \n"
#eval "$combine_nonsyn_cmd"

#sleep 1


#########################



# end
