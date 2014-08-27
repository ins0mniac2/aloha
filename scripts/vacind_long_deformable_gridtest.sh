#!/bin/bash 
#$ -S /bin/bash

################################################################
# Penn Hippocampus Atlas: Intensity-Based Normalization Script #
################################################################

# Usage function
function usage()
{
  cat <<-USAGETEXT
pmatas_ibn_long: penn hippo atlas longitudinal analysis script
usage:
pmatas_ibn_long [options]
      required options:
      -b image          Filename of baseline grayscale image
      -c image          Filename of baseline reference space image
      -f image          Filename of followup grayscale image
      -g image          Filename of followup reference space image
      -s image          Filename of hippocampus segmentation in baseline
      -t mesh           Filename of tetrahedral mesh fitted to segmentation
      -n string         Naming prefix for all files generated

      optional:
      -w                Working directory (default /tmp/pmatlas_XXXXXX)
      -d                Enable debugging
      -i                How many iterations of ANTS to run (default=60)
      -a globalmat      initial global transform in matrix format
      -q dim            type of deformable registration (def:3, else 2 or 2.5)
      -m                Use fixed image mask 
      -o                Don't use origin equalization
      -r superres       Superresolution sampling for 2D registration, e.g. 600x600%
      -e modality       Modality -- MPRAGE or TSE
	USAGETEXT
}

function get_identity_transform()
{
  echo "1 0 0 0"
  echo "0 1 0 0"
  echo "0 0 1 0"
  echo "0 0 0 1"
}

function get_2didentity_transform_itk()
{
  echo "#Insight Transform File V1.0"
  echo "# Transform 0"
  echo "Transform: MatrixOffsetTransformBase_double_2_2"
  echo "Parameters: 1 0 0 1 0 0"
  echo "FixedParameters: 0 0"
}

function setup_irtk()
{
  # Set up the parameter file to more or less match ANTS
  cat > ${WDIR}/irtk/nreg.param <<-PARMFILE
# Non-rigid registration parameters
Lambda1                           = 0
Lambda2                           = 0
Lambda3                           = 0
Control point spacing in X        = 4.8
Control point spacing in Y        = 4.8
Control point spacing in Z        = 1.6
Subdivision                       = True

# Registration parameters
No. of resolution levels          = 1
No. of bins                       = 64
Epsilon                           = 0.0001
Padding value                     = -32768
Similarity measure                = NMI
Interpolation mode                = Linear
Optimization method               = GradientDescent

# Registration parameters for resolution level 1
Resolution level                  = 1
Target blurring (in mm)           = 0.6
Target resolution (in mm)         = ${NATIVERES}
Source blurring (in mm)           = 0.6
Source resolution (in mm)         = ${NATIVERES}
No. of iterations                 = 10
No. of steps                      = 4
Length of steps                   = 0.736945 
PARMFILE


}


# Read the options
while getopts "b:c:e:f:g:w:s:t:n:r:a:q:i:mdho" opt; do
  case $opt in

    b) TP0=$OPTARG;;
    c) DTP0=$OPTARG;;
    e) MODALITY=$OPTARG;;
    f) TP1=$OPTARG;;
    g) DTP1=$OPTARG;;
    t) TET=$OPTARG;;
    r) ANTSRESAMPLE=$OPTARG;;
    s) SEG=$OPTARG;;
    w) WDIR=$OPTARG;;
    n) PREFIX=$OPTARG;;
    a) INITMAT=$OPTARG;;
    q) REGDIM=$OPTARG;;
    i) ANTSITER=$OPTARG;;
    d) set -x -e;;
    h) usage ;;
    m) DEFMASK=1 ;;
    o) NOORIGINMATCH=1 ;;
    \?)
      exit -1;
      ;;
    :)
      echo "Option $OPTARG requires an argument";
      exit -1;
      ;;
  esac
done

# ANTS is the default registration program
echo "Deformable registration using ${DEFREGPROG?}"
BIN_ANTS=~srdas/bin/ants_avants
BIN_IRTK=~pauly/bin/itk

# Check the existence of image files
if [[ -z $TP0 || ! -f $TP0 ]]; then
  echo "Baseline image is missing"
  exit -1;
elif [[ -z $TP1 || ! -f $TP1 ]]; then
  echo "Followup image is missing"
  exit -1;
elif [[ -z $DTP0 || ! -f $DTP0 ]]; then
  echo "Baseline refspace image is missing"
  exit -1;
elif [[ -z $DTP1 || ! -f $DTP1 ]]; then
  echo "Followup refspace image is missing"
  exit -1;
elif [[ -z $SEG || ! -f $SEG ]]; then
  echo "Baseline segmentation image is missing"
  exit -1;
#elif [[ -z $TET || ! -f $TET ]]; then
#  echo "Baseline tetrahedron mesh is missing"
#  exit -1;
elif [[ -z $PREFIX ]]; then
  echo "No prefix specified, use -n option"
  exit -1;
fi

# Create a working directory for this registration
if [ -z $WDIR ]; then
  WDIR="/tmp/`tempfile pmatlas_XXXXXX`"
fi
mkdir -p $WDIR


# Initialization required ?
if [ -z $INITMAT ]; then
  get_identity_transform > $WDIR/identity.mat
  INITMAT=$WDIR/identity.mat
fi

# 2, 2.5 or 3 D registration ?
if [ -z $REGDIM ]; then
  REGDIM=3
else
  REGDIM=$REGDIM
fi

# Modality ?
if [ -z $MODALITY ]; then
  MODALITY=TSE
else
  MODALITY=$MODALITY
fi

