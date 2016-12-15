#!/bin/bash
#$ -S /bin/bash

#######################################################################
#
#  Program:   ALOHA (Automatic Longitudinal Hippocampal Atrophy)
#  Module:    $Id: aloha_deformable.sh 100 2014-04-12 11:42:57Z srdas $
#  Language:  BASH Shell Script
#  Copyright (c) 2015 Sandhitsu R. Das, University of Pennsylvania
#  
#  This file is part of ALOHA
#
#  ALOHA is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details. 
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################

set -x -e

# Read the library
source ${ALOHA_ROOT?}/scripts/aloha_lib.sh

side=${1?}
# Existing initialization, global and deformable directory
WDINIT=$ALOHA_WORK/init
WDGLOBAL=$ALOHA_WORK/global
WDDEF=$ALOHA_WORK/deformable

# Verify all the necessary inputs
cat <<-BLOCK1
	Script: aloha_measure.sh
	Root: ${ALOHA_ROOT?}
	Working directory: ${ALOHA_WORK?}
        Initialization directory: ${WDINIT?}
        Global directory: ${WDGLOBAL?}
        Deformable directory: ${WDGLOBAL?}
        Side: ${side?}
	PATH: ${PATH?}
BLOCK1


export FSLOUTPUTTYPE=NIFTI_GZ

# Ensure directory
WDRES=$ALOHA_WORK/results

mkdir -p $WDRES
if [ -z $TMPDIR ]; then
  TMPDIR=$(tmpnam)
  rm -f $TMPDIR
  mkdir -p $TMPDIR
fi


for side in $side; do

  RESFILE=$WDRES/volumes_${side}.txt
  # Segmentations
  if [ "$side" == "left" ]; then
    ALOHA_BL_MPSEG=$ALOHA_BL_MPSEG_LEFT
    ALOHA_BL_TSESEG=$ALOHA_BL_TSESEG_LEFT
  else
    ALOHA_BL_MPSEG=$ALOHA_BL_MPSEG_RIGHT
    ALOHA_BL_TSESEG=$ALOHA_BL_TSESEG_RIGHT
  fi

  BLMPTRIM=$WDGLOBAL/blmptrim_${side}.nii.gz
  FUMPTRIM=$WDGLOBAL/fumptrim_${side}.nii.gz
  FUMPTRIMOM=$WDDEF/fumptrim_om_${side}.nii.gz
  BLMPTRIMDEF=$WDGLOBAL/blmptrimdef_${side}.nii.gz
  FUMPTRIMDEF=$WDGLOBAL/fumptrimdef_${side}.nii.gz
  FUMPTRIMOMDEF=$WDDEF/fumptrimdef_om_${side}.nii.gz
  HWTRIMDEF=$WDDEF/hwmptrimdef_${side}.nii.gz

  # Copy the segmentation
  cp $ALOHA_BL_MPSEG $TMPDIR/blseg_${side}.nii.gz
  
  # Create trimmed segmentation mask
  c3d $BLMPTRIMDEF $TMPDIR/blseg_${side}.nii.gz -interp NN -reslice-identity -o $WDRES/blmptrim_seg_${side}.nii.gz
  
  # Create a binary target for mesh processing: pad the boundary and get largest connected component
  c3d $WDRES/blmptrim_seg_${side}.nii.gz -pad 1x1x1vox 1x1x1vox 0 -comp -thresh 1 1 1 0 -o $TMPDIR/blmptrim_seg_${side}_bintarget.nii.gz

  # Take levelset and make mesh
  vtklevelset $TMPDIR/blmptrim_seg_${side}_bintarget.nii.gz $TMPDIR/blmptrim_seg_${side}.vtk 0.5

  # Warp mesh
  warpmesh $TMPDIR/blmptrim_seg_${side}.vtk $TMPDIR/blmptrim_seg_${side}_tohw.vtk $WDDEF/mprage_global_long_${side}_omRAS_half.mat
  warpmesh -w ants $TMPDIR/blmptrim_seg_${side}_tohw.vtk $TMPDIR/blmptrim_seg_${side}_warped.vtk $WDDEF/mp_antsreg3d_${side}Warp?vec.nii.gz
  warpmesh $TMPDIR/blmptrim_seg_${side}_warped.vtk $TMPDIR/blmptrim_seg_${side}_warped_to_futrim_om.vtk $WDDEF/mprage_global_long_${side}_omRAS_half.mat

  # Baseline volume
  BLVOL=$(vtkmeshvol $TMPDIR/blmptrim_seg_${side}.vtk | awk '{print $4}')
  FUVOL=$(vtkmeshvol $TMPDIR/blmptrim_seg_${side}_warped_to_futrim_om.vtk | awk '{print $4}')

  # Write to result file
  echo $BLVOL $FUVOL > $RESFILE  

done

