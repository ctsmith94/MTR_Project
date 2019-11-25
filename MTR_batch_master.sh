#!/bin/bash
#
# Process data to extract mean cord MTR per axial slice. This script should be run within the subject's folder.
#
# Usage:
#   ./MTR_batch_master.sh <SUBJECT> <FILEPARAM>
#
# Example:
#   ./MTR_batch_master.sh sub-03 parameters.sh
#
# Authors: Julien Cohen-Adad; C. Taylor Smith

# The following global variables are retrieved from parameters.sh but could be
# overwritten here by uncommenting:
# PATH_QC="~/qc"

# Uncomment for full verbose
#set -v

# Immediately exit if error
set -e

# Exit if user presses CTRL+C (Linux) or CMD+C (OSX)
trap "echo Caught Keyboard Interrupt within script. Exiting now.; exit" INT

# Retrieve input params
SUBJECT=$1
FILEPARAM=$2
SUBJECT=${SUBJECT##*/}
echo "$SUBJECT"


# FUNCTIONS
# ==============================================================================

# Get specific field from json file
get_field_from_json(){
  local file="$1"
  local field="$2"
  echo `grep $field $file | sed 's/[^0-9]*//g'`
}

# Check if manual segmentation already exists. If it does, copy it locally. If
# it does not, perform seg.
segment_if_does_not_exist(){
  local file="$1"
  local contrast="$2"
  # Update global variable with segmentation file name
  FILESEG="${file}_seg"
  if [ -e "${PATH_SEGMANUAL}/${FILESEG}-manual.nii.gz" ]; then
    echo "Found manual segmentation: ${PATH_SEGMANUAL}/${FILESEG}-manual.nii.gz"
    rsync -avzh "${PATH_SEGMANUAL}/${FILESEG}-manual.nii.gz" ${FILESEG}.nii.gz
    sct_qc -i ${file}.nii.gz -s ${FILESEG}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -qc-subject ${SUBJECT}
  else
    # Segment spinal cord
    sct_deepseg_sc -i ${file}.nii.gz -c $contrast -qc ${PATH_QC} -qc-subject ${SUBJECT}
  fi
}

# Check if manual label already exists. If it does, copy it locally. If it does
# not, perform labeling.
label_if_does_not_exist(){
  local file="$1"
  local file_seg="$2"
  # Update global variable with segmentation file name
  FILELABEL="${file}_labels"
  if [ -e "${PATH_SEGMANUAL}/${file}_labels-manual.nii.gz" ]; then
    echo "Found manual label: ${PATH_SEGMANUAL}/${file}_labels-manual.nii.gz"
    rsync -avzh "${PATH_SEGMANUAL}/${file}_labels-manual.nii.gz" ${FILELABEL}.nii.gz
  else
    # Generate labeled segmentation
    sct_label_vertebrae -i ${file}.nii.gz -s ${file_seg}.nii.gz -c t2
    # Create labels in the cord at C3 and C9 mid-vertebral levels
    sct_label_utils -i ${file_seg}_labeled.nii.gz -vert-body 3,9 -o ${FILELABEL}.nii.gz
  fi
}

# Check if manual segmentation already exists. If it does, copy it locally. If
# it does not, perform seg.
segment_gm_if_does_not_exist(){
  local file="$1"
  local contrast="$2"
  # Update global variable with segmentation file name
  FILESEG="${file}_gmseg"
  if [ -e "${PATH_SEGMANUAL}/${FILESEG}-manual.nii.gz" ]; then
    echo "Found manual segmentation: ${PATH_SEGMANUAL}/${FILESEG}-manual.nii.gz"
    rsync -avzh "${PATH_SEGMANUAL}/${FILESEG}-manual.nii.gz" ${FILESEG}.nii.gz
    sct_qc -i ${file}.nii.gz -s ${FILESEG}.nii.gz -p sct_deepseg_gm -qc ${PATH_QC} -qc-subject ${SUBJECT}
  else
    # Segment spinal cord
    sct_deepseg_gm -i ${file}.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
  fi
}



# SCRIPT STARTS HERE
# ==============================================================================
# Load environment variables
#source $FILEPARAM
# Go to results folder, where most of the outputs will be located
cd $PATH_RESULTS
pwd
# Copy source images
mkdir -p log
mkdir -p data
cd data
cp -r $PATH_DATA/$SUBJECT .
# Go to anat folder where all structural data are located
cd ${SUBJECT}/anat/
echo "Processing subject: ${SUBJECT}"

# T2 Segmentation and Warp to Template
# ------------------------------------------------------------------------------
file_t2="${SUBJECT}_T2w"
# Reorient to RPI and resample to 0.8mm iso (supposed to be the effective resolution)
sct_image -i ${file_t2}.nii.gz -setorient RPI -o ${file_t2}_RPI.nii.gz
sct_resample -i ${file_t2}_RPI.nii.gz -mm 0.8x0.8x0.8 -o ${file_t2}_RPI_r.nii.gz
file_t2="${file_t2}_RPI_r"
# Segment spinal cord (only if it does not exist)
segment_if_does_not_exist $file_t2 "t2"
file_t2_seg=$FILESEG
# Flatten scan along R-L direction (to make nice figures)
sct_flatten_sagittal -i ${file_t2}.nii.gz -s ${file_t2_seg}.nii.gz
# Create labels in the spinal cord at C3 and T2 mid-vertebral levels (only if it does not exist)
label_if_does_not_exist ${file_t2} ${file_t2_seg}
file_label=$FILELABEL
# Register T2 data to Template
sct_register_to_template -i ${file_t2}.nii.gz -s ${file_t2_seg}.nii.gz -l ${file_label}.nii.gz -c t2 -qc ${PATH_QC}
# MTS
# ------------------------------------------------------------------------------
file_t2w="${SUBJECT}_T2w"
file_mton="${SUBJECT}_acq-MTon_MTS"
file_mtoff="${SUBJECT}_acq-MToff_MTS"

if [[ -e "${file_t2w}.nii.gz" && -e "${file_mton}.nii.gz" && -e "${file_mtoff}.nii.gz" ]]; then
  # Fetch TR and FA from the json files
  FA_t2w=$(get_field_from_json ${file_t2w}.json FlipAngle)
  FA_mton=$(get_field_from_json ${file_mton}.json FlipAngle)
  FA_mtoff=$(get_field_from_json ${file_mtoff}.json FlipAngle)
  TR_t2w=$(get_field_from_json ${file_t2w}.json RepetitionTime)
  TR_mton=$(get_field_from_json ${file_mton}.json RepetitionTime)
  TR_mtoff=$(get_field_from_json ${file_mtoff}.json RepetitionTime)
  # Segment spinal cord (only if it does not exist)
  segment_if_does_not_exist $file_mton "t2"
  file_mton_seg=$FILESEG
  # Create mask
  sct_create_mask -i ${file_mton}.nii.gz -p centerline,${file_mton_seg}.nii.gz -size 35mm -o ${file_mton}_mask.nii.gz
  mask=${file_mton}_mask.nii.gz
  # Register MT0 to MT1
  sct_register_multimodal -i ${file_mtoff}.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=im,algo=slicereg,metric=CC -m ${mask} -x spline -qc ${PATH_QC}
  # Compute MTR
  sct_compute_mtr -mt0 ${file_mtoff}_reg.nii.gz -mt1 ${file_mton}.nii.gz -o ${SUBJECT}_mtr.nii.gz
  # Register template to MT1
  sct_register_multimodal -i $SCT_DIR/data/PAM50/template/PAM50_t2.nii.gz -iseg $SCT_DIR/data/PAM50/template/PAM50_cord.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=seg,algo=slicereg,smooth=3:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -initwarp warp_template2anat.nii.gz -initwarpinv warp_anat2template.nii.gz
  mv warp_PAM50_t22${file_mton}.nii.gz warp_template2mt1.nii.gz
  mv warp_${file_mton}2PAM50_t2.nii.gz warp_mt12template.nii.gz
  # Warp template to MT1
  sct_warp_template -d ${file_mton}.nii.gz -w warp_template2mt1.nii.gz -ofolder label_mt1 -qc ${PATH_QC}
  # Extract average MTR (per axial slice)
  sct_extract_metric -i ${SUBJECT}_mtr.nii.gz -f label_mt1/atlas -l 50 -method map -vert 2:8 -perslice 1 -vertfile label_mt1/template/PAM50_levels.nii.gz -o ${SUBJECT}MTR.csv -append 1
else
  echo "WARNING: MTS dataset is incomplete."
fi
cd ..
# Verify presence of output files and write log file if error
# ------------------------------------------------------------------------------
FILES_TO_CHECK=(
  "anat/${SUBJECT}_t2w_RPI_r_seg.nii.gz"
  "anat/${SUBJECT}_T2w_RPI_r_seg.nii.gz"
  "anat/label_mt1/template/PAM50_levels.nii.gz"
  "anat/mtr.nii.gz"
  ${SUBJECT}MTR.csv
)
for file in ${FILES_TO_CHECK[@]}; do
  if [ ! -e $file ]; then
    echo "${SUBJECT}/${file} does not exist" >> $PATH_LOG/_error_check_output_files.log
  fi
done
