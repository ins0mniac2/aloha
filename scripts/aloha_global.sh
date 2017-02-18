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

echo "Script: $0"

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
  BLMPTRIM=$WDGLOBAL/blmptrim_${side}.nii.gz
  FUMPTRIM=$WDGLOBAL/fumptrim_${side}.nii.gz
  BLTRIM=$WDGLOBAL/bltrim_${side}.nii.gz
  FUTRIM=$WDGLOBAL/futrim_${side}.nii.gz

  # Use the baseline segmentation and initial whole brain registration to create the trimmed T1 images
  c3d $ALOHA_BL_MPRAGE -as BL $ALOHA_FU_MPRAGE -as FU \
    $ALOHA_BL_MPSEG -trim ${ALOHA_REG_MPTRIM}mm -as M \
    -push BL -push M -dilate 1 ${ALOHA_REG_MPMASKRAD}x${ALOHA_REG_MPMASKRAD}x${ALOHA_REG_MPMASKRAD}mm \
    -trim 10mm -as SBL -o $WDGLOBAL/blmptrimdef_${side}.nii.gz \
    -push FU -push SBL -reslice-matrix ${WDINIT}/mprage_long_RAS_inv.mat \
    -trim 10mm -as SFU -o $WDGLOBAL/fumptrimdef_${side}.nii.gz \
    -push SBL -push BL -int NN -reslice-identity -o $BLMPTRIM \
    -push SFU -push FU -int NN -reslice-identity -o $FUMPTRIM

  # If if we have T2, we need to trim those as well
  if [[ $ALOHA_USE_TSE ]]; then 
    c3d $ALOHA_BL_TSE -as BL $ALOHA_FU_TSE -as FU \
      $ALOHA_BL_TSESEG -trim ${ALOHA_REG_TSETRIM}vox -as M \
      -push BL -push M -dilate 1 ${ALOHA_REG_TSEMASKRAD}x${ALOHA_REG_TSEMASKRAD}x${ALOHA_REG_TSEMASKRAD}vox \
      -trim 10mm -as SBL -o $WDGLOBAL/bltrimdef_${side}.nii.gz \
      -push FU -push SBL -reslice-matrix ${WDINIT}/tse_long_RAS_inv.mat \
      -trim 10mm -as SFU -o $WDGLOBAL/futrimdef_${side}.nii.gz \
      -push SBL -push BL -int NN -reslice-identity -o $BLTRIM \
      -push SFU -push FU -int NN -reslice-identity -o $FUTRIM
  fi


# TODO Check masks are genus zero


  #  -r [$WDGLOBAL/blmptrim_${side}.nii.gz,$WDGLOBAL/fumptrim_${side}.nii.gz,1] \

  # Create the halfway reference space for both modalities
  c3d_affine_tool -sform $FUMPTRIM  -sform $BLMPTRIM \
    -inv -mult -sqrt -sform $BLMPTRIM -mult -o $WDGLOBAL/mprage_${side}_hwspace.mat
  if [[ $ALOHA_USE_TSE ]]; then 
    c3d_affine_tool -sform $FUTRIM  -sform $BLTRIM \
      -inv -mult -sqrt -sform $BLTRIM -mult -o $WDGLOBAL/tse_${side}_hwspace.mat
  fi

  # Convert initialization matrix to ITK format
  c3d_affine_tool ${WDINIT}/mprage_long_RAS.mat -oitk ${WDINIT}/mprage_long_RAS_itk.txt

  # Do the registration
  antsRegistration -d 3 -o [$WDGLOBAL/mprage_global_long_${side},$WDGLOBAL/resliced_mprage_global_long_${side}_ants.nii.gz] \
    -r [$BLMPTRIM,$FUMPTRIM,1] \
    -t Translation[0.1] -f 4x2x1 -s 2x1x0 -c [ 1200x1200x50,1e-08,10 ] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[$BLMPTRIM,$FUMPTRIM,1,32,Regular,0.25] \
    -t Rigid[0.1] -f 4x2x1 -s 2x1x0 -c [ 1200x1200x50,1e-08,10 ] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[$BLMPTRIM,$FUMPTRIM,1,32,Regular,0.25] \
    -t Similarity[0.1] -f 4x2x1 -s 2x1x0 -c [ 1200x1200x50,1e-08,10 ] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[$BLMPTRIM,$FUMPTRIM,1,32,Regular,0.25] \
    -z 0

  if [[ $ALOHA_USE_TSE ]]; then
    antsRegistration -d 3 -o [$WDGLOBAL/tse_global_long_${side},$WDGLOBAL/resliced_tse_global_long_${side}_ants.nii.gz] \
      -r [$BLTRIM,$FUTRIM,1] \
      -t Translation[0.1] -f 4x2x1 -s 2x1x0 -c [ 1200x1200x50,1e-08,10 ] -l 1 -u 1 -w [0.0,0.995] \
      -m Mattes[$BLTRIM,$FUTRIM,1,32,Regular,0.25] \
      -t Rigid[0.1] -f 4x2x1 -s 2x1x0 -c [ 1200x1200x50,1e-08,10 ] -l 1 -u 1 -w [0.0,0.995] \
      -m Mattes[$BLTRIM,$FUTRIM,1,32,Regular,0.25] \
      -t Similarity[0.1] -f 4x2x1 -s 2x1x0 -c [ 1200x1200x50,1e-08,10 ] -l 1 -u 1 -w [0.0,0.995] \
      -m Mattes[$BLTRIM,$FUTRIM,1,32,Regular,0.25] \
      -z 0


  fi

    # Flirt initialization may not work as well as center of mass
    # -r ${WDINIT}/mprage_long_RAS_itk.txt \
    # Old version
    # -b 0

  # Convert tramsform files to RAS
  if [[ $ALOHA_USE_TSE ]]; then
    modlist=$(echo mprage tse)
  else
    modlist=$(echo mprage)
  fi
  
  for modality in $modlist; do

