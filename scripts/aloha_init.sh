#!/bin/bash
#$ -S /bin/bash

#######################################################################
#
#  Program:   ALOHA (Automatic Segmentation of Hippocampal Subfields)
#  Module:    $Id: aloha_template_qsub.sh 100 2014-04-12 11:42:57Z yushkevich $
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

echo "Script: $0"
# Verify all the necessary inputs
cat <<-BLOCK1
	Script: aloha_init.sh
	Root: ${ALOHA_ROOT?}
	Working directory: ${ALOHA_WORK?}
	PATH: ${PATH?}
BLOCK1

# Alternative segmentations, deprecate this
if [ "$ALOHA_REG_SEGALT" == "orig" ]; then
  ALOHA_REG_SEGALT=""
fi

export FSLOUTPUTTYPE=NIFTI_GZ

# Ensure directory
WDINIT=$ALOHA_WORK/init
mkdir -p $WDINIT


if [ "$ALOHA_REG_INITTYPE" == "chunk" ]; then
   
  # Register T1 followup to T1 baseline
  flirt -usesqform -v -ref $ALOHA_BL_MPRAGE -in $ALOHA_FU_MPRAGE \
    -omat $WDINIT/mprage_long.mat -out $WDINIT/mprage_fu_to_bl_resliced.nii.gz -dof 9
  c3d_affine_tool -ref $ALOHA_BL_MPRAGE -src $ALOHA_FU_MPRAGE \
    ${WDINIT}/mprage_long.mat -fsl2ras -o ${WDINIT}/mprage_long_RAS.mat
  c3d_affine_tool ${WDINIT}/mprage_long_RAS.mat -inv -o ${WDINIT}/mprage_long_RAS_inv.mat
  
  # If if we have T2, we need to do more
  if [[ $ALOHA_USE_TSE ]]; then
    # Make the TSE images isotropic and extract a chunk
    c3d $ALOHA_FU_TSE -resample $ALOHA_TSE_ISO_FACTOR -region $ALOHA_TSE_ISO_REGION_CROP \
      -o ${WDINIT}/tse_fu_iso.nii.gz
    c3d $ALOHA_BL_TSE -resample $ALOHA_TSE_ISO_FACTOR -region $ALOHA_TSE_ISO_REGION_CROP \
      -o ${WDINIT}/tse_bl_iso.nii.gz

    
    c3d ${WDINIT}/tse_fu_iso.nii.gz $ALOHA_FU_MPRAGE  -reslice-identity \
      -o ${WDINIT}/mprage_to_tse_fu_iso.nii.gz
    c3d ${WDINIT}/tse_bl_iso.nii.gz $ALOHA_BL_MPRAGE  -reslice-identity \
      -o ${WDINIT}/mprage_to_tse_bl_iso.nii.gz

    # Register T1 to T2 followup and baseline pairs
    for tp in fu bl; do
      flirt -usesqform -v -in  ${WDINIT}/mprage_to_tse_${tp}_iso.nii.gz -ref ${WDINIT}/tse_${tp}_iso.nii.gz -omat ${WDINIT}/${tp}_mprage_tse.mat \
        -cost normmi -searchcost normmi -dof 6 -out ${WDINIT}/mprage_to_tse_${tp}_iso_resliced.nii.gz \
        $ALOHA_FLIRT_MULTIMODAL_OPTS
      flirt -usesqform -v -in  ${WDINIT}/mprage_to_tse_${tp}_iso.nii.gz -ref ${WDINIT}/tse_${tp}_iso.nii.gz -omat ${WDINIT}/${tp}_mprage_tse_norange.mat \
        -cost normmi -searchcost normmi -dof 6 -out ${WDINIT}/mprage_to_tse_${tp}_iso_resliced_norange.nii.gz

      # Check whether specifying search range did better or not
      MET=$(c3d_old ${WDINIT}/tse_${tp}_iso.nii.gz ${WDINIT}/mprage_to_tse_${tp}_iso_resliced.nii.gz -nmi | awk '{print int(1000*$3)}')
      METNORANGE=$(c3d_old ${WDINIT}/tse_${tp}_iso.nii.gz ${WDINIT}/mprage_to_tse_${tp}_iso_resliced_norange.nii.gz -nmi | awk '{print int(1000*$3)}')

      if [[ $MET -gt $METNORANGE ]]; then
        rm ${WDINIT}/mprage_to_tse_${tp}_iso_resliced_norange.nii.gz ${WDINIT}/${tp}_mprage_tse_norange.mat
      else
        mv ${WDINIT}/mprage_to_tse_${tp}_iso_resliced_norange.nii.gz ${WDINIT}/mprage_to_tse_${tp}_iso_resliced.nii.gz
        mv ${WDINIT}/${tp}_mprage_tse_norange.mat ${WDINIT}/${tp}_mprage_tse.mat
      fi
      c3d_affine_tool -src ${WDINIT}/mprage_to_tse_${tp}_iso.nii.gz -ref ${WDINIT}/tse_${tp}_iso.nii.gz ${WDINIT}/${tp}_mprage_tse.mat \
        -fsl2ras -o ${WDINIT}/${tp}_mprage_tse_RAS.mat
    done

    # Combine the 3 transformations above to get initial T2 longitudinal transform

    c3d_affine_tool ${WDINIT}/bl_mprage_tse_RAS.mat  \
      ${WDINIT}/mprage_long_RAS.mat ${WDINIT}/fu_mprage_tse_RAS.mat -inv -o ${WDINIT}/fu_tse_mprage_RAS.mat -mult -o ${WDINIT}/fu_tse_bl_mprage_RAS.mat \
      -mult -o ${WDINIT}/tse_long_RAS.mat
    c3d_affine_tool -ref $ALOHA_BL_TSE -src $ALOHA_FU_TSE ${WDINIT}/tse_long_RAS.mat -ras2fsl -o ${WDINIT}/tse_long.mat
    c3d_affine_tool ${WDINIT}/tse_long_RAS.mat -inv -o ${WDINIT}/tse_long_RAS_inv.mat
    c3d_affine_tool ${WDINIT}/bl_mprage_tse_RAS.mat -inv -o ${WDINIT}/bl_mprage_tse_RAS_inv.mat
    c3d_affine_tool ${WDINIT}/bl_mprage_tse_RAS.mat -oitk ${WDINIT}/bl_mprage_tse_RAS_itk.txt

    #Initial resliced image for QA
    flirt -usesqform -v -ref $ALOHA_BL_TSE  -in $ALOHA_FU_TSE -out ${WDINIT}/resliced_init_flirt.nii.gz -init ${WDINIT}/tse_long.mat -applyxfm
    c3d $ALOHA_BL_TSE  $ALOHA_FU_TSE -reslice-matrix ${WDINIT}/tse_long_RAS.mat -o ${WDINIT}/resliced_init.nii.gz


  fi

  job_progress 1.0
  bash $ALOHA_HOOK_SCRIPT \
      info "Stage 1 initialization and bookkeeping complete"

else
  echo "Unknown initialization type"
  exit -1
fi


