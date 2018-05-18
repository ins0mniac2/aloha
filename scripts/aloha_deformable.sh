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
# Existing initialization and global directory
WDINIT=$ALOHA_WORK/init
WDGLOBAL=$ALOHA_WORK/global

# Verify all the necessary inputs
cat <<-BLOCK1
	Script: aloha_deformable.sh
	Root: ${ALOHA_ROOT?}
	Working directory: ${ALOHA_WORK?}
        Initialization directory: ${WDINIT?}
        Global reg directory: ${WDGLOBAL?}
        Side: ${side?}
	PATH: ${PATH?}
BLOCK1


export FSLOUTPUTTYPE=NIFTI_GZ

# Ensure directory
WDDEF=$ALOHA_WORK/deformable
mkdir -p $WDDEF

# Create a function to generate a canonical orientation matrix
function get_canon_sform()
{
  x=$1
  y=$2
  z=$3
  echo "-${x} -0.0  -0.0 -0.0"
  echo "-0.0  -${y} -0.0 -0.0"
  echo "0.0   0.0   ${z}  0.0"
  echo "0.0   0.0   0.0   1.0"
}



# Create MPRAGE trimmed images
for side in $side; do

  # The global registration matrix
  INITMAT=$WDGLOBAL/mprage_global_long_${side}_RAS.mat
  
  BLMPTRIM=$WDGLOBAL/blmptrim_${side}.nii.gz
  FUMPTRIM=$WDGLOBAL/fumptrim_${side}.nii.gz
  FUMPTRIMOM=$WDDEF/fumptrim_om_${side}.nii.gz
  BLMPTRIMDEF=$WDGLOBAL/blmptrimdef_${side}.nii.gz
  FUMPTRIMDEF=$WDGLOBAL/fumptrimdef_${side}.nii.gz
  FUMPTRIMOMDEF=$WDDEF/fumptrimdef_om_${side}.nii.gz
  HWTRIMDEF=$WDDEF/hwmptrimdef_${side}.nii.gz


  # Make the origins of the BL and FU images the same (this will make the 
  # rigid transform between then smaller, and will minimize ANTS-related issues)
  BLORIG=($(c3d $BLMPTRIM -info-full | head -n 3 | tail -n 1 | sed -e "s/.*{\[//" -e "s/\],.*//"))
  c3d $FUMPTRIM -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm -o $FUMPTRIMOM
  c3d $FUMPTRIMDEF -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm -o $FUMPTRIMOMDEF


  # Derive the global transform matrix that takes an image that matches the origin of the followup to baseline image to the baseline
  c3d_affine_tool \
    -sform $FUMPTRIMOM \
    -sform $FUMPTRIM -inv \
    -mult $INITMAT -mult -o $WDDEF/mprage_global_long_${side}_omRAS.mat

  # Repeat the halfway space business here for the origin-matched transform
  # Take the square root of the mapping. This brings moving to half-way point
  c3d_affine_tool $WDDEF/mprage_global_long_${side}_omRAS.mat                                      -oitk $WDDEF/mprage_global_long_${side}_omRAS_itk.txt
  c3d_affine_tool $WDDEF/mprage_global_long_${side}_omRAS.mat -sqrt     -o $WDDEF/mprage_global_long_${side}_omRAS_half.mat    -oitk $WDDEF/mprage_global_long_${side}_omRAS_half_itk.txt
  c3d_affine_tool $WDDEF/mprage_global_long_${side}_omRAS_half.mat -inv -o $WDDEF/mprage_global_long_${side}_omRAS_half_inv.mat -oitk $WDDEF/mprage_global_long_${side}_omRAS_half_inv_itk.txt
  c3d_affine_tool $WDDEF/mprage_global_long_${side}_omRAS.mat -inv      -o $WDDEF/mprage_global_long_${side}_omRAS_inv.mat     -oitk $WDDEF/mprage_global_long_${side}_omRAS_inv_itk.txt

  # Create the halfway reference space
  c3d_affine_tool -sform $FUMPTRIMOM -sform $BLMPTRIM -inv -mult \
    -sqrt -sform $BLMPTRIM -mult -o $WDDEF/mprage_${side}_om_hwspace.mat

  # Make images into the halfway space
  c3d $BLMPTRIM \
    -set-sform $WDDEF/mprage_${side}_om_hwspace.mat \
    $BLMPTRIMDEF -dilate 1 20x20x20mm -reslice-matrix $WDDEF/mprage_global_long_${side}_omRAS_half_inv.mat -o $HWTRIMDEF \
    $HWTRIMDEF  $BLMPTRIM -reslice-matrix $WDDEF/mprage_global_long_${side}_omRAS_half_inv.mat -o $WDDEF/blmptrim_${side}_to_hw.nii.gz \
    $HWTRIMDEF  $FUMPTRIMOM -reslice-matrix $WDDEF/mprage_global_long_${side}_omRAS_half.mat -o $WDDEF/fumptrim_om_${side}to_hw.nii.gz 

  
    # Use mask in registration or not
    if [ "$ALOHA_REG_USEDEFMASK" == true ]; then
      maskopt="--masks [$HWTRIMDEF, $HWTRIMDEF]"
    else
      maskopt=""
    fi

  # Registration
