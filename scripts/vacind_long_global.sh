# This script performs global longitudinal registration of T2 images initialized through T1 images
set -x


if [ "$USEMASK" == "1" ]; then
  if [ "$REGTYPE" == "chunk" ]; then
    mask="$WDIR/bl${mstr}trimfullmask.nii.gz $WDIR/fu${mstr}trimfullmask.nii.gz"
  else
    if [ "$MODALITY" == "TSE" ]; then
      mask="$WDIR/../../bl_tse_fullmask.nii.gz $WDIR/../../fu_tse_fullmask.nii.gz"
    else
      mask="$WDIR/../../bl_mprage_fullmask.nii.gz $WDIR/../../fu_mprage_fullmask.nii.gz"
    fi
  fi
else
  mask="none none"
fi


# Create the halfway reference space
# Break up the commands to avoid undebugged matrix inversion error on cluster at the -sqrt command
# doesn't happen on maxcent
c3d_affine_tool -sform $FUGRAY -sform $BLGRAY -inv -mult -o $WRDIR/tmp.mat 
c3d_affine_tool $WRDIR/tmp.mat -sqrt -sform $BLGRAY -mult -o $WRDIR/hwspace.mat
rm $WRDIR/tmp.mat

if [ "$GLOBALREGPROG" == "flirt" ]; then

  FSLOUTPUTTYPE=NIFTI_GZ
  export FSLOUTPUTTYPE

  if [ "$MODALITY" == "TSE" ]; then
    # For whole brain registration, use T1-based initialization
    INITMAT=${WRDIR}/../../ibn_work_L/tse_long.mat
  else
    # For whole brain registration, use the rough T1 registration as initialization
    INITMAT=${WRDIR}/../../ibn_work_L/mprage_long.mat
  fi
  if [ "$REGTYPE" == "chunk" ]; then
    # using whole brain run as initialization for chunk run
    if [ "$MODALITY" == "TSE" ]; then
      if [ -f ${WRDIR}/../../ibn_work_L/flirt/flirt_${METRIC}_${SYMMTYPE}.mat ]; then
        echo "Not using whole brain initialization even though it is available"
#        INITMAT=${WRDIR}/../../ibn_work_L/flirt/flirt_${METRIC}_${SYMMTYPE}.mat
      fi
    else
      if [ -f ${WRDIR}/../../ibn_work_L/flirt_mp/flirt_${METRIC}_${SYMMTYPE}.mat ]; then
        # echo "Not using whole brain initialization even though it is available"
         INITMAT=${WRDIR}/../../ibn_work_L/flirt_mp/flirt_${METRIC}_${SYMMTYPE}.mat
      fi
    fi
  fi

  if [ ! -f $INITMAT ]; then
    echo "Initial transform not found, perhaps you did not run left side ?"
    exit -1
  else 
    INIT="-init $INITMAT"
  fi
  
  thetalo=10
  thetahi=10
   coarse=1
   fine=0.1
  # coarse=2
  # fine=1

  if [ "$SYMMTYPE" == "symm" ]; then
    echo "Symmetric registration not supported with flirt"
    exit -1
  fi

  if $RUNRIGID; then
    flirt -usesqform -v -ref $BLGRAY -in $FUGRAY -omat $WRDIR/flirt_${METRIC}_${SYMMTYPE}.mat -dof 9 $INIT  \
      -searchrx -$thetalo $thetahi -searchry -$thetalo $thetahi -searchrz -$thetalo $thetahi \
      -cost $METRIC  -searchcost $METRIC -anglerep quaternion # \
#      -coarsesearch $coarse -finesearch $fine
  fi
  # Delete these lines when flirt is run with the new setup once, for now -- copying matrix from old flirt run
  # cp $WDIR/wbFlirt.mat $WRDIR/flirt_${METRIC}_${SYMMTYPE}.mat


  # Reslice for QA
  flirt -usesqform -v -ref $BLGRAY -in $FUGRAY -out $WRDIR/resliced_flirt_${METRIC}_${SYMMTYPE}.nii.gz -init $WRDIR/flirt_${METRIC}_${SYMMTYPE}.mat -applyxfm

  # Convert transform to RAS
  c3d_affine_tool -ref $BLGRAY -src $FUGRAY $WRDIR/flirt_${METRIC}_${SYMMTYPE}.mat -fsl2ras -o $WRDIR/flirt_RAS_${METRIC}_${SYMMTYPE}.mat 

