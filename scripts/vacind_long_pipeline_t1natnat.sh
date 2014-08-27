set -x
if [ -z $TMPDIR ]; then
  TMPDIR=$(mktemp -d)
fi
export side MODALITY GLOBALRIGIDPROG RIGIDMODE ASTEPSIZE METRIC GLOBALREGPROG USEMASK SYMMTYPE REGTYPE USEDEFMASK DEFREGPROG REGUL1 REGUL2 TMPDIR


FSLOUTPUTTYPE=NIFTI_GZ
BIN_ANTS=~srdas/bin/ants_avants
export FSLOUTPUTTYPE
WDIR=${WORK}/ibn_work_${side}
mkdir -p $WDIR

if [ "$INITTYPE" == "chunk" ]; then
  if [ "$MODALITY" == "TSE"  ]; then
  if [ ! -f ${WORK}/ibn_work_L/tse_long.mat ]; then
    if [ "$side" == "L" ]; then
      echo "Running whole brain global initialization"
      source ${ROOT}/scripts/bash/vacind_long_rigid_chunkinit.sh
    else
      echo "Expected to find global initialization, not found, perhaps you forgot to run left side first ?"
      exit -1
    fi 
  else
    echo "Skipping global initialization, already present"
      echo "Not skipping: Running whole brain global initialization"
      source ${ROOT}/scripts/bash/vacind_long_rigid_chunkinit.sh
  fi
  fi

  if [ "$MODALITY" == "MPRAGE"  ]; then
  if [ ! -f ${WORK}/ibn_work_L/mprage_long.mat ]; then
    if [ "$side" == "L" ]; then
      echo "Running whole brain global initialization"
      source ${ROOT}/scripts/bash/vacind_long_rigid_chunkinit.sh
    else
      echo "Expected to find global initialization, not found, perhaps you forgot to run left side first ?"
      exit -1
    fi 
  else
    echo "Skipping global initialization, already present"
  fi
  fi

elif [ "$INITTYPE" == "full" ]; then
  source ${ROOT}/scripts/bash/vacind_long_rigid_init.sh
else
  echo "Unknown initialization type"
  exit -1
fi

# Now we are ready to register followup T2 to baseline T2 with this initialization
# However, one task still remains -- we need to trim images in case we are using chunk-based global registration 
# (deformable registration is always chunk-based)

# Initialization matrix for T2
INITMAT=${WORK}/ibn_work_L/tse_long_RAS.mat
INITINVMAT=${WORK}/ibn_work_L/tse_long_RAS_inv.mat
# Initialization matrix for T1
MPINITMAT=${WORK}/ibn_work_L/mprage_long_RAS.mat
MPINITINVMAT=${WORK}/ibn_work_L/mprage_long_RAS_inv.mat

# FCD012 T1 init doesn't work, so trims are wrong, but T2 rigid still works. For trimming, use the full rigid matrix
# It is dangerous to use this hack. Make sure T1 init works and use it for trimming
# if [ -f ${WORK}/ibn_work_L/flirt/flirt_RAS_normcorr_asym.mat ]; then
#  INITMAT=${WORK}/ibn_work_L/flirt/flirt_RAS_normcorr_asym.mat
#  INITINVMAT=${WORK}/ibn_work_L/flirt/flirt_RAS_normcorr_asym_inv.mat
# fi

if [ "$MODALITY" == "MPRAGE"  ]; then
  c3d_affine_tool $MPINITMAT -inv -o $MPINITINVMAT
else
  c3d_affine_tool $INITMAT -inv -o $INITINVMAT
fi
# Create the inverse if the transform exists
if [ -f ${WORK}/ibn_work_L/bl_mprage_tse_RAS.mat ]; then
  c3d_affine_tool ${WORK}/ibn_work_L/bl_mprage_tse_RAS.mat -inv -o ${WORK}/ibn_work_L/bl_mprage_tse_RAS_inv.mat
  c3d_affine_tool ${WORK}/ibn_work_L/bl_mprage_tse_RAS.mat -oitk $WDIR/bl_mprage_tse_RAS_itk.txt
fi

if [ "$REGTYPE" == "chunk" ]; then
  WRDIR=$WDIR/${GLOBALREGPROG}_${REGTYPE}
  REGSUFF="_chunk"
else
  WRDIR=$WDIR/${GLOBALREGPROG}
  REGSUFF=""
