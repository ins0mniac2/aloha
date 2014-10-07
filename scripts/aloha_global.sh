#!/bin/bash
#$ -S /bin/bash

#######################################################################
#
#  Program:   ALOHA (Automatic Longitudinal Hippocampal Atrophy)
#  Module:    $Id: aloha_global.sh 100 2014-04-12 11:42:57Z srdas $
#  Language:  BASH Shell Script
#  Copyright (c) 2012 Paul A. Yushkevich, University of Pennsylvania
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
# Existing initialization directory
WDINIT=$ALOHA_WORK/init

# Verify all the necessary inputs
cat <<-BLOCK1
	Script: aloha_global.sh
	Root: ${ALOHA_ROOT?}
	Working directory: ${ALOHA_WORK?}
        Initialization directory: ${WDINIT?}
        Side: ${side?}
	PATH: ${PATH?}
BLOCK1


export FSLOUTPUTTYPE=NIFTI_GZ

# Ensure directory
WDGLOBAL=$ALOHA_WORK/global
mkdir -p $WDGLOBAL

# Create MPRAGE trimmed images
for side in $side; do
  if [ "$side" == "left" ]; then
    ALOHA_BL_MPSEG=$ALOHA_BL_MPSEG_LEFT
    ALOHA_BL_TSESEG=$ALOHA_BL_TSESEG_LEFT
  else
    ALOHA_BL_MPSEG=$ALOHA_BL_MPSEG_RIGHT
    ALOHA_BL_TSESEG=$ALOHA_BL_TSESEG_RIGHT
  fi
  c3d $ALOHA_BL_MPRAGE -as BL $ALOHA_FU_MPRAGE -as FU \
    $ALOHA_BL_MPSEG -trim 16mm -sdt -smooth 4mm -thresh 0 inf 1 0 -as M \
    -push BL -push M -dilate 1 ${ALOHA_REG_MASKRAD}x${ALOHA_REG_MASKRAD}x${ALOHA_REG_MASKRAD}mm \
    -trim 10mm -as SBL -o $WDGLOBAL/blmptrimdef_${side}.nii.gz \
    -push FU -push SBL -dilate 1 ${ALOHA_REG_MASKRAD}x${ALOHA_REG_MASKRAD}x${ALOHA_REG_MASKRAD}mm -reslice-matrix ${WDINIT}/mprage_long_RAS_inv.mat \
    -trim 10mm -as SFU -o $WDGLOBAL/fumptrimdef_${side}.nii.gz \
    -push SBL -push BL -int NN -reslice-identity -o $WDGLOBAL/blmptrim_${side}.nii.gz \
    -push SFU -push FU -int NN -reslice-identity -o $WDGLOBAL/fumptrim_${side}.nii.gz

# TODO Check masks are genus zero



  # Do the registration
  antsRegistration -d 3 -o [$WDGLOBAL/mprage_global_long_${side},$WDGLOBAL/mprage_global_long_${side}_resliced.nii.gz] \
    -r [$WDGLOBAL/blmptrim_${side}.nii.gz,$WDGLOBAL/fumptrim_${side}.nii.gz,1] \
    -t Translation[0.1] -f 4x2x1 -s 2x1x0 -c [1200x1200x50,1e-08,10] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[$WDGLOBAL/blmptrim_${side}.nii.gz,$WDGLOBAL/fumptrim_${side}.nii.gz,1,32,Regular,0.25] \
    -t Rigid[0.1] -f 4x2x1 -s 2x1x0 -c [1200x1200x50,1e-08,10] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[$WDGLOBAL/blmptrim_${side}.nii.gz,$WDGLOBAL/fumptrim_${side}.nii.gz,1,32,Regular,0.25] \
    -t Similarity[0.1] -f 4x2x1 -s 2x1x0 -c [1200x1200x50,1e-08,10] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[$WDGLOBAL/blmptrim_${side}.nii.gz,$WDGLOBAL/fumptrim_${side}.nii.gz,1,32,Regular,0.25] \
    -b 0

    ConvertTransformFile 3 $WDGLOBAL/mprage_global_long_${side}0GenericAffine.mat $WDGLOBAL/mprage_global_long_${side}0GenericAffine_RAS.mat --hm

    c3d $ALOHA_BL_MPRAGE $ALOHA_FU_MPRAGE -reslice-matrix $WDGLOBAL/mprage_global_long_${side}0GenericAffine_RAS.mat -o $WDGLOBAL/resliced_mprage_global_${side}.nii.gz


  if [[ $ALOHA_USE_TSE ]]; then

    # Create TSE trimmed images
    c3d $ALOHA_BL_TSE -as BL $ALOHA_FU_TSE -as FU \
      $ALOHA_BL_TSESEG -trim 16mm -sdt -smooth 4mm -thresh 0 inf 1 0 -as M \
      -push BL -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -reslice-identity \
      -trim 10mm -as SBL -o $WDGLOBAL/bltrimdef_${side}.nii.gz \
      -push FU -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -reslice-matrix ${WDINIT}/tse_long_RAS_inv.mat \
      -trim 10mm -as SFU -o $WDGLOBAL/futrimdef_${side}.nii.gz \
      -push SBL -push BL -int NN -reslice-identity -o $WDGLOBAL/bltrim_${side}.nii.gz \
      -push SFU -push FU -int NN -reslice-identity -o $WDGLOBAL/futrim_${side}.nii.gz

  fi
done