# :<<'NOT1'
  antsRegistration --dimensionality 3 $maskopt \
    --initial-fixed-transform $WDDEF/mprage_global_long_${side}_omRAS_half_inv_itk.txt \
    --initial-moving-transform $WDDEF/mprage_global_long_${side}_omRAS_half_itk.txt \
    -o [ $WDDEF/mp_antsreg3d_${side} , ${WDDEF}/fumptrim_om_to_hw_warped_3d_${side}.nii.gz ] \
    -t SyN[ $ALOHA_REG_ASTEPSIZE , $ALOHA_REG_REGUL1 , $ALOHA_REG_REGUL2  ] \
    -m Mattes[$BLMPTRIM,$FUMPTRIMOM,1,32,Regular,0.25] \
    -c [ $ALOHA_MPRAGE_ANTS_ITER, 1e-08,10 ] \
    -s 2x1x0vox  -f 4x2x1 | tee $WDDEF/mp_ants_output_3d_${side}.txt;
 
# NOT1

  # Split the warp field for later use with mesh utilities which do not support multi-component images
  c3d -mcs $WDDEF/mp_antsreg3d_${side}1Warp.nii.gz -oo $WDDEF/mp_antsreg3d_${side}Warpxvec.nii.gz  $WDDEF/mp_antsreg3d_${side}Warpyvec.nii.gz  $WDDEF/mp_antsreg3d_${side}Warpzvec.nii.gz


  if [[ $ALOHA_USE_TSE ]]; then
    # The global registration matrix
    INITMAT=$WDGLOBAL/tse_global_long_${side}_RAS.mat
  
    BLTRIM=$WDGLOBAL/bltrim_${side}.nii.gz
    FUTRIM=$WDGLOBAL/futrim_${side}.nii.gz
    FUTRIMOM=$WDDEF/futrim_om_${side}.nii.gz
    BLTRIMDEF=$WDGLOBAL/bltrimdef_${side}.nii.gz
    FUTRIMDEF=$WDGLOBAL/futrimdef_${side}.nii.gz
    FUTRIMOMDEF=$WDDEF/futrimdef_om_${side}.nii.gz
    HWTRIMDEF=$WDDEF/hwtrimdef_${side}.nii.gz


    # Make the origins of the BL and FU images the same (this will make the 
    # rigid transform between then smaller, and will minimize ANTS-related issues)
    BLORIG=($(c3d $BLTRIM -info-full | head -n 3 | tail -n 1 | sed -e "s/.*{\[//" -e "s/\],.*//"))
    c3d $FUTRIM -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm -o $FUTRIMOM
    c3d $FUTRIMDEF -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm -o $FUTRIMOMDEF


    # Derive the global transform matrix that takes an image that matches the origin of the followup to baseline image to the baseline
    c3d_affine_tool \
      -sform $FUTRIMOM \
      -sform $FUTRIM -inv \
      -mult $INITMAT -mult -o $WDDEF/tse_global_long_${side}_omRAS.mat

    # Repeat the halfway space business here for the origin-matched transform
    # Take the square root of the mapping. This brings moving to half-way point
    c3d_affine_tool $WDDEF/tse_global_long_${side}_omRAS.mat                                      -oitk $WDDEF/tse_global_long_${side}_omRAS_itk.txt
    c3d_affine_tool $WDDEF/tse_global_long_${side}_omRAS.mat -sqrt     -o $WDDEF/tse_global_long_${side}_omRAS_half.mat    -oitk $WDDEF/tse_global_long_${side}_omRAS_half_itk.txt
    c3d_affine_tool $WDDEF/tse_global_long_${side}_omRAS_half.mat -inv -o $WDDEF/tse_global_long_${side}_omRAS_half_inv.mat -oitk $WDDEF/tse_global_long_${side}_omRAS_half_inv_itk.txt
    c3d_affine_tool $WDDEF/tse_global_long_${side}_omRAS.mat -inv      -o $WDDEF/tse_global_long_${side}_omRAS_inv.mat     -oitk $WDDEF/tse_global_long_${side}_omRAS_inv_itk.txt

    # Create the halfway reference space
    c3d_affine_tool -sform $FUTRIMOM -sform $BLTRIM -inv -mult \
      -sqrt -sform $BLTRIM -mult -o $WDDEF/tse_${side}_om_hwspace.mat

    # Make images into the halfway space
    c3d $BLTRIM \
      -set-sform $WDDEF/tse_${side}_om_hwspace.mat \
      $BLTRIMDEF -dilate 1 20x20x20mm -reslice-matrix $WDDEF/tse_global_long_${side}_omRAS_half_inv.mat -o $HWTRIMDEF \
      $HWTRIMDEF  $BLTRIM -reslice-matrix $WDDEF/tse_global_long_${side}_omRAS_half_inv.mat -o $WDDEF/bltrim_${side}_to_hw.nii.gz \
      $HWTRIMDEF  $FUTRIMOM -reslice-matrix $WDDEF/tse_global_long_${side}_omRAS_half.mat -o $WDDEF/futrim_om_${side}_to_hw.nii.gz 

  
    # Use mask in registration or not
    if [ "$ALOHA_REG_USEDEFMASK" == true ]; then
      maskopt="--masks [$HWTRIMDEF, $HWTRIMDEF]"
    else
      maskopt=""
    fi
    # Registration