# Superesolution sampling or not
if [ -z $ANTSRESAMPLE ]; then
  SUPERRES=""
else
  SUPERRES=" -resample $ANTSRESAMPLE"
fi


if [ -z $NOORIGINMATCH ]; then
  cp $INITMAT $WDIR/wbRAS.mat
  c3d_affine_tool $WDIR/wbRAS.mat -inv -o $WDIR/wbRAS_inv.mat
else
  cp $INITMAT $WDIR/omRAS.mat
fi

# This whole section is now done before global registration
:<<'TRIM'
# Create small images in baseline and followup image spaces copy this code to global registration script
c3d $TP0 -as BL $TP1 -as FU \
  $SEG -trim 16mm -sdt -smooth 4mm -thresh 0 inf 1 0 -as M \
  -push BL -push M -dilate 1 3x3x3mm -reslice-identity -trim 10mm -as SBL -o $WDIR/bltrimdef.nii.gz \
  -push FU -push M -dilate 1 3x3x3mm -reslice-matrix $WDIR/wbRAS_inv.mat -trim 10mm -as SFU -o $WDIR/futrimdef.nii.gz \
  -push SBL -push BL -int NN -reslice-identity -o $WDIR/bltrim.nii.gz \
  -push SFU -push FU -int NN -reslice-identity -o $WDIR/futrim.nii.gz 


# Check if mask contains the whole segmentation
maxdiff=`c3d  $SEG -trim 16mm -thresh 1 inf 1 0 -as M $WDIR/../bltrimdef.nii.gz -push M -reslice-identity \
   -trim 10mm -binarize -scale -1 \
  -add -info-full   | grep "Intensity Range" | sed -e 's/]//g' | awk -F ',' {'print $2'}`
if [ $maxdiff -lt 0 ]; then 
  echo "mask doesn't contain the whole segmentation"
  exit -1;
fi

# Check if mask is genus zero
c3d $WDIR/../bltrimdef.nii.gz -connected-components -threshold 1 1 1 0 -dilate 1 2x2x2vox  -pad 1x1x1vox 1x1x1vox 0 \
  -o $WDIR/padded.nii.gz
genus=`CheckTopology $WDIR/padded.nii.gz | tail -1 | awk {'print $2'}`
if [ $genus != 0 ]; then
  echo "mask is not a sphere"
  exit -1;
fi
rm -f $WDIR/padded.nii.gz


TRIM

# -------------------------- work for deformable registration starts here ----------------------------------

ln -sf $TP1 $WDIR/futrim.nii.gz 
ln -sf $TP0 $WDIR/bltrim.nii.gz 
ln -sf $DTP0 $WDIR/bltrimdef.nii.gz 
ln -sf $DTP1 $WDIR/futrimdef.nii.gz 


# Make the origins of the BL and FU images the same (this will make the 
# rigid transform between then smaller, and will minimize ANTS-related issues)
BLORIG=($(c3d $WDIR/bltrim.nii.gz -info-full | head -n 3 | tail -n 1 | sed -e "s/.*{\[//" -e "s/\],.*//"))
c3d $WDIR/futrim.nii.gz -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm -o $WDIR/futrim_om.nii.gz


# Recompute the transformation between the images


if [ -z $NOORIGINMATCH ]; then
  c3d_affine_tool \
    -sform $WDIR/futrim_om.nii.gz \
    -sform $WDIR/futrim.nii.gz -inv \
    -mult $WDIR/wbRAS.mat -mult -o $WDIR/omRAS.mat
fi

# Why the following is wrong ? TODO
#c3d_affine_tool \
#  $WDIR/wbRAS.mat \
#  -sform $WDIR/futrim.nii.gz \
#  -sform $WDIR/futrim_om.nii.gz -inv \
#  -mult -mult -o $WDIR/omRAS.mat
#  For any fixed image F, suppose we know the transform T1, between moving image M1 and F.
#  Now, we have another moving image M2 which is the same as M1, except in a different physical space, related to
#  M1 by a rigid transformation.
#  And we want to find the transform T2, between moving image M2 and F.
#  Voxel V in fixed image F should have its image at the same voxel locations in both moving images M1 and M2.
#  Thus, we write, equating the two voxel locations of the image points:
#  inv(sform(M1)) * T1 * sform(F) *V = inv(sform(M2)) * T2 * sform(F) *V
#  Or
#  T2 = sform(M2) * inv(sform(M1)) * T1
   

# Take the square root of the mapping. This brings moving to half-way point
c3d_affine_tool $WDIR/omRAS.mat                                      -oitk $WDIR/omRAS_itk.txt
c3d_affine_tool $WDIR/omRAS.mat -sqrt     -o $WDIR/omRAS_half.mat    -oitk $WDIR/omRAS_half_itk.txt
c3d_affine_tool $WDIR/omRAS_half.mat -inv -o $WDIR/omRAS_halfinv.mat -oitk $WDIR/omRAS_half_inv_itk.txt
c3d_affine_tool $WDIR/omRAS.mat -inv      -o $WDIR/omRAS_inv.mat     -oitk $WDIR/omRAS_inv_itk.txt