# Use Reuter's tool

elif [ "$GLOBALREGPROG" == "reuter" ]; then

  FREESURFER_HOME=/home/hwang3/pkg/freesurfer/

  export FREESURFER_HOME

  if [ "$SYMMTYPE" == "asym" ]; then
    echo "Symmetric registration not supported with Reuter's robust registration"
    exit -1
  fi


  # Run initial registration with Reuter's tool
  if [ ! -f $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}.lta ]; then 
    ~pauly/bin/mri_robust_register \
      --dst $FUGRAY \
      --mov $BLGRAY \
      --lta $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}.lta --satit 
  fi

  if [ "$MODALITY" == "TSE" ]; then
    # For whole brain registration, use T1-based initialization
    INITMAT=${WRDIR}/../../ibn_work_L/tse_long_RAS.mat
     INITMAT=${WRDIR}/../../ibn_work_L/flirt_chunk/flirt_RAS_normcorr_asym.mat
  else
    # For whole brain registration, use the rough T1 registration as initialization
    INITMAT=${WRDIR}/../../ibn_work_L/mprage_long_RAS.mat
  fi

  
  cat $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}.lta | head -n 8 > $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}_init.lta
  cat $INITMAT >> $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}_init.lta
  cat $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}.lta | tail -n 18 >> $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}_init.lta 


  ~pauly/bin/mri_robust_register \
    --dst $FUGRAY \
    --mov $BLGRAY \
    --lta $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}.lta --satit \
    --maxit 20 --highit 5 \
    --transform $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}_init.lta


  cat $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}.lta | head -n 12 | tail -n 4 > $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}.mat

  # Reslice for QA
  c3d $BLGRAY $FUGRAY -reslice-matrix $WRDIR/reuter_RAS_${METRIC}_${SYMMTYPE}.mat -o $WRDIR/resliced_reuter_${METRIC}_${SYMMTYPE}.nii.gz


# Do evolutionary optimization

elif [ "$GLOBALREGPROG" == "evolreg" ]; then
  
  radius=0.01
  growth=1.05
  shrink=-1
  eps=1e-100
  # maxit=100000
  maxit=30000
  inittype=unchanged
  regtype=rig

  # If we use flirt initialization, use normcorr which is reasonable
  # INIT=$WRDIR/../../ibn_work_${side}/flirt${REGSUFF}/flirt_RAS_normcorr_asym.mat
  if [ "$MODALITY" == "TSE" ]; then
    INIT=${WRDIR}/../../ibn_work_${side}/tse_long_RAS.mat
  else
    INIT=${WRDIR}/../../ibn_work_${side}/mprage_long_RAS.mat
  fi 

  evolreg $BLGRAY $FUGRAY $mask $WRDIR/evolreg_RAS_${METRIC}_${SYMMTYPE} $INIT $inittype $regtype $METRIC \
    $SYMMTYPE master $radius $growth $shrink $eps $maxit;

  # Reslice for QA
  # Already done
  mv $WRDIR/evolreg_RAS_${METRIC}_${SYMMTYPE}.nii.gz $WRDIR/resliced_evolreg_${METRIC}_${SYMMTYPE}.nii.gz

# Do brute force optimization

elif [ "$GLOBALREGPROG" == "bfreg" ]; then

  nsteps=6
  tsteps=1
  steplength=0.01
  inittype=unchanged
  regtype=rig

  if [ "$MODALITY" == "TSE" ]; then
    INIT=$WRDIR/../../ibn_work_${side}/flirt${REGSUFF}/flirt_RAS_normcorr_asym.mat
  else
    INIT=$WRDIR/../../ibn_work_${side}/flirt${REGSUFF}_mp/flirt_RAS_normcorr_asym.mat
  fi

  bfreg $BLGRAY $FUGRAY $mask $WRDIR/bfreg_RAS_${METRIC}_${SYMMTYPE} $INIT $inittype $regtype $METRIC \
    $SYMMTYPE master $nsteps $tsteps $steplength;

  # Reslice for QA
  # Already done
  mv $WRDIR/bfreg_RAS_${METRIC}_${SYMMTYPE}.nii.gz $WRDIR/resliced_bfreg_${METRIC}_${SYMMTYPE}.nii.gz