# :<<'NO3D'
    # Also run the 3D registration
    antsRegistration --dimensionality 3 $maskopt \
      --initial-fixed-transform $WDDEF/tse_global_long_${side}_omRAS_half_inv_itk.txt \
      --initial-moving-transform $WDDEF/tse_global_long_${side}_omRAS_half_itk.txt \
      -o [ $WDDEF/tse_antsreg3d_${side} , ${WDDEF}/futrim_om_to_hw_warped_3d_${side}.nii.gz ] \
      -t SyN[ $ALOHA_REG_ASTEPSIZE , $ALOHA_REG_REGUL1 , $ALOHA_REG_REGUL2  ] \
      -m Mattes[$BLTRIM,$FUTRIMOM,1,32,Regular,0.25] \
      -c [ $ALOHA_MPRAGE_ANTS_ITER, 1e-08,10 ] \
      -s 2x1x0vox  -f 4x2x1 | tee $WDDEF/tse_ants_output_3d_${side}.txt;
 
    # Run the 3D resgistration without origin match, to use for pointwise atrophy analysis
    c3d_affine_tool $WDGLOBAL/tse_global_long_${side}_RAS_half.mat -oitk $WDGLOBAL/tse_global_long_${side}_RAS_half_itk.txt
    c3d_affine_tool $WDGLOBAL/tse_global_long_${side}_RAS_halfinv.mat -oitk $WDGLOBAL/tse_global_long_${side}_RAS_halfinv_itk.txt
    antsRegistration --dimensionality 3 $maskopt \
      --initial-fixed-transform $WDGLOBAL/tse_global_long_${side}_RAS_halfinv_itk.txt \
      --initial-moving-transform $WDGLOBAL/tse_global_long_${side}_RAS_half_itk.txt \
      -o [ $WDDEF/tse_antsreg3d_${side}_noom , ${WDDEF}/futrim_to_hw_warped_3d_${side}_noom.nii.gz ] \
      -t SyN[ $ALOHA_REG_ASTEPSIZE , $ALOHA_REG_REGUL1 , $ALOHA_REG_REGUL2  ] \
      -m Mattes[$BLTRIM,$FUTRIM,1,32,Regular,0.25] \
      -c [ $ALOHA_MPRAGE_ANTS_ITER, 1e-08,10 ] \
      -s 2x1x0vox  -f 4x2x1 | tee $WDDEF/tse_ants_output_3d_${side}_noom.txt;
 
    # Split the warp field for later use with mesh utilities which do not support multi-component images
    c3d -mcs $WDDEF/tse_antsreg3d_${side}1Warp.nii.gz -oo $WDDEF/tse_antsreg3d_${side}Warpxvec.nii.gz  $WDDEF/tse_antsreg3d_${side}Warpyvec.nii.gz  $WDDEF/tse_antsreg3d_${side}Warpzvec.nii.gz