# Create the halfway reference space
c3d_affine_tool -sform $WDIR/futrim_om.nii.gz -sform $WDIR/bltrim.nii.gz -inv -mult -sqrt -sform $WDIR/bltrim.nii.gz -mult -o $WDIR/hwtrimspace.mat
# resample to neutral space - incorporates initialization and subsequent flirt between T2 images
# generate trimmed images
c3d $WDIR/bltrim.nii.gz \
  -o $WDIR/bltrim.mha \
  -set-sform $WDIR/hwtrimspace.mat \
  $WDIR/bltrimdef.nii.gz -dilate 1 5x5x5mm -reslice-matrix $WDIR/omRAS_halfinv.mat -trim 10mm -o $WDIR/hwtrimdef.nii.gz \
  -o $WDIR/hwtrimdef.mha \
  $WDIR/hwtrimdef.nii.gz  $WDIR/bltrim.nii.gz -reslice-matrix $WDIR/omRAS_halfinv.mat -o $WDIR/bltrim_to_hw.nii.gz \
  -o $WDIR/bltrim_to_hw.mha \
  $WDIR/hwtrimdef.nii.gz  $WDIR/futrim_om.nii.gz -reslice-matrix $WDIR/omRAS_half.mat -o $WDIR/futrim_om_to_hw.nii.gz \
  -o $WDIR/futrim_om_to_hw.mha

rm -f $WDIR/bltrim.mha  $WDIR/hwtrimdef.mha $WDIR/bltrim_to_hw.mha $WDIR/futrim_om_to_hw.mha

# Check if halfway mask contains the whole segmentation
maxdiff=`c3d  $SEG -trim 16mm -thresh 1 inf 1 0 -as M $WDIR/hwtrimdef.nii.gz -push M -reslice-matrix \
  $WDIR/omRAS_halfinv.mat -trim 10mm -binarize -scale -1 \
  -add -info-full   | grep "Intensity Range" | sed -e 's/]//g' | awk -F ',' {'print $2'}`
if [ $maxdiff -lt 0 ]; then
  echo "halfway mask doesn't contain the whole segmentation"
  exit -1;
fi
# Check if halfway mask is genus zero
c3d $WDIR/hwtrimdef.nii.gz -connected-components -threshold 1 1 1 0 -dilate 1 2x2x2vox  -pad 1x1x1vox 1x1x1vox 0 \
  -o $WDIR/padded.nii.gz
genus=`CheckTopology $WDIR/padded.nii.gz | tail -1 | awk {'print $2'}`
if [ $genus != 0 ]; then
  echo "halfway mask is not a sphere"
  exit -1;
fi
rm -f $WDIR/padded.nii.gz