fi

if [ "$MODALITY" == "TSE" ]; then
  mstr=""
  WRDIR=$WRDIR
else
  mstr="_mp"
  WRDIR=${WRDIR}${mstr}
fi

if [ "$ANTSVER" == "v3" ] ; then
  WDDIR=${WRDIR}/${METRIC}_${SYMMTYPE}_oldants_${ASTEPSIZE}_${REGUL1}_${REGUL2}
else
  # WDDIR=${WRDIR}/${METRIC}_${SYMMTYPE}_bsplinesyn
  WDDIR=${WRDIR}/${METRIC}_${SYMMTYPE}_${ASTEPSIZE}_${REGUL1}_${REGUL2}
fi
mkdir -p $WDDIR

# Create the trimmed images for ROI-based registration
# if [ ! -f $WRDIR/bltrim.nii.gz ] || [  ! -f $WRDIR/futrim.nii.gz ]; then
  # Create small images in baseline and followup image spaces copy this code to global registration script
  if [ -f $BLSEG ]; then 
    if [ "$MODALITY" == "TSE"  ]; then
      # Create TSE trimmed images
      c3d $BLGRAY -as BL $FUGRAY -as FU \
        $BLSEG -trim 16mm -sdt -smooth 4mm -thresh 0 inf 1 0 -as M \
        -push BL -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -reslice-identity \
        -trim 10mm -as SBL -o $WRDIR/bltrimdef.nii.gz \
        -push FU -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -reslice-matrix $INITINVMAT \
        -trim 10mm -as SFU -o $WRDIR/futrimdef.nii.gz \
        -push SBL -push BL -int NN -reslice-identity -o $WRDIR/bltrim.nii.gz \
        -push SFU -push FU -int NN -reslice-identity -o $WRDIR/futrim.nii.gz

      # Check if mask contains the whole segmentation
      maxdiff=`c3d  $BLSEG -trim 16mm -thresh 1 inf 1 0 -as M $WRDIR/bltrimdef.nii.gz -push M -reslice-identity \
        -trim 10mm -binarize -scale -1 \
        -add -info-full   | grep "Intensity Range" | sed -e 's/]//g' | awk -F ',' {'print $2'}`
      if [ $maxdiff -lt 0 ]; then
        echo "mask doesn't contain the whole segmentation"
        exit -1;
      fi
    else
      # Create MPRAGE trimmed images
      c3d $BLMPGRAY -as BL $FUMPGRAY -as FU \
        $BLSEG -trim 16mm -sdt -smooth 4mm -thresh 0 inf 1 0 -as M \
        -push BL -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm \
        -reslice-matrix ${WORK}/ibn_work_L/bl_mprage_tse_RAS_inv.mat \
        -trim 10mm -as SBL -o $WRDIR/blmptrimdef.nii.gz \
        -push FU -push SBL -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -reslice-matrix $MPINITINVMAT \
        -trim 10mm -as SFU -o $WRDIR/fumptrimdef.nii.gz \
        -push SBL -push BL -int NN -reslice-identity -o $WRDIR/blmptrim.nii.gz \
        -push SFU -push FU -int NN -reslice-identity -o $WRDIR/fumptrim.nii.gz
        BLSEG=$WRDIR/blmptrimdef.nii.gz
    fi
  else
    if [ -f $BLMPSEG ]; then
      # Create MPRAGE trimmed images
      c3d $BLMPGRAY -as BL $FUMPGRAY -as FU \
        $BLMPSEG -trim 16mm -sdt -smooth 4mm -thresh 0 inf 1 0 -as M \
        -push BL -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm \
        -trim 10mm -as SBL -o $WRDIR/blmptrimdef.nii.gz \
        -push FU -push SBL -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -reslice-matrix $MPINITINVMAT \
        -trim 10mm -as SFU -o $WRDIR/fumptrimdef.nii.gz \
        -push SBL -push BL -int NN -reslice-identity -o $WRDIR/blmptrim.nii.gz \
        -push SFU -push FU -int NN -reslice-identity -o $WRDIR/fumptrim.nii.gz
      
        if [ "$MODALITY" == "MPRAGE"  ]; then
          BLSEG=$WRDIR/blmptrimdef.nii.gz
        else
          c3d $BLGRAY -as BL $FUGRAY -as FU \
            $WRDIR/blmptrimdef.nii.gz -as M \
            -push BL -push M -interp NN -reslice-itk $WDIR/bl_mprage_tse_RAS_itk.txt -as SBL -o $WRDIR/bltrimdef.nii.gz \
            -push FU -push SBL -interp NN -reslice-matrix $INITINVMAT \
            -trim 10mm -as SFU -o $WRDIR/futrimdef.nii.gz \
            -push SBL -push BL -int NN -reslice-identity -o $WRDIR/bltrim.nii.gz \
            -push SFU -push FU -int NN -reslice-identity -o $WRDIR/futrim.nii.gz
          BLSEG=$WDIR/bltrimdef.nii.gz

        fi
    else
      TEMP_T1_FULL=~srdas/wd/ashs/data/template/template.nii.gz
      TEMP_T1_MASK=~srdas/wd/ashs/data/template/template_bet_mask.nii.gz
      if [ "$side" == "L" ]; then 
        sidestr="left";
      else 
        sidestr="right"; 
      fi;
      REFSPACE=~srdas/wd/ashs/data/template/refspace_${sidestr}.nii.gz
      if [ ! -f ${WORK}/ibn_work_L/ants_t1_to_tempAffine.txt ]; then
        $BIN_ANTS/ANTS 3 -m PR[$TEMP_T1_FULL,$BLMPGRAY,1,4] \
          --use-Histogram-Matching --number-of-affine-iterations 10000x10000x10000x10000x10000 \
          --affine-gradient-descent-option  0.5x0.95x1.e-4x1.e-4  --MI-option 32x16000 \
          -x $TEMP_T1_MASK \
          -o ${WORK}/ibn_work_L/ants_t1_to_temp.nii.gz \
          -i 200x120x40 -v -t SyN[0.5] | tee ${WORK}/ibn_work_L/ants_output.txt
      fi

      $BIN_ANTS/WarpImageMultiTransform 3 $REFSPACE $WDIR/blmpdef.nii.gz \
        -R $BLMPGRAY --use-NN \
        -i ${WORK}/ibn_work_L/ants_t1_to_tempAffine.txt ${WORK}/ibn_work_L/ants_t1_to_tempInverseWarp.nii.gz
      if [ "$MODALITY" == "MPRAGE"  ]; then

        c3d $BLMPGRAY -as BL $FUMPGRAY -as FU \
          $WDIR/blmpdef.nii.gz -as M \
          -push BL -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -int NN -reslice-identity -trim 10mm -as SBL -o $WRDIR/blmptrimdef.nii.gz \
          -push FU -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -reslice-matrix $MPINITINVMAT \
          -trim 10mm -as SFU -o $WRDIR/fumptrimdef.nii.gz \
          -push SBL -push BL -int NN -reslice-identity -o $WRDIR/blmptrim.nii.gz \
          -push SFU -push FU -int NN -reslice-identity -o $WRDIR/fumptrim.nii.gz
        

        BLSEG=$WDIR/blmpdef.nii.gz
      else
        $BIN_ANTS/WarpImageMultiTransform 3 $REFSPACE $WDIR/bldef.nii.gz \
          -R $BLGRAY $WDIR/bl_mprage_tse_RAS_itk.txt --use-NN \
          -i ${WORK}/ibn_work_L/ants_t1_to_tempAffine.txt ${WORK}/ibn_work_L/ants_t1_to_tempInverseWarp.nii.gz

        c3d $BLGRAY -as BL $FUGRAY -as FU \
          $WDIR/bldef.nii.gz -as M \
          -push BL -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -int NN -reslice-identity -trim 10mm -as SBL -o $WRDIR/bltrimdef.nii.gz \
          -push FU -push M -dilate 1 ${MASKRAD}x${MASKRAD}x${MASKRAD}mm -reslice-matrix $INITINVMAT \
          -trim 10mm -as SFU -o $WRDIR/futrimdef.nii.gz \
          -push SBL -push BL -int NN -reslice-identity -o $WRDIR/bltrim.nii.gz \
          -push SFU -push FU -int NN -reslice-identity -o $WRDIR/futrim.nii.gz

        BLSEG=$WDIR/bldef.nii.gz
      fi
    fi

  fi

  # QA of mask for deformable registration later

  if [ "$MODALITY" == "TSE"  ]; then
    TRIMMASK=$WRDIR/bltrimdef.nii.gz
  else
    TRIMMASK=$WRDIR/blmptrimdef.nii.gz
  fi
  # Check if mask is genus zero
  c3d $TRIMMASK -connected-components -threshold 1 1 1 0 -dilate 1 3x3x3vox  -pad 1x1x1vox 1x1x1vox 0 \
    -o $TMPDIR/padded.nii.gz
  genus=`CheckTopology $TMPDIR/padded.nii.gz | tail -1 | awk {'print $2'}`
  if [ $genus != 0 ]; then
   # Try again with larger dilation
   c3d $TRIMMASK -connected-components -threshold 1 1 1 0 -dilate 1 4x4x4vox  -pad 1x1x1vox 1x1x1vox 0 \
    -o $TMPDIR/padded.nii.gz
   genus=`CheckTopology $TMPDIR/padded.nii.gz | tail -1 | awk {'print $2'}`
   if [ $genus != 0 ]; then
    echo "mask is not a sphere"
    exit -1;
   fi
  fi


