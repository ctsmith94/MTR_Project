#!/bin/bash
#
# This is a wrapper to processing scripts, that loops across subjects.
#
# Usage:
#   ./run_process.sh <script>
#
# Example:
#   ./run_process.sh prepare_data.sh
#
# Note:
#   Make sure to edit the file parameters.sh with the proper list of subjects and variable.
#
# NB: add the flag "-x" after "!/bin/bash" for full verbose of commands.
# Julien Cohen-Adad 2018-05-07; C. Taylor Smith 11/25/19


# Load parameters
source parameters.sh

# build syntax for process execution
PATH_PROCESS=`pwd`/$1
echo ${PATH_DATA[@]}
# Loop across subjects
for subject in ${SUBJECT[@]}; do
  # Display stuff
  echo "Processing subject: ${subject}"
  # run process
  $PATH_PROCESS ${subject}
done