# ANTSITER=0
# Run ANTS over the masked region (if there are more than 0 iterations)
mkdir -p $WDIR/ants
# mkdir -p $WDIR/irtk
# mkdir -p $WDIR/of
if [[ ${ANTSITER=100} > 0 ]]; then

  if [ -z $REGUL1 ]; then
    if [ "$MODALITY" == "TSE" ]; then
      REGUL="0.8,0.2"
    else
      REGUL="2.0,0.5"
    fi
  else
    REGUL="${REGUL1},${REGUL2}"
  fi


  if [ ${RIGIDMODE?} = "BL" ]; then

      

    # Run one of three different kinds of deformable registration
    case $REGDIM in  
      "3")  echo "performing 3D deformable registration";
           
            ANTSITER=50x50x100;
            #ANTSITER=100;

            # Use mask or not
            if [ -z $DEFMASK ]; then
              maskopt=""
            else
              maskopt="-x $WDIR/bltrimdef.nii.gz"
            fi
            
            c3d $WDIR/bltrim.nii.gz $WDIR/futrim_om.nii.gz -reslice-itk $WDIR/omRAS_itk.txt -o $WDIR/futrim_om_resliced_to_bltrim.nii.gz
            if [ ${DEFREGPROG} = "ants" ]; then
                rm -f $WDIR/ants/ants_output_3d.txt
                # Execute ANTS with special function
                $BIN_ANTS/ANTS 3 $maskopt  \
                  -m PR[$WDIR/bltrim.nii.gz,$WDIR/futrim_om_resliced_to_bltrim.nii.gz,1,4] \
                  -o $WDIR/ants/antsreg3d.nii.gz \
                  -i $ANTSITER \
                  -v -t SyN[${ASTEPSIZE?}] -r $REGUL \
                  --continue-affine false | tee $WDIR/ants/ants_output_3d.txt;
            elif [ ${DEFREGPROG} = "irtk" ]; then
                # Get the native resolution
                NATIVERES=$(c3d $WDIR/bltrim_to_hw.nii.gz -info-full | grep "Voxel Spacing" | sed -e "s/.*\[//" -e "s/,//g" -e "s/\]//");
                setup_irtk;
                $BIN_IRTK/nreg $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw.nii.gz \
                  -parin $WDIR/irtk/nreg.param \
                  -dofout $WDIR/irtk/nreg_3d.dof -parout $WDIR/irtk/nreg_out.param | tee $WDIR/irtk/irtk_output_3d.txt;
                # Extract the warps as images
                $BIN_IRTK/dof2image $WDIR/hwtrimdef.nii.gz $WDIR/irtk/nreg_3d.dof \
                  $WDIR/irtk/irtkreg3dWarpxvec.nii.gz \
                  $WDIR/irtk/irtkreg3dWarpyvec.nii.gz \
                  $WDIR/irtk/irtkreg3dWarpzvec.nii.gz;
            else
                echo "Unknown deformable registration program";
                exit -1;
            fi

        

            # Warp followup to baseline
            $BIN_ANTS/WarpImageMultiTransform 3 $WDIR/futrim_om.nii.gz $WDIR/futrim_om_to_bltrim_warped_3d.nii.gz \
              -R $WDIR/bltrimdef.nii.gz  $WDIR/${DEFREGPROG}/${DEFREGPROG}reg3dWarp.nii.gz $WDIR/omRAS_itk.txt;
            c3d $WDIR/${DEFREGPROG}/${DEFREGPROG}reg3dWarp?vec.nii.gz -omc 3 $WDIR/${DEFREGPROG}/${DEFREGPROG}reg3dWarp.mha;
            c3d $WDIR/bltrim.nii.gz $WDIR/futrim_om_resliced_to_bltrim.nii.gz  -scale -1 -add -o $WDIR/regdiffbefore_3d.nii.gz
            c3d $WDIR/bltrim.nii.gz $WDIR/futrim_om_to_hw_warped_3d.nii.gz -histmatch 3 \
              $WDIR/bltrim.nii.gz -scale -1 -add -o $WDIR/regdiffafter_3d.nii.gz 
            echo before `c3d $WDIR/bltrim.nii.gz $WDIR/futrim_om_resliced_to_bltrim.nii.gz -ncor` > $WDIR/regncor_3d.txt 
            echo after `c3d $WDIR/bltrim.nii.gz $WDIR/futrim_om_to_bltrim_warped_3d.nii.gz -ncor` >> $WDIR/regncor_3d.txt 
            ;;
      "2.5")  echo "performing 2.5D deformable registration, restrict deformation in z******RIGIDMODE BL not implemented****";
            ANTSITER=50x50x100;
            #ANTSITER=100;
            # Use mask or not
            if [ -z $DEFMASK ]; then
              maskopt=""
            else
              maskopt="-x $WDIR/hwtrimdef.nii.gz"
            fi
            rm -f $WDIR/ants/ants_output_2.5d.txt
            $BIN_ANTS/ANTS 3 $maskopt \
              -m PR[$WDIR/bltrim_to_hw.nii.gz,$WDIR/futrim_om_to_hw.nii.gz,1,4] \
              -o $WDIR/ants/antsreg2.5d.nii.gz \
              -i $ANTSITER \
              -v -t SyN[${ASTEPSIZE}] -r $REGUL \
              --Restrict-Deformation  1x1x0 \
              --continue-affine false | tee $WDIR/ants/ants_output_2.5d.txt;

            # Warp followup to baseline and to halfway space
            $BIN_ANTS/WarpImageMultiTransform 3 $WDIR/futrim_om.nii.gz $WDIR/futrim_om_to_bltrim_warped_2.5d.nii.gz \
               -R $WDIR/bltrimdef.nii.gz  $WDIR/omRAS_half_itk.txt $WDIR/ants/antsreg2.5dWarp.nii.gz $WDIR/omRAS_half_itk.txt;
            $BIN_ANTS/WarpImageMultiTransform 3 $WDIR/futrim_om.nii.gz $WDIR/futrim_om_to_hw_warped_2.5d.nii.gz \
               -R $WDIR/hwtrimdef.nii.gz  $WDIR/ants/antsreg2.5dWarp.nii.gz $WDIR/omRAS_half_itk.txt;
            c3d $WDIR/ants/antsreg2.5dWarp?vec.nii.gz -omc 3 $WDIR/ants/antsreg2.5dWarp.mha;
            c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw.nii.gz -histmatch 3 \
              $WDIR/bltrim_to_hw.nii.gz -scale -1 -add -o $WDIR/regdiffbefore_2.5d.nii.gz 
            c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw_warped_2.5d.nii.gz -histmatch 3 \
              $WDIR/bltrim_to_hw.nii.gz -scale -1 -add -o $WDIR/regdiffafter_2.5d.nii.gz 
            echo before `c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw.nii.gz -ncor` > $WDIR/regncor_2.5d.txt 
            echo after `c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw_warped_2.5d.nii.gz -ncor` >> $WDIR/regncor_2.5d.txt 
            ;;
        "2")  echo "performing 2D deformable registration on corresponding z slices";
            ANTSITER=50x50x300;
            #ANTSITER=400;
            zsize=`c3d $WDIR/bltrimdef.nii.gz -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
            > $WDIR/regncor_2.txt
            for ((i=0; i < ${zsize}; i++)) do
              c3d $WDIR/bltrimdef.nii.gz -slice z $i -o $WDIR/bltrimdef_${i}.nii.gz;
              c3d $WDIR/bltrim.nii.gz -slice z $i -o $WDIR/bltrim_${i}.nii.gz -o $WDIR/bltrim_${i}.mha;
              c3d $WDIR/futrim_om_resliced_to_bltrim.nii.gz -slice z $i -o $WDIR/futrim_om_resliced_to_bltrim_${i}.nii.gz;
              c2d $WDIR/bltrimdef_${i}.nii.gz $SUPERRES -o $WDIR/bltrimdef_${i}.nii.gz
              c2d $WDIR/bltrim_${i}.nii.gz $SUPERRES -o $WDIR/bltrim_${i}.nii.gz
              c2d $WDIR/futrim_om_resliced_to_bltrim_${i}.nii.gz $SUPERRES -o $WDIR/futrim_om_resliced_to_bltrim_${i}.nii.gz
              # Use mask or not
              if [ -z $DEFMASK ]; then
                maskopt=""
              else
                maskopt="-x $WDIR/bltrimdef_${i}.nii.gz"
              fi
              rm -f $WDIR/ants/ants_output_${i}.txt
              $BIN_ANTS/ANTS 2 $maskopt \
                -m PR[$WDIR/bltrim_${i}.nii.gz,$WDIR/futrim_om_resliced_to_bltrim_${i}.nii.gz,1,4] \
                -o $WDIR/ants/antsreg_${i}.nii.gz \
                -i $ANTSITER \
                -v -t SyN[${ASTEPSIZE?}] -r $REGUL \
                --continue-affine false | tee $WDIR/ants/ants_output_${i}.txt;
              #  -v -t SyN[${ASTEPSIZE?}] -r $REGUL \
              #  -v -t SyN[0.1,5,0.001] --geodesic 2 -r $REGUL] \
              # TODO handle properly. This is a terrible hack. When one image is empty, ANTS bails out with NaNs in energy
              # without any warning. If this happens warp files are not generated.

              if [ ! -f $WDIR/ants/antsreg_${i}Warpxvec.nii.gz ]; then
                c3d $WDIR/bltrimdef_${i}.nii.gz -dup -scale -1 -add -o $WDIR/ants/antsreg_${i}Warpxvec.nii.gz
                cp $WDIR/ants/antsreg_${i}Warpxvec.nii.gz $WDIR/ants/antsreg_${i}Warpyvec.nii.gz
                cp $WDIR/ants/antsreg_${i}Warpxvec.nii.gz $WDIR/ants/antsreg_${i}InverseWarpxvec.nii.gz
                cp $WDIR/ants/antsreg_${i}Warpyvec.nii.gz $WDIR/ants/antsreg_${i}InverseWarpyvec.nii.gz
                get_2didentity_transform_itk > $WDIR/ants/antsreg_${i}Affine.txt
              fi
              c3d $WDIR/ants/antsreg_${i}Warpxvec.nii.gz -dup -scale -1 -add -o $WDIR/ants/antsreg_${i}Warpzvec.nii.gz
              c3d $WDIR/ants/antsreg_${i}InverseWarpxvec.nii.gz -dup -scale -1 -add -o $WDIR/ants/antsreg_${i}InverseWarpzvec.nii.gz
              
              $BIN_ANTS/WarpImageMultiTransform 2 $WDIR/futrim_om_resliced_to_bltrim_${i}.nii.gz $WDIR/futrim_om_to_bltrim_warped_${i}.nii.gz \
                -R $WDIR/bltrimdef_${i}.nii.gz  $WDIR/ants/antsreg_${i}Warp.nii.gz $WDIR/ants/antsreg_${i}Affine.txt;
              c3d $WDIR/ants/antsreg_${i}Warp?vec.nii.gz -omc 3 $WDIR/ants/antsreg_${i}Warp.mha;
              c2d $WDIR/bltrim_${i}.nii.gz $WDIR/futrim_om_resliced_to_bltrim_${i}.nii.gz \
                -histmatch 2 $WDIR/bltrim_${i}.nii.gz -scale -1 -add -o $WDIR/regdiffbefore_${i}.nii.gz
              c2d $WDIR/bltrim_${i}.nii.gz $WDIR/futrim_om_to_bltrim_warped_${i}.nii.gz \
                -histmatch 2 $WDIR/bltrim_${i}.nii.gz -scale -1 -add -o $WDIR/regdiffafter_${i}.nii.gz
              echo ${i} before `c2d $WDIR/bltrim_${i}.nii.gz $WDIR/futrim_om_resliced_to_bltrim_${i}.nii.gz -ncor` >> $WDIR/regcor_2.txt 
              echo ${i} after `c2d $WDIR/bltrim_${i}.nii.gz $WDIR/futrim_om_to_bltrim_warped_${i}.nii.gz -ncor` >> $WDIR/regcor_2.txt 
               
            done
            ;;
        *) echo "Unknown deformable registration option";
            exit -1;
            ;;
    esac
      
     
      

      # Move the tetmesh to the halfway point
      #warpmesh $TET $WDIR/tet2hw.vtk $WDIR/omRAS_half.mat

      # Apply the warp to the mesh
      #warpmesh -w ants $WDIR/tet2hw.vtk $WDIR/tetwarp.vtk $WDIR/ants/antsregWarp?vec.nii.gz

      # Apply the second half of the rigid transform to the mesh
      #warpmesh $WDIR/tetwarp.vtk ${PREFIX}_tetmesh.vtk $WDIR/omRAS_half.mat

  elif [ ${RIGIDMODE?} = "HW" ]; then

    # Run one of three different kinds of deformable registration
    case $REGDIM in  
      "3")  echo "performing 3D deformable registration";
           
            ANTSITER=50x50x100;
            #ANTSITER=100;

            # Use mask or not
            if [ -z $DEFMASK ]; then
              maskopt=""
            else
              maskopt="-x $WDIR/hwtrimdef.nii.gz"
            fi

            /home/pauly/bin/c3d $WDIR/bltrim_to_hw.nii.gz -cmp -oo $TMPDIR/grid00.nii.gz $TMPDIR/grid01.nii.gz $TMPDIR/grid02.nii.gz
            
            if [ ${DEFREGPROG} = "ants" ]; then
                rm -f $WDIR/ants/ants_output_3d.txt
                # Execute ANTS with special function
                $BIN_ANTS/ANTS 3 $maskopt  \
                  -m PR[$WDIR/bltrim_to_hw.nii.gz,$WDIR/futrim_om_to_hw.nii.gz,1,4] \
                  -o $WDIR/ants/antsreg3d.nii.gz \
                  -i $ANTSITER \
                  -v -t SyN[${ASTEPSIZE?}] -r Gauss[$REGUL] \
                  --continue-affine false | tee $WDIR/ants/ants_output_3d.txt;

               #   -m MSQ[$TMPDIR/grid00.nii.gz,$TMPDIR/grid00.nii.gz,0.2] \
               #   -m MSQ[$TMPDIR/grid01.nii.gz,$TMPDIR/grid01.nii.gz,0.2] \
               #   -m MSQ[$TMPDIR/grid02.nii.gz,$TMPDIR/grid02.nii.gz,0.2] \
              #  $BIN_ANTS/ANTS_unbiased 3 $maskopt \
              #   -m PR[$WDIR/bltrim.nii.gz,$WDIR/futrim_om.nii.gz,1,4] \
              #   -o $WDIR/ants/antsreg3d.nii.gz \
              #   -i $ANTSITER \
              #   -F $WDIR/omRAS_half_inv_itk.txt \
              #   -a $WDIR/omRAS_half_itk.txt \
              #   --fixed-image-initial-affine-ref-image $WDIR/hwtrimdef.nii.gz \
              #   -v -t SyN[${ASTEPSIZE?}] -r $REGUL \
              #   --continue-affine false | tee $WDIR/ants/ants_output_3d.txt;

              #    -m PR[$WDIR/bltrim_to_hw.nii.gz,$WDIR/futrim_om_to_hw.nii.gz,1,4] \ # PR metric
              #    -m MI[$WDIR/bltrim_to_hw.nii.gz,$WDIR/futrim_om_to_hw.nii.gz,1,32] \ # MI metric
              #    -v -t SyN[${ASTEPSIZE?}] -r $REGUL \ # For TSE, Gauss[0.5,0.2]
              #    -v -t SyN[${ASTEPSIZE?}] -r $REGUL \ # For MPRAGE, Gauss[2.0,0.5]
              #  -v -t SyN[0.25,5,0.1] --geodesic 2 -r Gauss[0.5, 0.2] \
            elif [ ${DEFREGPROG} = "irtk" ]; then
                # Get the native resolution
                NATIVERES=$(c3d $WDIR/bltrim_to_hw.nii.gz -info-full | grep "Voxel Spacing" | sed -e "s/.*\[//" -e "s/,//g" -e "s/\]//");
                setup_irtk;
                $BIN_IRTK/nreg $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw.nii.gz \
                  -parin $WDIR/irtk/nreg.param \
                  -dofout $WDIR/irtk/nreg_3d.dof -parout $WDIR/irtk/nreg_out.param | tee $WDIR/irtk/irtk_output_3d.txt;
                # Extract the warps as images
                $BIN_IRTK/dof2image $WDIR/hwtrimdef.nii.gz $WDIR/irtk/nreg_3d.dof \
                  $WDIR/irtk/irtkreg3dWarpxvec.nii.gz \
                  $WDIR/irtk/irtkreg3dWarpyvec.nii.gz \
                  $WDIR/irtk/irtkreg3dWarpzvec.nii.gz;
            else
                echo "Unknown deformable registration program";
                exit -1;
            fi

        

            # Warp followup to baseline
            $BIN_ANTS/WarpImageMultiTransform 3 $WDIR/futrim_om.nii.gz $WDIR/futrim_om_to_bltrim_warped_3d.nii.gz \
              -R $WDIR/bltrimdef.nii.gz  $WDIR/omRAS_half_itk.txt $WDIR/${DEFREGPROG}/${DEFREGPROG}reg3dWarp.nii.gz $WDIR/omRAS_half_itk.txt;
            $BIN_ANTS/WarpImageMultiTransform 3 $WDIR/futrim_om.nii.gz $WDIR/futrim_om_to_hw_warped_3d.nii.gz \
               -R $WDIR/hwtrimdef.nii.gz  $WDIR/${DEFREGPROG}/${DEFREGPROG}reg3dWarp.nii.gz $WDIR/omRAS_half_itk.txt;
            c3d $WDIR/${DEFREGPROG}/${DEFREGPROG}reg3dWarp?vec.nii.gz -omc 3 $WDIR/${DEFREGPROG}/${DEFREGPROG}reg3dWarp.mha;
            c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw.nii.gz -histmatch 3 \
              $WDIR/bltrim_to_hw.nii.gz -scale -1 -add -o $WDIR/regdiffbefore_3d.nii.gz 
            c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw_warped_3d.nii.gz -histmatch 3 \
              $WDIR/bltrim_to_hw.nii.gz -scale -1 -add -o $WDIR/regdiffafter_3d.nii.gz 
            echo before `c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw.nii.gz -ncor` > $WDIR/regncor_3d.txt 
            echo after `c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw_warped_3d.nii.gz -ncor` >> $WDIR/regncor_3d.txt 
            ;;
      "2.5")  echo "performing 2.5D deformable registration, restrict deformation in z";
            ANTSITER=50x50x100;
            #ANTSITER=100;
            # Use mask or not
            if [ -z $DEFMASK ]; then
              maskopt=""
            else
              maskopt="-x $WDIR/hwtrimdef.nii.gz"
            fi
            rm -f $WDIR/ants/ants_output_2.5d.txt
            $BIN_ANTS/ANTS 3 $maskopt \
              -m PR[$WDIR/bltrim_to_hw.nii.gz,$WDIR/futrim_om_to_hw.nii.gz,1,4] \
              -o $WDIR/ants/antsreg2.5d.nii.gz \
              -i $ANTSITER \
              -v -t SyN[${ASTEPSIZE}] -r $REGUL \
              --Restrict-Deformation  1x1x0 \
              --continue-affine false | tee $WDIR/ants/ants_output_2.5d.txt;

            # Warp followup to baseline and to halfway space
            $BIN_ANTS/WarpImageMultiTransform 3 $WDIR/futrim_om.nii.gz $WDIR/futrim_om_to_bltrim_warped_2.5d.nii.gz \
               -R $WDIR/bltrimdef.nii.gz  $WDIR/omRAS_half_itk.txt $WDIR/ants/antsreg2.5dWarp.nii.gz $WDIR/omRAS_half_itk.txt;
            $BIN_ANTS/WarpImageMultiTransform 3 $WDIR/futrim_om.nii.gz $WDIR/futrim_om_to_hw_warped_2.5d.nii.gz \
               -R $WDIR/hwtrimdef.nii.gz  $WDIR/ants/antsreg2.5dWarp.nii.gz $WDIR/omRAS_half_itk.txt;
            c3d $WDIR/ants/antsreg2.5dWarp?vec.nii.gz -omc 3 $WDIR/ants/antsreg2.5dWarp.mha;
            c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw.nii.gz -histmatch 3 \
              $WDIR/bltrim_to_hw.nii.gz -scale -1 -add -o $WDIR/regdiffbefore_2.5d.nii.gz 
            c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw_warped_2.5d.nii.gz -histmatch 3 \
              $WDIR/bltrim_to_hw.nii.gz -scale -1 -add -o $WDIR/regdiffafter_2.5d.nii.gz 
            echo before `c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw.nii.gz -ncor` > $WDIR/regncor_2.5d.txt 
            echo after `c3d $WDIR/bltrim_to_hw.nii.gz $WDIR/futrim_om_to_hw_warped_2.5d.nii.gz -ncor` >> $WDIR/regncor_2.5d.txt 
            ;;
        "2")  echo "performing 2D deformable registration on corresponding z slices";
            ANTSITER=50x50x300;
            #ANTSITER=400;
            zsize=`c3d $WDIR/hwtrimdef.nii.gz -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
            > $WDIR/regncor_2.txt
            for ((i=0; i < ${zsize}; i++)) do
              c3d $WDIR/hwtrimdef.nii.gz -slice z $i -o $WDIR/hwtrimdef_${i}.nii.gz;
              c3d $WDIR/bltrim_to_hw.nii.gz -slice z $i -o $WDIR/bltrim_to_hw_${i}.nii.gz -o $WDIR/bltrim_to_hw_${i}.mha;
              c3d $WDIR/futrim_om_to_hw.nii.gz -slice z $i -o $WDIR/futrim_om_to_hw_${i}.nii.gz -o $WDIR/futrim_om_to_hw_${i}.mha;
              c2d $WDIR/hwtrimdef_${i}.nii.gz $SUPERRES -o $WDIR/hwtrimdef_${i}.nii.gz
              c2d $WDIR/bltrim_to_hw_${i}.nii.gz $SUPERRES -o $WDIR/bltrim_to_hw_${i}.nii.gz
              c2d $WDIR/futrim_om_to_hw_${i}.nii.gz $SUPERRES -o $WDIR/futrim_om_to_hw_${i}.nii.gz
              # Use mask or not
              if [ -z $DEFMASK ]; then
                maskopt=""
              else
                maskopt="-x $WDIR/hwtrimdef_${i}.nii.gz"
              fi


              if [ ${DEFREGPROG} = "ants" ]; then
                rm -f $WDIR/ants/ants_output_${i}.txt
                $BIN_ANTS/ANTS 2 $maskopt \
                  -m PR[$WDIR/bltrim_to_hw_${i}.nii.gz,$WDIR/futrim_om_to_hw_${i}.nii.gz,1,4] \
                  -o $WDIR/ants/antsreg_${i}.nii.gz \
                  -i $ANTSITER \
                  -v -t SyN[${ASTEPSIZE?}] -r $REGUL \
                  --continue-affine false | tee $WDIR/ants/ants_output_${i}.txt;
                #  -v -t SyN[${ASTEPSIZE?}] -r $REGUL \
                #  -v -t SyN[0.1,5,0.001] --geodesic 2 -r $REGUL] \
                # TODO handle properly. This is a terrible hack. When one image is empty, ANTS bails out with NaNs in energy
                # without any warning. If this happens warp files are not generated.
                if [ ! -f $WDIR/ants/antsreg_${i}Warpxvec.nii.gz ]; then
                  c3d $WDIR/hwtrimdef_${i}.nii.gz -dup -scale -1 -add -o $WDIR/ants/antsreg_${i}Warpxvec.nii.gz
                  cp $WDIR/ants/antsreg_${i}Warpxvec.nii.gz $WDIR/ants/antsreg_${i}Warpyvec.nii.gz
                  cp $WDIR/ants/antsreg_${i}Warpxvec.nii.gz $WDIR/ants/antsreg_${i}InverseWarpxvec.nii.gz
                  cp $WDIR/ants/antsreg_${i}Warpyvec.nii.gz $WDIR/ants/antsreg_${i}InverseWarpyvec.nii.gz
                  get_2didentity_transform_itk > $WDIR/ants/antsreg_${i}Affine.txt
                fi
              elif [ ${DEFREGPROG} = "of" ]; then
                