# fi

# if [ ! -f $BLSEG ]; then
#     BLSEG=$WDIR/bldef.nii.gz
# fi

if [ "$REGTYPE" == "chunk" ]; then
  if [ "$MODALITY" == "TSE"  ]; then
    BLGRAY=${WRDIR}/bltrim.nii.gz
    FUGRAY=${WRDIR}/futrim.nii.gz
    if [ ! -f ${WRDIR}/bltrimfullmask.nii.gz ] || [ ! -f ${WRDIR}/futrimfullmask.nii.gz ]; then
      c3d $BLGRAY -thresh -inf inf 1 0 -type uchar -o ${WRDIR}/bltrimfullmask.nii.gz
      c3d $FUGRAY -thresh -inf inf 1 0 -type uchar -o ${WRDIR}/futrimfullmask.nii.gz
    fi
  else
    BLGRAY=${WRDIR}/blmptrim.nii.gz
    FUGRAY=${WRDIR}/fumptrim.nii.gz
    if [ ! -f ${WRDIR}/blmptrimfullmask.nii.gz ] || [ ! -f ${WRDIR}/fumptrimfullmask.nii.gz ]; then
      c3d $BLMPGRAY -thresh -inf inf 1 0 -type uchar -o ${WRDIR}/blmptrimfullmask.nii.gz
      c3d $FUMPGRAY -thresh -inf inf 1 0 -type uchar -o ${WRDIR}/fumptrimfullmask.nii.gz
    fi

  fi