elif [ "$GLOBALREGPROG" == "ANTS" ]; then


  if [ "SYMMTYPE" == "symm" ]; then
    echo "Symmetric global registration not supported with ANTS"
    exit -1
  fi
  if [ "$MODALITY" == "TSE" ]; then
    # For whole brain registration, use T1-based initialization
    INITMAT=${WRDIR}/../../ibn_work_L/tse_long.mat
  else
    # For whole brain registration, use the rough T1 registration as initialization
    INITMAT=${WRDIR}/../../ibn_work_L/mprage_long.mat
  fi
  if [ "$REGTYPE" == "chunk" ]; then
    # using whole brain run as initialization for chunk run
    if [ "$MODALITY" == "TSE" ]; then
      if [ -f ${WRDIR}/../../ibn_work_L/ANTS/ANTS_${METRIC}_${SYMMTYPE}.mat ]; then
        echo "Not using whole brain initialization even though it is available"
#        INITMAT=${WRDIR}/../../ibn_work_L/flirt/flirt_${METRIC}_${SYMMTYPE}.mat
      fi
    else
      if [ -f ${WRDIR}/../../ibn_work_L/ANTS_mp/ANTS_${METRIC}_${SYMMTYPE}.mat ]; then
        # echo "Not using whole brain initialization even though it is available"
         INITMAT=${WRDIR}/../../ibn_work_L/ANTS_mp/ANTS_${METRIC}_${SYMMTYPE}.mat
      fi
    fi
  fi

  if [ ! -f $INITMAT ]; then
    echo "Initial transform not found, perhaps you did not run left side ?"
    exit -1
  else 
    c3d_affine_tool -ref $BLGRAY -src $FUGRAY $INITMAT -fsl2ras -oitk ${WRDIR}/ants_init_itk.txt
    INIT="-r [${WRDIR}/ants_init_itk.txt]"
  fi




  # INITMAT=$WRDIR/../../ibn_work_L/flirt${REGSUFF}/flirt_RAS_normcorr_asym.mat
  # c3d_affine_tool -ref $BLGRAY -src $FUGRAY $INITMAT -fsl2ras -oitk ${WRDIR}/ants_init_itk.txt
  # ANTS 3 -m  MI[${BLGRAY},${FUGRAY},1,32] -o $WRDIR/ANTS_${METRIC}_${SYMMTYPE} \
  #   -i 0   --use-Histogram-Matching --number-of-affine-iterations 10000x10000x10000x10000x10000 \
  #   --rigid-affine true  --affine-gradient-descent-option  0.5x0.95x1.e-4x1.e-4  --MI-option 32x16000 \
  #   -a ${WRDIR}/ants_init_itk.txt

  BIN_ANTSITK4=$HOME/bin/ants_avants
  # Initialize with center of mass or use initial transform
  # If we use initial transform then ConvertTransoformFile fails on 0DerivedInitialMovingTranslation.mat
  #  -r [${BLGRAY},${FUGRAY},1] \
  #  $INIT \

  $BIN_ANTSITK4/antsRegistration -d 3 -o [$WRDIR/ANTS_${METRIC}_${SYMMTYPE},$WRDIR/ANTS_${METRIC}_${SYMMTYPE}_resliced.nii.gz] \
    -r [${BLGRAY},${FUGRAY},1] \
    -t Translation[0.1] -f 4x2x1 -s 2x1x0 -c [1200x1200x50,1e-08,10] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[${BLGRAY},${FUGRAY},1,32,Regular,0.25] \
    -t Rigid[0.1] -f 4x2x1 -s 2x1x0 -c [1200x1200x50,1e-08,10] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[${BLGRAY},${FUGRAY},1,32,Regular,0.25] \
    -t Similarity[0.1] -f 4x2x1 -s 2x1x0 -c [1200x1200x50,1e-08,10] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[${BLGRAY},${FUGRAY},1,32,Regular,0.25] \
    -b 0 
    ConvertTransformFile 3 $WRDIR/ANTS_${METRIC}_${SYMMTYPE}0DerivedInitialMovingTranslation.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}0DerivedInitialMovingTranslation_RAS.mat --hm
    ConvertTransformFile 3 $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Translation.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Translation_RAS.mat --hm
    ConvertTransformFile 3 $WRDIR/ANTS_${METRIC}_${SYMMTYPE}2Rigid.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}2Rigid_RAS.mat --hm
    ConvertTransformFile 3 $WRDIR/ANTS_${METRIC}_${SYMMTYPE}3Similarity.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}3Similarity_RAS.mat --hm
    c3d_affine_tool \
      $WRDIR/ANTS_${METRIC}_${SYMMTYPE}0DerivedInitialMovingTranslation_RAS.mat \
      $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Translation_RAS.mat \
      $WRDIR/ANTS_${METRIC}_${SYMMTYPE}2Rigid_RAS.mat \
      $WRDIR/ANTS_${METRIC}_${SYMMTYPE}3Similarity_RAS.mat \
      -mult -mult -mult \
      -o $WRDIR/ANTS_RAS_${METRIC}_${SYMMTYPE}.mat