# NO3D

# :<<MAKE2D
    # How many slices ?
    zsize=`c3d $HWTRIMDEF -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
    for ((i=0; i < ${zsize}; i++)); do
      c3d $HWTRIMDEF -slice z $i -o $WDDEF/hwtrimdef_${side}_${i}.nii.gz
      c3d $WDDEF/bltrim_${side}_to_hw.nii.gz -slice z $i -o $WDDEF/bltrim_${side}_to_hw_${i}.nii.gz
      c3d $WDDEF/futrim_om_${side}_to_hw.nii.gz -slice z $i -o $WDDEF/futrim_om_${side}_to_hw_${i}.nii.gz

      # Set canonical orientation
      voxsize=$(c3d $HWTRIMDEF -info | cut -f 3 -d ";" | cut -f 2 -d "=" | sed -e 's/\[//g' | sed -e 's/\]//g')
      xvox=$(echo $voxsize | cut -f 1 -d ",")
      yvox=$(echo $voxsize | cut -f 2 -d ",")
      zvox=$(echo $voxsize | cut -f 3 -d ",")

      get_canon_sform ${xvox} ${yvox} 1.0 > $WDDEF/canon.mat
      
      c3d $WDDEF/futrim_om_${side}_to_hw_${i}.nii.gz -set-sform $WDDEF/canon.mat \
        -o $WDDEF/futrim_om_${side}_to_hw_${i}_canon.nii.gz
      c3d $WDDEF/bltrim_${side}_to_hw_${i}.nii.gz -set-sform $WDDEF/canon.mat \
        -o $WDDEF/bltrim_${side}_to_hw_${i}_canon.nii.gz

      # c3d $WDDEF/hwtrimdef_${side}_${i}.nii.gz  -orient RIA -o $WDDEF/hwtrimdef_${side}_${i}.nii.gz
      antsRegistration --dimensionality 2 $maskopt \
        -o [ $WDDEF/tse_antsreg2d_${side}_${i}, ${WDDEF}/futrim_om_to_hw_warped_2d_${side}_${i}.nii.gz ] \
        -t SyN[ $ALOHA_REG_ASTEPSIZE , $ALOHA_REG_REGUL1 , $ALOHA_REG_REGUL2 ] \
        -m Mattes[$WDDEF/bltrim_${side}_to_hw_${i}_canon.nii.gz,$WDDEF/futrim_om_${side}_to_hw_${i}_canon.nii.gz,1,32,Regular,0.25] \
        -c [ $ALOHA_TSE_ANTS_ITER, 1e-08,10 ] \
        -s 2x1x0vox  -f 4x2x1 | tee $WDDEF/tse_ants_output_2d_${side}_${i}.txt

      # TODO handle properly. This is a terrible hack. When one image is empty like at the boundary slices, ANTS bails out with NaNs in energy
      # without any warning. If this happens warp files are not generated. So generate fake zero warp files
      if [ ! -f $WDDEF/tse_antsreg2d_${side}_${i}0Warp.nii.gz ]; then
      c3d $WDDEF/bltrim_${side}_to_hw_${i}_canon.nii.gz -dup -scale -1 -add -dup \
        -omc $WDDEF/tse_antsreg2d_${side}_${i}0Warp.nii.gz \
        -omc $WDDEF/tse_antsreg2d_${side}_${i}0InverseWarp.nii.gz
      fi


      # Try greedy
:<<'NOGREEDY'
      ~pauly/bin/greedy -d 2 \
        -i $WDDEF/bltrim_${side}_to_hw_${i}.nii.gz $WDDEF/futrim_om_${side}_to_hw_${i}.nii.gz \
        -m NCC 2x2 -o $WDDEF/tse_greedyreg2d_${side}_${i}.nii.gz -n 20x20 -wp 0.0001
    
      # Warped image from greedy
      ~pauly/bin/greedy -d 2 \
        -rf $WDDEF/bltrim_${side}_to_hw_${i}.nii.gz \
        -rm $WDDEF/futrim_om_${side}_to_hw_${i}.nii.gz \
        $WDDEF/futrim_om_to_hw_greedywarped_2d_left_${i}.nii.gz \
        -r $WDDEF/tse_greedyreg2d_${side}_${i}.nii.gz

      # Fix matrix
# :<<'NOMAT'
      c3d $WDDEF/hwtrimdef_${side}_${i}.nii.gz \
        ${WDDEF}/futrim_om_to_hw_warped_2d_${side}_${i}.nii.gz -copy-transform \
        -o ${WDDEF}/futrim_om_to_hw_warped_2d_${side}_${i}_vis.nii.gz
      c3d $WDDEF/hwtrimdef_${side}_${i}.nii.gz \
        ${WDDEF}/futrim_om_to_hw_greedywarped_2d_${side}_${i}.nii.gz -copy-transform \
        -o ${WDDEF}/futrim_om_to_hw_greedywarped_2d_${side}_${i}_vis.nii.gz
NOGREEDY

      for fn in $WDDEF/tse_antsreg2d_${side}_${i}0Warp.nii.gz $WDDEF/tse_antsreg2d_${side}_${i}0InverseWarp.nii.gz ; do
      # $WDDEF/tse_greedyreg2d_${side}_${i}.nii.gz; do
        c3d $WDDEF/hwtrimdef_${side}_${i}.nii.gz -popas A -mcs $fn \
          -foreach -insert A 1 -copy-transform -endfor \
          -omc ${fn%.nii.gz}_vis.nii.gz
      done

# NOMAT
      echo "Registration for slice $i is done"
  
      # Split the warp field for later use with mesh utilities which do not support multi-component images
      c2d -mcs $WDDEF/tse_antsreg2d_${side}_${i}0Warp.nii.gz \
        -oo $WDDEF/tse_antsreg2d_${side}_${i}Warpxvec.nii.gz \
        $WDDEF/tse_antsreg2d_${side}_${i}Warpyvec.nii.gz 

      c2d -mcs $WDDEF/tse_antsreg2d_${side}_${i}0InverseWarp.nii.gz \
        -oo $WDDEF/tse_antsreg2d_${side}_${i}InverseWarpxvec.nii.gz \
        $WDDEF/tse_antsreg2d_${side}_${i}InverseWarpyvec.nii.gz 

      for fn in $WDDEF/tse_antsreg2d_${side}_${i}*Warp?vec.nii.gz ; do
        c3d $WDDEF/hwtrimdef_${side}_${i}.nii.gz -popas A -mcs $fn \
          -foreach -insert A 1 -copy-transform -endfor \
          -omc ${fn%.nii.gz}_vis.nii.gz
      done
    done
    
# MAKE2D
 fi

done

job_progress 0.75
  bash $ALOHA_HOOK_SCRIPT \
      info "Stage 3 ${side} deformable registration complete"