else
  echo "Not generating full masks"
  if [ "$MODALITY" == "TSE"  ]; then
    BLGRAY=$BLGRAY
    FUGRAY=$FUGRAY
:<<'NOMASK'
    if [ ! -f $LDIR/${id}/bl_tse_fullmask.nii.gz ] || [ ! -f $LDIR/${id}/fu_tse_fullmask.nii.gz ]; then
      c3d $BLGRAY   -thresh -inf inf 1 0 -o $LDIR/${id}/bl_tse_fullmask.nii.gz
      c3d $FUGRAY   -thresh -inf inf 1 0 -o $LDIR/${id}/fu_tse_fullmask.nii.gz
    fi
NOMASK
  else
    BLGRAY=$BLMPGRAY
    FUGRAY=$FUMPGRAY
:<<'NOMASK'
    if [ ! -f $LDIR/${id}/bl_mprage_fullmask.nii.gz ] || [ ! -f $LDIR/${id}/fu_mprage_fullmask.nii.gz ]; then
      c3d $BLMPGRAY   -thresh -inf inf 1 0 -o $LDIR/${id}/bl_mprage_fullmask.nii.gz
      c3d $FUMPGRAY   -thresh -inf inf 1 0 -o $LDIR/${id}/fu_mprage_fullmask.nii.gz
    fi
NOMASK

  fi
fi

RUNRIGID=true
if [ "$REGTYPE" == "full" ] && [  "${side}" == "R" ]; then
  mkdir -p ${WRDIR}
  RINITDIR=${WORK}/ibn_work_L/${GLOBALREGPROG}${mstr}
  ln -sf $RINITDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}.mat ${WRDIR}
  ln -sf $RINITDIR/${GLOBALREGPROG}_${METRIC}_${SYMMTYPE}.mat ${WRDIR}
  RUNRIGID=false
fi