<<'OLDCOMM'
  $BIN_ANTSITK4/antsRegistration -d 3 -o [$WRDIR/ANTS_${METRIC}_${SYMMTYPE},$WRDIR/ANTS_${METRIC}_${SYMMTYPE}_resliced.nii.gz] \
    -m Mattes[${BLGRAY},${FUGRAY},1,32,Regular,0.05] \
    -t Translation[1] -f 4x2x1 -s 2x1x0 -c [200x200x50,1e-08,10] -l 1 -u 1 -w [0.0,0.995] \
    -m Mattes[${BLGRAY},${FUGRAY},1,32,Regular,0.05] \
    -t Similarity[1] -f 4x2x1 -s 2x1x0 -c [200x200x50,1e-08,10] -l 1 -u 1 -w [0.0,0.995] \
    -b 0 $INIT
  if [ "$INIT" == "" ]; then 
    ConvertTransformFile 3 $WRDIR/ANTS_${METRIC}_${SYMMTYPE}0Translation.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}0Translation_RAS.mat --hm
    ConvertTransformFile 3 $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Similarity.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Similarity_RAS.mat --hm
    c3d_affine_tool $WRDIR/ANTS_${METRIC}_${SYMMTYPE}0Translation_RAS.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Similarity_RAS.mat -mult \
      -o $WRDIR/ANTS_RAS_${METRIC}_${SYMMTYPE}.mat
  else
    ConvertTransformFile 3 $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Translation.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Translation_RAS.mat --hm
    ConvertTransformFile 3 $WRDIR/ANTS_${METRIC}_${SYMMTYPE}2Similarity.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}2Similarity_RAS.mat --hm
    c3d_affine_tool -itk ${WRDIR}/ants_init_itk.txt $WRDIR/ANTS_${METRIC}_${SYMMTYPE}1Translation_RAS.mat $WRDIR/ANTS_${METRIC}_${SYMMTYPE}2Similarity_RAS.mat -mult -mult \
    -o $WRDIR/ANTS_RAS_${METRIC}_${SYMMTYPE}.mat
  fi
OLDCOMM

  c3d $BLGRAY $FUGRAY -reslice-matrix $WRDIR/ANTS_RAS_${METRIC}_${SYMMTYPE}.mat -o $WRDIR/resliced_ANTS_${METRIC}_${SYMMTYPE}.nii.gz

  # c3d_affine_tool -itk $WRDIR/ANTS_${METRIC}_${SYMMTYPE}Affine.txt -o $WRDIR/ANTS_RAS_${METRIC}_${SYMMTYPE}.mat
  # c3d $BLGRAY $FUGRAY -reslice-matrix $WRDIR/ANTS_RAS_${METRIC}_${SYMMTYPE}.mat -o $WRDIR/resliced_ANTS_${METRIC}_${SYMMTYPE}.nii.gz

