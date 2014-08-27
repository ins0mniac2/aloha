#!/bin/bash
# usage: vacind_long_labelimage_to_lm.sh labelimagefile landmarkfile
# generates point landmark file from a label image by computing the centroid of
# each label landmark and outputs into a landmark file in Nx3 format
# splits labels, calculates centroid of each, gets the locations in mm, 
# discards background label 0, deletes delimiters and such
c3d $1 -split -foreach -centroid -endfor | grep MM | sed -e '1d' -e 's/CENTROID_MM \[//g' -e 's/\]//g' -e 's/,//g' > $2