# First do global registration
  if [ -f $WRDIR/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}.mat ]; then
   echo "Not Skipping global registration"
   source ${ROOT}/scripts/bash/vacind_long_global.sh
 else
   source ${ROOT}/scripts/bash/vacind_long_global.sh
   echo "global registration done"
 fi

# Now, in case global registration was with full images, then we need to define chunk images for deformable
if [ "$MODALITY" == "TSE"  ]; then
  BLGRAY=${WRDIR}/bltrim.nii.gz
  FUGRAY=${WRDIR}/futrim.nii.gz
  BLSPACE=${WRDIR}/bltrimdef.nii.gz
  FUSPACE=${WRDIR}/futrimdef.nii.gz
else
  BLGRAY=${WRDIR}/blmptrim.nii.gz
  FUGRAY=${WRDIR}/fumptrim.nii.gz
  BLSPACE=${WRDIR}/blmptrimdef.nii.gz
  FUSPACE=${WRDIR}/fumptrimdef.nii.gz
fi

# Now do deformable registration
if [ "$USEDEFMASK" == "0" ]; then
  defmaskopt=""
else
  defmaskopt="-m"
fi

if [ "$RESAMPLE" == "0" ]; then
  SUPERRES=""
else
  SUPERRES="-r $RESAMPLE"
fi

# :<<'COMM'

if [ "$RFIT" == "0" ]; then
echo "Starting deformable registration"
if [ "$ANTSVER" == "v3" ] ; then
  bash ${ROOT}/scripts/bash/vacind_long_deformable.sh -d \
     -b ${BLGRAY} \
     -c ${BLSPACE} \
     -e ${MODALITY} \
     -f ${FUGRAY} \
     -g ${FUSPACE} \
     -s ${BLSEG} \
     -w ${WDDIR} \
     -q ${DEFTYPE} \
     -n ${id}_${side} \
     -a ${WRDIR}/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}.mat $defmaskopt $SUPERRES
else
  bash ${ROOT}/scripts/bash/vacind_long_deformable_ITKv4.sh -d \
     -b ${BLGRAY} \
     -c ${BLSPACE} \
     -e ${MODALITY} \
     -f ${FUGRAY} \
     -g ${FUSPACE} \
     -s ${BLSEG} \
     -w ${WDDIR} \
     -q ${DEFTYPE} \
     -n ${id}_${side} \
     -a ${WRDIR}/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}.mat $defmaskopt $SUPERRES
fi


else

# If we want to fit a global transform to the deformable result, do it here followed by deformable registration again

if [ "$DEFTYPE" == 2 ]; then
  FITDEFTYPE=3
else
  FITDEFTYPE=$DEFTYPE
fi

ANTSUseDeformationFieldToGetAffineTransform ${WDDIR}/ants/antsreg${FITDEFTYPE}dWarp.nii.gz 0.2 rigid \
  ${WDDIR}/ants/antsreg${FITDEFTYPE}dWarpfit_itk.txt

c3d_affine_tool -itk ${WDDIR}/ants/antsreg${FITDEFTYPE}dWarpfit_itk.txt \
  -o ${WDDIR}/ants/antsreg${FITDEFTYPE}dWarpfit.mat \
  -inv -o ${WDDIR}/ants/antsreg${FITDEFTYPE}dWarpfit_inv.mat \
  -sqrt -o ${WDDIR}/ants/antsreg${FITDEFTYPE}dWarpfit_halfinv.mat \
  -inv -o ${WDDIR}/ants/antsreg${FITDEFTYPE}dWarpfit_half.mat


WDCDIR=${WRDIR}/${METRIC}_${SYMMTYPE}
mkdir -p $WDCDIR

c3d_affine_tool ${WDDIR}/omRAS_half.mat ${WDDIR}/ants/antsreg${FITDEFTYPE}dWarpfit.mat \
   ${WDDIR}/omRAS_half.mat -mult -mult -o ${WDCDIR}/omRAS_warpfit.mat

bash ${ROOT}/scripts/bash/vacind_long_deformable.sh -d \
     -b ${BLGRAY} \
     -c ${BLSPACE} \
     -e ${MODALITY} \
     -f ${FUGRAY} \
     -g ${FUSPACE} \
     -s ${BLSEG} \
     -w ${WDCDIR} \
     -q ${DEFTYPE} \
     -n ${id}_${side} \
     -o \
     -a ${WDCDIR}/omRAS_warpfit.mat $defmaskopt $SUPERRES
fi


# COMM