else
  
  echo "Unknown global registration program"
  exit -1
  

fi


# Common processing of creating matrices and chunk images etc.


# Split transform
c3d_affine_tool $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}.mat \
  -inv -o $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}_inv.mat \
  -sqrt -o $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}_halfinv.mat -inv \
  -o $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}_half.mat

# Create halfway image according to current transform
c3d $BLGRAY -set-sform $WRDIR/hwspace.mat \
$BLGRAY -reslice-matrix $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}_halfinv.mat \
  -o $WRDIR/${GLOBALREGPROG}_${METRIC}_${SYMMTYPE}_hwdef.nii.gz -o $WRDIR/${GLOBALREGPROG}_${METRIC}_${SYMMTYPE}_bl_to_hw.nii.gz

c3d $WRDIR/${GLOBALREGPROG}_${METRIC}_${SYMMTYPE}_hwdef.nii.gz $FUGRAY \
  -reslice-matrix $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}_half.mat \
  -o $WRDIR/${GLOBALREGPROG}_${METRIC}_${SYMMTYPE}_fu_to_hw.nii.gz



if [ "$METRIC" == "mutualinfo" ]; then
  metriccommand="-mmi"
elif [ "$METRIC" == "normcorr" ]; then
  metriccommand="-ncor"
elif [ "$METRIC" == "normmi" ]; then
  metriccommand="-nmi"
elif [ "$METRIC" == "leastsq" ]; then
  metriccommand="-msq"
else
  echo "Unknown metric"
  exit -1
fi
echo "fixed   `c3d $BLGRAY $FUGRAY $metriccommand $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}.mat  `" \
  > $WRDIR/rigid_${METRIC}_${SYMMTYPE}.txt
echo "halfway `c3d $BLGRAY $FUGRAY $metriccommand $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}_half.mat $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}_halfinv.mat`" \
  >> $WRDIR/rigid_${METRIC}_${SYMMTYPE}.txt



:<< 'RSKIP'
# The following section is to be run one time only, using flirt result
# This creates the trimmed space, for which we can use the same images
# --------------------- one time ------------------
# Create small images in baseline and followup image spaces

# use the normmi transform for trimming
cp $WRDIR/../flirt/flirt_RAS_normmi_inv.mat $WRDIR/../flirt/flirt_RAS_${METRIC}_inv.mat

c3d $BLGRAY -as BL $FUGRAY -as FU \
  $BLSEG -trim 16mm -sdt -smooth 4mm -thresh 0 inf 1 0 -as M \
  -push BL -push M -dilate 1 3x3x3mm -reslice-identity -trim 10mm -as SBL -o $WDIR/bltrimdef.nii.gz \
  -push FU -push M -dilate 1 3x3x3mm -reslice-matrix $WRDIR/../flirt/flirt_RAS_normmi_inv.mat \
  -trim 10mm -as SFU -o $WDIR/futrimdef.nii.gz \
  -push SBL -push BL -int NN -reslice-identity  -o $WDIR/bltrim.nii.gz \
  -push SFU -push FU -int NN -reslice-identity  -o $WDIR/futrim.nii.gz 

# Check if mask contains the whole segmentation
maxdiff=`c3d  $SEG -trim 16mm -thresh 1 inf 1 0 -as M $WDIR/bltrimdef.nii.gz -push M -reslice-identity \
  -trim 10mm -binarize -scale -1 \
  -add -info-full   | grep "Intensity Range" | sed -e 's/]//g' | awk -F ',' {'print $2'}`
if [ $maxdiff -lt 0 ]; then 
  echo "mask doesn't contain the whole segmentation"
  exit -1;
fi

# Check if mask is genus zero
c3d $WDIR/bltrimdef.nii.gz -connected-components -threshold 1 1 1 0 -dilate 1 2x2x2vox  -pad 1x1x1vox 1x1x1vox 0 \
  -o $WDIR/padded.nii.gz
genus=`CheckTopology $WDIR/padded.nii.gz | tail -1 | awk {'print $2'}`
if [ $genus != 0 ]; then
  echo "mask is not a sphere"
  exit -1;
