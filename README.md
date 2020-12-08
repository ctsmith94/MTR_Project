# MTR_Project
Pipeline for computing average spinal cord MTR by axial slice. Outputs a NIfTI
file of MTR as well as a CSV file with average MTR per vertebral level.

The pipeline is semi-automatic and requires to:
- manually label C2-C3 disc
- check the cord segmentation (and adjust it if necessary)


## Dependencies

- [SCT v5.0.1](https://github.com/neuropoly/spinalcordtoolbox/releases/tag/5.0.1) or above.
- [FSLeyes](https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FSLeyes) for QC and manual
correction of segmentation. Note: Another editor could be used if more convenient
(e.g. ITKsnap).


## File structure

The dataset needs to be organized according to the following BIDS structure:
```
|- PATH_DATA
   |- Sub-01
   |- Sub-02
   |- Sub-03
   |  |- anat
   |     |- Sub-03_T2w.nii.gz
   |     |- Sub-03_T2w.json
   |     |- Sub-03_acq-MToff.nii.gz
   |     |- Sub-03_acq-MToff.json
   |     |- Sub-03_acq-MTon.nii.gz
   |     |- Sub-03_acq-MTon.json
   |
   |- derivatives
      |- labels
         |- Sub-01
            |- anat
               |- Sub-01_acq-MToff_labels-disc-manual.nii.gz  <------- intervertebral disc labels
```


## How to run

- Download (or `git clone`) this repository.
- Run the processing:
  ```bash
  sct_run_batch -jobs -1 -path-data <PATH_DATA> -path-output <PATH_RESULTS> -script process_data.sh
  ```

The program will prompt to click at C2-C3 discs. The label file will be created
within the <PATH_DATA> folder, under a new directory called `derivatives/`.

The program will also prompt you to verify the segmentation, manually fix it
if necessary, and then save it (overwrite the existing file). The next time
you run the pipeline, if the manually-corrected segmentation is already present,
you will not have to edit it.

After running the pipeline across subjects, look at the QC file:
```bash
open <PATH_RESULTS>/qc/index.html
```

Specifically look at:
- the segmentation results, by entering "deepseg" in the search window.
- The co-registration between the MTon and MToff, by entering "register" in
the search window.


## Contributors

Julien Cohen-Adad; C. Taylor Smith


## License

The MIT License (MIT)

Copyright (c) 2018 École Polytechnique, Université de Montréal

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
