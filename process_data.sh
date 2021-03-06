#!/bin/bash
#
# Process data.
#
# Usage:
#   ./process_data.sh <SUBJECT>
#
# Manual segmentations or labels should be located under:
# PATH_DATA/derivatives/labels/SUBJECT/<CONTRAST>/
#
# Authors: Julien Cohen-Adad

# The following global variables are retrieved from the caller sct_run_batch
# but could be overwritten by uncommenting the lines below:
# PATH_DATA_PROCESSED="~/data_processed"
# PATH_RESULTS="~/results"
# PATH_LOG="~/log"
# PATH_QC="~/qc"

# Uncomment for full verbose
set -x

# Immediately exit if error
set -e -o pipefail

# Exit if user presses CTRL+C (Linux) or CMD+C (OSX)
trap "echo Caught Keyboard Interrupt within script. Exiting now.; exit" INT

# Retrieve input params
SUBJECT=$1

# get starting time:
start=`date +%s`


# FUNCTIONS
# ==============================================================================

# Check if manual label already exists. If it does, copy it locally. If it does
# not, perform labeling.
label_if_does_not_exist(){
  local file="$1"
  # Update global variable with segmentation file name
  FILELABELMANUAL="${PATH_DATA}/derivatives/labels/${SUBJECT}/anat/${file}labels-disc-manual.nii.gz"
  echo "Looking for manual label: $FILELABELMANUAL"
  if [[ -e $FILELABELMANUAL ]]; then
    echo "Found! Using manual labels."
  else
    echo "Not found. Proceeding with manual labeling."
    mkdir -p ${PATH_DATA}/derivatives/labels/${SUBJECT}/anat
    # Create labels at the posterior tip of the C2-C3 intervertebral disc
    sct_label_utils -i ${file}.nii.gz -create-viewer 3 -o ${FILELABELMANUAL} -msg "Click at the posterior tip of the C2-C3 intervertebral disc."
  fi
  # sct_qc -i ${file}.nii.gz -s ${FILELABELMANUAL} -p sct_label_utils -qc ${PATH_QC} -qc-subject ${SUBJECT}
}

# Check if manual segmentation already exists. If it does, copy it locally. If
# it does not, perform seg, then open FSLeyes for QC.
segment_if_does_not_exist(){
  local file="$1"
  local contrast="$2"
  # Find contrast
  if [[ $contrast == "dwi" ]]; then
    folder_contrast="dwi"
  else
    folder_contrast="anat"
  fi
  # Update global variable with segmentation file name
  FILESEG="${file}_seg"
  FILESEGMANUAL="${PATH_DATA}/derivatives/labels/${SUBJECT}/${folder_contrast}/${FILESEG}-manual.nii.gz"
  echo
  echo "Looking for manual segmentation: $FILESEGMANUAL"
  if [[ -e $FILESEGMANUAL ]]; then
    echo "Found! Using manual segmentation."
    rsync -avzh $FILESEGMANUAL ${FILESEG}.nii.gz
  else
    echo "Not found. Proceeding with automatic segmentation."
    # Segment spinal cord
    sct_deepseg_sc -i ${file}.nii.gz -c $contrast
    # Open FSLeyes
    fsleyes ${file}.nii.gz -cm greyscale ${FILESEG}.nii.gz -cm red -a 70.0
    # Copy to derivatives
    cp ${FILESEG}.nii.gz ${FILESEGMANUAL}
  fi
  sct_qc -i ${file}.nii.gz -s ${FILESEG}.nii.gz -p sct_deepseg_sc -qc ${PATH_QC} -qc-subject ${SUBJECT}
}



# SCRIPT STARTS HERE
# ==============================================================================
# Display useful info for the log, such as SCT version, RAM and CPU cores available
sct_check_dependencies -short

# Go to folder where data will be copied and processed
cd $PATH_DATA_PROCESSED
# Copy source images
rsync -avzh $PATH_DATA/$SUBJECT .
# Go to anat folder where all structural data are located
cd ${SUBJECT}/anat/

# MTS
# ------------------------------------------------------------------------------
file_mton="${SUBJECT}_acq-MTon_MTS"
file_mtoff="${SUBJECT}_acq-MToff_MTS"

if [[ -e "${file_mton}.nii.gz" && -e "${file_mtoff}.nii.gz" ]]; then
  # Label C2-C3 disc
  label_if_does_not_exist ${file_mtoff}
  # Segment spinal cord (only if it does not exist)
  segment_if_does_not_exist $file_mton "t2"
  file_mton_seg=$FILESEG
  # Create mask
  sct_create_mask -i ${file_mton}.nii.gz -p centerline,${file_mton_seg}.nii.gz -size 35mm -o ${file_mton}_mask.nii.gz
  # Crop data for faster processing
  sct_crop_image -i ${file_mton}.nii.gz -m ${file_mton}_mask.nii.gz -o ${file_mton}_crop.nii.gz
  sct_crop_image -i ${file_mton_seg}.nii.gz -m ${file_mton}_mask.nii.gz -o ${file_mton_seg}_crop.nii.gz
  file_mton="${file_mton}_crop"
  file_mton_seg="${file_mton_seg}_crop"
  # Register MToff->MTon
  # Tips: here we only use rigid transformation because both images have very similar sequence parameters. We don't want to use SyN/BSplineSyN to avoid introducing spurious deformations.
  sct_register_multimodal -i ${file_mtoff}.nii.gz -d ${file_mton}.nii.gz -dseg ${file_mton_seg}.nii.gz -param step=1,type=im,algo=rigid,slicewise=1,metric=CC -x spline -qc ${PATH_QC} -qc-subject ${SUBJECT}
  file_mtoff="${file_mtoff}_reg"
  # Register template->MTon
  sct_register_to_template -i ${file_mton}.nii.gz -s ${file_mton_seg}.nii.gz -ldisc ${FILELABELMANUAL} -ref subject -param step=1,type=seg,algo=centermassrot:step=2,type=seg,algo=bsplinesyn,metric=MeanSquares,iter=5,smooth=1,gradStep=0.5,slicewise=1 -qc ${PATH_QC} -qc-subject ${SUBJECT}
  # Warp template
  sct_warp_template -d ${file_mton}.nii.gz -w warp_template2anat.nii.gz -qc ${PATH_QC} -qc-subject ${SUBJECT}
  # Compute MTR
  sct_compute_mtr -mt0 ${file_mtoff}.nii.gz -mt1 ${file_mton}.nii.gz
  # Extract MTR, MTsat and T1 in WM between C2 and C5 vertebral levels
  sct_extract_metric -i mtr.nii.gz -l 51 -vert 2:7 -perlevel 1 -o ${PATH_RESULTS}/MTR.csv -append 1
else
  echo "WARNING: MTS dataset is incomplete."
fi

# Go back to parent folder
cd ..

# Verify presence of output files and write log file if error
# ------------------------------------------------------------------------------
FILES_TO_CHECK=(
  "anat/mtr.nii.gz"
)
for file in ${FILES_TO_CHECK[@]}; do
  if [[ ! -e $file ]]; then
    echo "${SUBJECT}/${file} does not exist" >> $PATH_LOG/_error_check_output_files.log
  fi
done

# Display useful info for the log
end=`date +%s`
runtime=$((end-start))
echo
echo "~~~"
echo "SCT version: `sct_version`"
echo "Ran on:      `uname -nsr`"
echo "Duration:    $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"
echo "~~~"
