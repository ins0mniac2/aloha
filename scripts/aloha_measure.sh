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

set -x 

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
        Deformable directory: ${WDDEF?}
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
TMPDIR=$WDRES/debug_${side}
mkdir -p $TMPDIR


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
  echo T1HIPP,$BLVOL,$FUVOL > $RESFILE  

  if [[ $ALOHA_USE_TSE ]]; then
    rm -rf $TMPDIR/*
    
    BLTRIMDEF=$WDGLOBAL/bltrimdef_${side}.nii.gz
    HWTRIMDEF=$WDDEF/hwtrimdef_${side}.nii.gz

    # Copy the segmentation
    cp $ALOHA_BL_TSESEG $TMPDIR/blseg_${side}.nii.gz

    # Label map to describe the ROIs (possibly combinations thereof as well) over which to measure change
    # Format: Label1:ROI1,ROI2;Label2:ROI1;Label2:ROI1,ROI2,ROI4;
    P_LABELMAP="0:0;1:1;2:2;3:3;4:4;5:8;6:10;7:11;8:12;9:13;10:1,2,4;11:11,12;12:1,2,3,4,7;"
    P_LABELSTR=(BG  CA1 CA2 DG  CA3 SUB ERC  BA35 BA36 PHC  CA       PRC   T2HIPP)
#    P_LABELMAP="0:0;1:1;2:2;3:3;4:4;5:8;6:9;7:11;8:12;9:1,2,4;10:11,12;11:1,2,3,4,7;"
#    P_LABELSTR=(BG CA1  CA2 DG  CA3 SUB ERC BA35 BA36 CA      PRC      T2HIPP)
    map=($(echo $P_LABELMAP | sed -e "s/;/ /g"))
    nROI=${#map[*]}
    nl=nROI

    # Create trimmed segmentation mask
    c3d $BLTRIMDEF $TMPDIR/blseg_${side}.nii.gz -interp NN -reslice-identity \
      -o $WDRES/bltrim_seg_${side}.nii.gz
    BLSEG=$WDRES/bltrim_seg_${side}.nii.gz

    llist=($(c3d  $BLSEG $BLSEG -lstat | grep -v LabelID | awk '{print $1}'))
    LABELMAP=''
    # Map segmentation to halfway space
    for ((i=0; i < ${#llist[*]}; i++)); do 
      LABELMAP="$LABELMAP $i ${llist[i]}"
      c3d $BLTRIMDEF $BLSEG \
        -thresh ${llist[i]} ${llist[i]} 1 0  -smooth 0.24mm \
        -o $TMPDIR/label`printf %02d ${llist[i]}`_${side}.nii.gz

      c3d $HWTRIMDEF ${TMPDIR}/label`printf %02d ${llist[i]}`_${side}.nii.gz \
        -reslice-matrix $WDDEF/tse_global_long_${side}_omRAS_half_inv.mat \
        -o ${TMPDIR}/labelhw`printf %02d ${llist[i]}`_${side}.nii.gz
    done
    # Create replacement command to later create appropriate ROIs
    LIDX=0
    for ((i=0; i < ${#map[*]}; i++)); do
      imap=${map[i]}
      LOUT=${imap%:*}
      LSRC=${imap#*:}
      CMD[i]=""
      for trg in `echo $LSRC | sed -e "s/,/ /g"`; do
        CMD[i]="${CMD[i]} $trg inf"
      done
    done
    # Create segmentation in halfway space 
    c3d ${TMPDIR}/labelhw??_${side}.nii.gz -vote -o ${WDRES}/seghw_${side}.nii.gz
    # This is probably redundant TODO
    c3d ${WDRES}/seghw_${side}.nii.gz -replace $LABELMAP -o ${WDRES}/seghw_${side}.nii.gz

#***********************************
    # Measure subfields in 3D
    # For each ROI
    for ((l=0; l<nl; l++)) ; do
      if [ ${l} -eq 0 ]; then
        continue
      fi
      sf=`printf %02d $l`;
      sfi=$l
      THRESHCMD="-replace ${CMD[l]} -thresh inf inf 1 0"
      # Create ROI mask according to P_LABELMAP


      # Create a binary target for mesh processing: pad the boundary and get largest connected component
      c3d $BLSEG -pad 1x1x1vox 1x1x1vox 0 $THRESHCMD -comp -thresh 1 1 1 0 -o $TMPDIR/bltrim_seg_${sf}_${side}_bintarget.nii.gz

      # Take levelset and make mesh
      vtklevelset $TMPDIR/bltrim_seg_${sf}_${side}_bintarget.nii.gz $TMPDIR/bltrim_seg_${sf}_${side}.vtk 0.5

      # Warp mesh
      warpmesh $TMPDIR/bltrim_seg_${sf}_${side}.vtk $TMPDIR/bltrim_seg_${sf}_${side}_tohw.vtk $WDDEF/tse_global_long_${side}_omRAS_half.mat
      warpmesh -w ants $TMPDIR/bltrim_seg_${sf}_${side}_tohw.vtk $TMPDIR/bltrim_seg_${sf}_${side}_warped.vtk $WDDEF/tse_antsreg3d_${side}Warp?vec.nii.gz
      warpmesh $TMPDIR/bltrim_seg_${sf}_${side}_warped.vtk $TMPDIR/bltrim_seg_${sf}_${side}_warped_to_futrim_om.vtk $WDDEF/tse_global_long_${side}_omRAS_half.mat

      # Baseline volume
      BLVOL=$(vtkmeshvol $TMPDIR/bltrim_seg_${sf}_${side}.vtk | awk '{print $4}')
      FUVOL=$(vtkmeshvol $TMPDIR/bltrim_seg_${sf}_${side}_warped_to_futrim_om.vtk | awk '{print $4}')

      # Write to result file
      echo ${P_LABELSTR[l]}3D,$BLVOL,$FUVOL >> $RESFILE
    done



#***********************************


    # Number of slices
    zsize=`c3d $HWTRIMDEF -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;


    # For each slice
    for ((i=0; i < ${zsize}; i++)) do

:<<'NOSPLIT'
      ############### We don't need to do this, just get the segmentation sliced directly
      # Create probability map of each label on each slice
      for ((l=0; l < ${#llist[*]}; l++)); do 
        sf=`printf %02d ${llist[l]}` 
        c3d ${TMPDIR}/labelhw${sf}_${side}.nii.gz -slice z $i -o ${TMPDIR}/labelhw${sf}_${i}_${side}.nii.gz
      done
      # Vote to create segmentation for this slice
      c2d ${TMPDIR}/labelhw??_${i}_${side}.nii.gz -vote -o ${WDRES}/seghw_${side}_${i}.nii.gz
NOSPLIT
      c3d ${WDRES}/seghw_${side} -slice z $i -o ${WDRES}/seghw_${side}_${i}.nii.gz
    done

    # Initialize volumes to zero
    for ((i=0; i<nROI; i++)) ; do
      SFBL[i]=0
      SFFU[i]=0
    done

    # For each slice except first and last
    # for ((i=0; i < ${zsize}; i++)) do
    zsize=$(expr $zsize - 1)
    for ((i=1; i < ${zsize}; i++)) do


      # For each ROI
      for ((l=0; l<nl; l++)) ; do
        if [ ${l} -eq 0 ]; then
          continue
        fi
        sf=`printf %02d $l`;
        sfi=$l
        THRESHCMD="-replace ${CMD[l]} -thresh inf inf 1 0"
	# Create ROI mask according to P_LABELMAP
        c2d ${WDRES}/seghw_${side}_${i}.nii.gz $THRESHCMD \
          -o ${TMPDIR}/roilabelhw${sf}_${i}_${side}.nii.gz

        c3d ${TMPDIR}/roilabelhw${sf}_${i}_${side}.nii.gz -set-sform $WDDEF/canon.mat \
          -o ${TMPDIR}/roilabelhw${sf}_${i}_${side}_canon.nii.gz

	# Get the contour
	vtkcontour ${TMPDIR}/roilabelhw${sf}_${i}_${side}_canon.nii.gz \
          ${TMPDIR}/roilabelhw${sf}_${i}_contour_${side}.vtk 0.5
        # Is there any contour ?
        nPoints=`grep POINTS ${TMPDIR}/roilabelhw${sf}_${i}_contour_${side}.vtk | awk '{print $2}'`
        if [ $nPoints -ne 0 ]; then

          # Triangulate the contour
          contour2surf ${TMPDIR}/roilabelhw${sf}_${i}_contour_${side}.vtk \
	    ${TMPDIR}/roilabelhw${sf}_${i}_trimesh_${side}.vtk zYpq32a0.1

          # Create fake zero z warp
          c3d $WDDEF/tse_antsreg2d_${side}_${i}Warpyvec.nii.gz -dup -scale -1 -add \
            -o $WDDEF/tse_antsreg2d_${side}_${i}Warpzvec.nii.gz
          
          # Warp the mesh
          AREA_STATS=`warpmesh -w ants \
	    ${TMPDIR}/roilabelhw${sf}_${i}_trimesh_${side}.vtk ${TMPDIR}/roilabelhw${sf}_${i}_warpedtrimesh_${side}.vtk \
            $WDDEF/tse_antsreg2d_${side}_${i}Warpxvec.nii.gz \
            $WDDEF/tse_antsreg2d_${side}_${i}Warpyvec.nii.gz \
            $WDDEF/tse_antsreg2d_${side}_${i}Warpzvec.nii.gz | grep AREA_STATS`
        
          BLVOL=`echo $AREA_STATS | awk '{print $2}'`    
          FUVOL=`echo $AREA_STATS | awk '{print $3}'`

	  # Bad cases
          if [ "${BLVOL}" == "nan" -o "${FUVOL}" == "" -o "${BLVOL}" == "0" -o "${FUVOL}" == "nan" ]; then FUVOL=0; BLVOL=0; fi


          SFBL[sfi]=`echo "${SFBL[${sfi}]} + ${BLVOL}" | bc`     
          SFFU[sfi]=`echo "${SFFU[${sfi}]} + ${FUVOL}" | bc`     

        fi


      done
    done

    for ((i=1; i<nROI; i++)) ; do
      echo ${P_LABELSTR[i]},${SFBL[i]},${SFFU[i]} >> $RESFILE  
    done

  fi

done