fi
rm -f $WDIR/padded.nii.gz

# Make the origins of the BL and FU images the same (this will make the 
# rigid transform between then smaller, and will minimize ANTS-related issues)
BLORIG=($(c3d $WDIR/bltrim.nii.gz -info-full | head -n 3 | tail -n 1 | sed -e "s/.*{\[//" -e "s/\],.*//"))
c3d $WDIR/futrim.nii.gz -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm -o $WDIR/futrim_om.nii.gz

# Create the halfway reference space
c3d_affine_tool -sform $WDIR/futrim_om.nii.gz -sform $WDIR/bltrim.nii.gz -inv -mult -sqrt -sform $WDIR/bltrim.nii.gz -mult -o $WDIR/hwtrimspace.mat
# ------------------ one time -------------------- 

RSKIP

:<< 'RSKIP1'
# Skipping the rest of the processing now, until we are happy with rigid registration
# Recompute the transformation between the images
c3d_affine_tool \
  -sform $WDIR/futrim_om.nii.gz \
  -sform $WDIR/futrim.nii.gz -inv \
  -mult $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}.mat -mult -o $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}.mat
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
c3d_affine_tool $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}.mat \
  -oitk $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_itk.txt
c3d_affine_tool $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}.mat -sqrt \
  -o $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_half.mat    -oitk $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_half_itk.txt
c3d_affine_tool $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_half.mat -inv \
  -o $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_halfinv.mat -oitk $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_half_inv_itk.txt
c3d_affine_tool $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}.mat -inv \
  -o $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_inv.mat     -oitk $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_inv_itk.txt

# resample to neutral space - incorporates initialization and subsequent flirt between T2 images
# generate trimmed images
c3d $WDIR/bltrim.nii.gz \
  -set-sform $WDIR/hwtrimspace.mat \
  $WDIR/bltrimdef.nii.gz -dilate 1 5x5x5mm -reslice-matrix $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_halfinv.mat \
  -trim 10mm -o $WRDIR/hwtrimdef_${GLOBALREGPROG}_${METRIC}.nii.gz \
  $WRDIR/hwtrimdef_${GLOBALREGPROG}_${METRIC}.nii.gz  $WDIR/bltrim.nii.gz \
  -reslice-matrix $WRDIR/om_${GLOBALREGPROG}_${METRIC}_halfinv.mat -o $WRDIR/${GLOBALREGPROG}_${METRIC}_bltrim_to_hw.nii.gz \
  $WRDIR/hwtrimdef_${GLOBALREGPROG}_${METRIC}.nii.gz  $WDIR/futrim_om.nii.gz \
  -reslice-matrix $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_half.mat -o $WRDIR/${GLOBALREGPROG}_${METRIC}_futrim_om_to_hw.nii.gz 

# Check if halfway mask contains the whole segmentation
maxdiff=`c3d  $SEG -trim 16mm -thresh 1 inf 1 0 -as M $WDIR/hwtrimdef_${GLOBALREGPROG}_${METRIC}.nii.gz -push M -reslice-matrix \
  $WRDIR/om_${GLOBALREGPROG}_RAS_${METRIC}_halfinv.mat -trim 10mm -binarize -scale -1 \
  -add -info-full   | grep "Intensity Range" | sed -e 's/]//g' | awk -F ',' {'print $2'}`
if [ $maxdiff -lt 0 ]; then
  echo "halfway mask doesn't contain the whole segmentation"
  exit -1;
fi
# Check if halfway mask is genus zero
c3d $WRDIR/hwtrimdef_${GLOBALREGPROG}_${METRIC}.nii.gz -connected-components -threshold 1 1 1 0 -dilate 1 2x2x2vox  -pad 1x1x1vox 1x1x1vox 0 \
  -o $WDIR/padded.nii.gz
genus=`CheckTopology $WDIR/padded.nii.gz | tail -1 | awk {'print $2'}`
if [ $genus != 0 ]; then
  echo "halfway mask is not a sphere"
  exit -1;
fi
rm -f $WDIR/padded.nii.gz

RSKIP1