:<<'NOOF'
/home/local/matlab_r2009b/bin/matlab -singleCompThread -nodisplay <<MAT2
  mypwd=pwd;
  cd('${WDIR}/of');
  vacind_long_opticalflow('${WDIR}/bltrim_to_hw_${i}.nii','${WDIR}/futrim_om_to_hw_${i}.nii');
  cd(mypwd);
MAT2
                mv ${WDIR}/of/of_Warpxvec.nii ${WDIR}/of/ofreg_${i}Warpxvec.nii 
                mv ${WDIR}/of/of_Warpyvec.nii ${WDIR}/of/ofreg_${i}Warpyvec.nii 
NOOF
                xvox=`c2d ${WDIR}/bltrim_to_hw_${i}.nii.gz -info-full |grep "Voxel Spacing" | cut -f 2 -d "[" | cut -f 1 -d "]" | cut -f 1 -d ","`
                c2d ${WDIR}/of/ofreg_${i}Warpxvec.nii.gz -scale $xvox -o ${WDIR}/of/ofreg_${i}Warpxvec.nii.gz
                yvox=`c2d ${WDIR}/bltrim_to_hw_${i}.nii.gz -info-full |grep "Voxel Spacing" | cut -f 2 -d "[" | cut -f 1 -d "]" | cut -f 2 -d ","`
                c2d ${WDIR}/of/ofreg_${i}Warpyvec.nii.gz -scale $yvox -o ${WDIR}/of/ofreg_${i}Warpyvec.nii.gz
                # gzip -f ${WDIR}/of/ofreg_${i}Warp?vec.nii
                get_2didentity_transform_itk > $WDIR/of/ofreg_${i}Affine.txt
              else
                echo "Unknown deformable registration program";
                exit -1;
              fi

              
              c3d $WDIR/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warpxvec.nii.gz -dup -scale -1 -add -o $WDIR/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warpzvec.nii.gz
              if [ ${DEFREGPROG} = "ants" ]; then
                c3d $WDIR/${DEFREGPROG}/${DEFREGPROG}reg_${i}InverseWarpxvec.nii.gz -dup -scale -1 -add -o $WDIR/${DEFREGPROG}/${DEFREGPROG}reg_${i}InverseWarpzvec.nii.gz
              fi
              $BIN_ANTS/WarpImageMultiTransform 2 $WDIR/futrim_om_to_hw_${i}.nii.gz $WDIR/futrim_om_to_hw_warped_${i}.nii.gz \
                -R $WDIR/hwtrimdef_${i}.nii.gz  $WDIR/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warp.nii.gz $WDIR/${DEFREGPROG}/${DEFREGPROG}reg_${i}Affine.txt;
              if [ ${DEFREGPROG} = "ants" ]; then
              $BIN_ANTS/WarpImageMultiTransform 2 $WDIR/bltrim_to_hw_${i}.nii.gz $WDIR/bltrim_to_hw_warped_${i}.nii.gz \
                -R $WDIR/hwtrimdef_${i}.nii.gz  -i $WDIR/ants/antsreg_${i}Affine.txt $WDIR/ants/antsreg_${i}InverseWarp.nii.gz;
              fi
              c3d $WDIR/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warp?vec.nii.gz -omc 3 $WDIR/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warp.mha;
              c2d $WDIR/bltrim_to_hw_${i}.nii.gz $WDIR/futrim_om_to_hw_${i}.nii.gz \
                -histmatch 2 $WDIR/bltrim_to_hw_${i}.nii.gz -scale -1 -add -o $WDIR/regdiffbefore_${i}.nii.gz
              c2d $WDIR/bltrim_to_hw_${i}.nii.gz $WDIR/futrim_om_to_hw_warped_${i}.nii.gz \
                -histmatch 2 $WDIR/bltrim_to_hw_${i}.nii.gz -scale -1 -add -o $WDIR/regdiffafter_${i}.nii.gz
              echo ${i} before `c2d $WDIR/bltrim_to_hw_${i}.nii.gz $WDIR/futrim_om_to_hw_${i}.nii.gz -ncor` >> $WDIR/regncor_2.txt 
              echo ${i} after `c2d $WDIR/bltrim_to_hw_${i}.nii.gz $WDIR/futrim_om_to_hw_warped_${i}.nii.gz -ncor` >> $WDIR/regncor_2.txt 
               
            done
            ;;
        *) echo "Unknown deformable registration option";
            exit -1;
            ;;
    esac
      
     
      

      # Move the tetmesh to the halfway point
      #warpmesh $TET $WDIR/tet2hw.vtk $WDIR/omRAS_half.mat

      # Apply the warp to the mesh
      #warpmesh -w ants $WDIR/tet2hw.vtk $WDIR/tetwarp.vtk $WDIR/ants/antsregWarp?vec.nii.gz

      # Apply the second half of the rigid transform to the mesh
      #warpmesh $WDIR/tetwarp.vtk ${PREFIX}_tetmesh.vtk $WDIR/omRAS_half.mat

  else

    # Execute ANTS with special function
    /home/srdas/bin/ants_avants/ANTS 3 \
      -x $WDIR/bltrimdef.nii.gz \
      -m PR[$WDIR/bltrim.nii.gz,$WDIR/futrim_om.nii.gz,1,4] \
      -a $WDIR/omRAS_itk.txt \
      -o $WDIR/ants/antsreg.nii.gz \
      -i $ANTSITER \
      -v -t SyN[${ASTEPSIZE?}] -r Gauss[2.0] \
      --continue-affine false | tee $WDIR/ants/ants_output.txt

      # Apply the warp to the mesh
      warpmesh -w ants $TET $WDIR/tetwarp.vtk $WDIR/ants/antsregWarp?vec.nii.gz

      # Apply the second half of the rigid transform to the mesh
      warpmesh $WDIR/tetwarp.vtk ${PREFIX}_tetmesh.vtk $WDIR/omRAS.mat

  fi

  # Measure the Jacobian between the meshes
  #tetjac $TET ${PREFIX}_tetmesh.vtk ${PREFIX}_tetjac.vtk \
  #  | grep VOLUME_STATS | cut -f 3 -d ' ' > ${PREFIX}_tetvol.txt

else

  # Just transform the mesh using FLIRT transform
  #warpmesh $TET ${PREFIX}_tetmesh.vtk $WDIR/wbRAS.mat
  echo "Not doing deformable registration"

fi