# :<<nocompose
 #   ConvertTransformFile 3 $WDGLOBAL/${modality}_global_long_${side}0GenericAffine.mat $WDGLOBAL/${modality}_global_long_${side}0GenericAffine_RAS.mat --hm --ras
    ConvertTransformFile 3 $WDGLOBAL/${modality}_global_long_${side}0DerivedInitialMovingTranslation.mat $WDGLOBAL/${modality}_global_long_${side}0DerivedInitialMovingTranslation_RAS.mat --hm --ras
    ConvertTransformFile 3 $WDGLOBAL/${modality}_global_long_${side}1Translation.mat $WDGLOBAL/${modality}_global_long_${side}1Translation_RAS.mat --hm --ras
    ConvertTransformFile 3 $WDGLOBAL/${modality}_global_long_${side}2Rigid.mat $WDGLOBAL/${modality}_global_long_${side}2Rigid_RAS.mat --hm --ras
    ConvertTransformFile 3 $WDGLOBAL/${modality}_global_long_${side}3Similarity.mat $WDGLOBAL/${modality}_global_long_${side}3Similarity_RAS.mat --hm --ras
    c3d_affine_tool \
      $WDGLOBAL/${modality}_global_long_${side}0DerivedInitialMovingTranslation_RAS.mat \
      $WDGLOBAL/${modality}_global_long_${side}1Translation_RAS.mat \
      $WDGLOBAL/${modality}_global_long_${side}2Rigid_RAS.mat \
      $WDGLOBAL/${modality}_global_long_${side}3Similarity_RAS.mat \
      -mult -mult -mult \
      -o $WDGLOBAL/${modality}_global_long_${side}_RAS.mat
# nocompose
  done

    # One collapsed transform
    # ConvertTransformFile 3 $WDGLOBAL/${modality}_global_long_${side}0GenericAffine.mat $WDGLOBAL/${modality}_global_long_${side}_RAS.mat --hm --ras

    # Make the resliced image
    c3d $BLMPTRIM $FUMPTRIM -reslice-matrix $WDGLOBAL/mprage_global_long_${side}_RAS.mat -o $WDGLOBAL/resliced_mprage_global_${side}.nii.gz
    if [[ $ALOHA_USE_TSE ]]; then
      c3d $BLTRIM $FUTRIM -reslice-matrix $WDGLOBAL/tse_global_long_${side}_RAS.mat -o $WDGLOBAL/resliced_tse_global_${side}.nii.gz
    fi

    # Split transform in half for unbiased processing
    c3d_affine_tool $WDGLOBAL/mprage_global_long_${side}_RAS.mat \
      -inv -o $WDGLOBAL/mprage_global_long_${side}_RAS_inv.mat \
      -sqrt -o $WDGLOBAL/mprage_global_long_${side}_RAS_halfinv.mat -inv \
      -o $WDGLOBAL/mprage_global_long_${side}_RAS_half.mat
    # Create halfway space image and reslice both images to the halfway space

    c3d $BLMPTRIM -set-sform $WDGLOBAL/mprage_${side}_hwspace.mat \
      $BLMPTRIM -reslice-matrix $WDGLOBAL/mprage_global_long_${side}_RAS_halfinv.mat \
      -o  $WDGLOBAL/mprage_${side}_hwdef.nii.gz -o $WDGLOBAL/resliced_mprage_global_${side}_bl_to_hw.nii.gz
    c3d $WDGLOBAL/mprage_${side}_hwdef.nii.gz $FUMPTRIM \
      -reslice-matrix $WDGLOBAL/mprage_global_long_${side}_RAS_half.mat \
      -o $WDGLOBAL/resliced_mprage_global_${side}_fu_to_hw.nii.gz
    if [[ $ALOHA_USE_TSE ]]; then
      # Split transform in half for unbiased processing
      c3d_affine_tool $WDGLOBAL/tse_global_long_${side}_RAS.mat \
        -inv -o $WDGLOBAL/tse_global_long_${side}_RAS_inv.mat \
        -sqrt -o $WDGLOBAL/tse_global_long_${side}_RAS_halfinv.mat -inv \
        -o $WDGLOBAL/tse_global_long_${side}_RAS_half.mat
      # Create halfway space image and reslice both images to the halfway space

      c3d $BLTRIM -set-sform $WDGLOBAL/tse_${side}_hwspace.mat \
        $BLTRIM -reslice-matrix $WDGLOBAL/tse_global_long_${side}_RAS_halfinv.mat \
        -o  $WDGLOBAL/tse_${side}_hwdef.nii.gz -o $WDGLOBAL/resliced_tse_global_${side}_bl_to_hw.nii.gz
      c3d $WDGLOBAL/tse_${side}_hwdef.nii.gz $FUTRIM \
        -reslice-matrix $WDGLOBAL/tse_global_long_${side}_RAS_half.mat \
        -o $WDGLOBAL/resliced_tse_global_${side}_fu_to_hw.nii.gz


    fi

done

