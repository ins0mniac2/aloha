

# Now do measurements

ATRMODE="BL"
USEBNDMASK=false
USEPLABELMAP=true
USETHICK=false
USENATIVE=true
USEMESH=true
USEMASKOL=false
CLEANALL=true


WDIR=${WORK}/ibn_work_${side}
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
  mstr="mp"
  WRDIR=${WRDIR}_${mstr}
fi

#                 CA1/CA2/DG/ CA3/HEAD/TAIL/MISC/SUB/ERC/PHGP/PHGA  CA  /  ERPH        /HIPP          /BODY      /CA3DG /CA23DG      /ALL
#  P_LABELMAP="0:0;1:1;2:2;3:3;4:4;5:5;6:6;7:7;8:8;9:9;10:10;11:11;12:1,2,4;13:9,10,11;14:1,2,3,4,5,6,7;15:1,2,3,4,7;16:3,4;17:2,3,4;18:1,2,3,4,5,6,7,8,9,10,11;"
#                 CA1/CA2/DG/ CA3/HEAD/TAIL/MISC/SUB/ERCP/ERCA/BA35/BA36/CS   CA  /    ERC    /PRC      /HIPP           /ALL
  P_LABELMAP="0:0;1:1;2:2;3:3;4:4;5:5;6:6;7:7;8:8;9:9;10:10;11:11;12:12;13:13;14:1,2,4;15:9,10;16:11,12;17:1,2,3,4,5,6,7;18:1,2,3,4,5,6,7,8,9,10,11,12;"
  map=($(echo $P_LABELMAP | sed -e "s/;/ /g"))


if [ "$RFIT" == "0" ]; then
  if [ "$ANTSVER" == "v3" ] ; then
    WDCDIR=${WRDIR}/${METRIC}_${SYMMTYPE}_oldants_${ASTEPSIZE}_${REGUL1}_${REGUL2}
  else
    # WDCDIR=${WRDIR}/${METRIC}_${SYMMTYPE}_bsplinesyn
    WDCDIR=${WRDIR}/${METRIC}_${SYMMTYPE}_${ASTEPSIZE}_${REGUL1}_${REGUL2}
  fi
else
  WDCDIR=${WRDIR}/${METRIC}_${SYMMTYPE}_rfit_${ASTEPSIZE}_${REGUL1}_${REGUL2}
fi
WDDIR=$WDCDIR

if [ "$RESAMPLE" == "0" ]; then
  SUPERRES=""
else
  SUPERRES="-resample $RESAMPLE"
fi

# Image warping based long volume calculation
RESFILE=${WDDIR}/imwarp_longvol_${DEFTYPE}d.txt
rm -f $RESFILE
# Jacobian based long volume calculation
JACRESFILE=${WDDIR}/jac_longvol_${DEFTYPE}d.txt
  rm -f $JACRESFILE
  # tmpdir=`mktemp -d`
  tmpdir=${WDDIR}/debug1_${side}_${DEFTYPE}d
  # rm -rf $tmpdir
   mkdir -p $tmpdir
   rm -f $tmpdir/*
#  tmpdir=$TMPDIR

  BLSPACE=${WDDIR}/bltrimdef.nii.gz
  HWSPACE=${WDDIR}/hwtrimdef.nii.gz
  FUSPACE=${WDDIR}/futrim_om.nii.gz
  FUORIGSPACE=${WDDIR}/futrim.nii.gz
  MESHTRIM=2
  MESHRES=500
  BLTSESEG=$BLSEG
  if [ "$MODALITY" == "MPRAGE" ]; then
    MESHTRIM=10
    MESHRES=100
    # T1 subfield estimation
    if [ "$DOMPSUB" == "1" ]; then
      BLSEG=$BLMPSUBSEG
      BLSPACE=$BLMPSUBSEG
      c3d $HWSPACE -resample 500% -o ${tmpdir}/hwspace.nii.gz
      c3d $FUSPACE -resample 500% -o ${tmpdir}/fuspace.nii.gz
      HWSPACE=${tmpdir}/hwspace.nii.gz
      FUSPACE=${tmpdir}/fuspace.nii.gz
      cp $BLSEG $tmpdir/blseg.nii.gz
    else  
      if $ALTMODESEG; then
        BLSEG=$BLTSESEG
        c3d $BLSEG $WDDIR/futrimdef_om_to_bltrim_warped_3d.nii.gz -interp NN -reslice-identity $BLSEG -times -o $tmpdir/blseg.nii.gz
      else
        BLSEG=$BLMPSEG
        FUSEG=$FUMPSEG
        cp $BLSEG $tmpdir/blseg.nii.gz
      fi
      if $USENATIVE; then
        echo "Measuring in native T1 space"
      else
        echo "Measuring in highres/pm T1 space"
        BLSPACE=$BLMPSUBSEG
        c3d $HWSPACE -resample 500% -o ${tmpdir}/hwspace.nii.gz
        c3d $FUSPACE -resample 500% -o ${tmpdir}/fuspace.nii.gz
        HWSPACE=${tmpdir}/hwspace.nii.gz
        FUSPACE=${tmpdir}/fuspace.nii.gz
      fi
    fi
  else
    if $ALTMODESEG; then
      if [ "$DOMPSUB" == "1" ]; then
        BLSEG=$BLMPSUBSEG
      else
        BLSEG=$BLMPSEG
      fi
      cp $BLSEG $tmpdir/blseg.nii.gz
    else
      BLSEG=$BLTSESEG
      # Mask with FU image coverage
      c3d $BLSEG $WDDIR/futrimdef_om_to_bltrim_warped_3d.nii.gz -interp NN -reslice-identity $BLSEG -times -o $tmpdir/blseg.nii.gz
    fi
  fi

  BLSEG=$tmpdir/blseg.nii.gz

  # We need to limit the baseline segmentation over which longitudinal measurements are made to the region in which followup image
  # has been imaged. Later on, this should be implemented as the common region where both scans are acquired when reciprocal measuremeants are made.

  llist=($(c3d $BLSEG $BLSEG -lstat | grep -v LabelID | awk '{print $1}'))
  LABELMAP=''
  for ((i=0; i < ${#llist[*]}; i++)); do 
    LABELMAP="$LABELMAP $i ${llist[i]}"
  done

  if $ALTMODESEG; then
    if [ "$MODALITY" == "TSE" ]; then
      RESLICECOMM="-reslice-matrix ${WDDIR}/../../../ibn_work_L/bl_mprage_tse_RAS.mat"
    else
      c3d_affine_tool ${WDDIR}/../../../ibn_work_L/bl_mprage_tse_RAS.mat -inv -o ${tmpdir}/bl_tse_mprage_RAS.mat
      RESLICECOMM="-reslice-matrix ${tmpdir}/bl_tse_mprage_RAS.mat"
    fi
  else
    RESLICECOMM="-reslice-identity"
  fi

  c3d $BLSPACE $BLSEG -interp NN -reslice-identity -o $WDDIR/segbl.nii.gz

  # If we want to mask baseline seg by common coverage
  if $USEMASKOL; then
    for ((i=0; i < ${#llist[*]}; i++)); do 
      BLORIG=($(c3d $BLSPACE -info-full | head -n 3 | tail -n 1 | sed -e "s/.*{\[//" -e "s/\],.*//"))
      c3d $FUORIGSPACE $FUSEG -interp NN -reslice-identity -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm -o $WDIR/fuseg_om.nii.gz

      c3d $FUSPACE $WDIR/fuseg_om.nii.gz \
        -thresh ${llist[i]} ${llist[i]} 1 0  -smooth 0.24mm $RESLICECOMM \
        -o ${tmpdir}/fulabel`printf %02d ${llist[i]}`.nii.gz

      c3d $BLSPACE $WDIR/fuseg_om.nii.gz \
        -thresh ${llist[i]} ${llist[i]} 1 0  -reslice-matrix ${WDDIR}/omRAS.mat \
        -o ${tmpdir}/fulabelbl`printf %02d ${llist[i]}`.nii.gz

      c3d $HWSPACE ${tmpdir}/fulabel`printf %02d ${llist[i]}`.nii.gz \
        -reslice-matrix ${WDDIR}/omRAS_half.mat \
        -o ${tmpdir}/fulabelhw`printf %02d ${llist[i]}`.nii.gz
    done
    # Warning: assuming followup segmentation has the same label set as the baseline. Sometimes a small label may be absent (like CA2/3)
    # Won't matter unless using individual labels matching by numbers
    c3d ${tmpdir}/fulabelhw??.nii.gz -vote -o ${WDDIR}/fuseghw.nii.gz
    c3d ${tmpdir}/fulabelbl??.nii.gz -vote -o ${WDDIR}/fusegbl.nii.gz
    c3d ${WDDIR}/fuseghw.nii.gz -replace $LABELMAP -o ${WDDIR}/fuseghw.nii.gz
    # Change BLSEG by common mask
    c3d ${WDDIR}/segbl.nii.gz ${WDDIR}/fusegbl.nii.gz -overlap 1
    c3d $BLSPACE $BLSEG -interp NN $RESLICECOMM ${WDDIR}/fusegbl.nii.gz -times -thresh 1 inf 1 0 $BLSEG -o $BLSEG
    
  fi

  # Map segmentation to halfway space
  for ((i=0; i < ${#llist[*]}; i++)); do 
    c3d $BLSPACE $BLSEG \
      -thresh ${llist[i]} ${llist[i]} 1 0  -smooth 0.24mm $RESLICECOMM \
      -o ${tmpdir}/label`printf %02d ${llist[i]}`.nii.gz


    c3d $HWSPACE ${tmpdir}/label`printf %02d ${llist[i]}`.nii.gz \
      -reslice-matrix ${WDDIR}/omRAS_halfinv.mat \
      -o ${tmpdir}/labelhw`printf %02d ${llist[i]}`.nii.gz
  done

  LIDX=0
  LREP=""
  # Create ROI labels to use for P_LABELMAP measurements
  for ((i=0; i < ${#map[*]}; i++)); do
    imap=${map[i]}
    LOUT=${imap%:*}
    LSRC=${imap#*:}
    CMD[i]=""
    for trg in `echo $LSRC | sed -e "s/,/ /g"`; do
      CMD[i]="${CMD[i]} $trg inf"
    done

    ID=`printf %02i $LIDX`;
    # ********************** check if we need ${CMD[i]} here
    c3d $BLSPACE $BLSEG -replace $CMD -thresh inf inf 1 0 -smooth 0.24mm $RESLICECOMM \
      -o ${tmpdir}/roilabel${ID}.nii.gz
    c3d $HWSPACE ${tmpdir}/roilabel${ID}.nii.gz \
      -reslice-matrix ${WDDIR}/omRAS_halfinv.mat \
      -o ${tmpdir}/roilabelhw${ID}.nii.gz
    
    LREP="$LREP $((LIDX++)) $LOUT"

  done

  c3d ${tmpdir}/labelhw??.nii.gz -vote -o ${WDDIR}/seghw.nii.gz
  c3d ${WDDIR}/seghw.nii.gz -replace $LABELMAP -o ${WDDIR}/seghw.nii.gz


  if [ "$ATRMODE" == "HW" ]; then
    llist=($(c3d ${WDDIR}/seghw.nii.gz ${WDDIR}/seghw.nii.gz -lstat | grep -v LabelID | awk '{print $1}'))
    LABELMAP=''
    for ((i=0; i < ${#llist[*]}; i++)); do 
      LABELMAP="$LABELMAP $i ${llist[i]}"
    done
  fi
  if [ "$ATRMODE" == "BL" ]; then
    llist=($(c3d ${WDDIR}/segbl.nii.gz ${WDDIR}/segbl.nii.gz -lstat | grep -v LabelID | awk '{print $1}'))
    LABELMAP=''
    for ((i=0; i < ${#llist[*]}; i++)); do 
      LABELMAP="$LABELMAP $i ${llist[i]}"
    done
  fi
  # This doesn't work for missing labels 
  # c3d $BLSPACE -popas BB $BLSEG -split -foreach -smooth 0.24mm -insert BB 1 -reslice-identity -endfor \
  # -oo ${tmpdir}/label%02d.nii.gz 

  export id side BLGRAY FUGRAY BLMPGRAY FUMPGRAY BLSEG FUSEG BLHRGRAY FUHRGRAY BLHRSEG FUHRSEG WORK INITTYPE DEFTYPE METRIC GLOBALREGPROG USEMASK SYMMTYPE REGTYPE USEDEFMASK MASKRAD


  if $USEPLABELMAP; then
    nROI=${#map[*]}
  else
    nROI=11
  fi

  unset SFBL SFFU JACSFBL JACSFFU

  is3d=`echo "$DEFTYPE > 2" | bc`
  if [ $is3d == 1 ]; then
    
  MANRESFILE=${WDDIR}/manual_longvol.txt
  rm -f $MANRESFILE
  c3d $BLSPACE $BLSEG -interp NN $RESLICECOMM -o ${WDDIR}/segbltrim.nii.gz
  for ((i=0; i<nROI; i++)) ; do
    SFBL[i]=0
    SFFU[i]=0
    MANSFBL[i]=0
    MANSFFU[i]=0
    JACSFBL[i]=0
    JACSFFU[i]=0
  done

  # Calculate Jacobian  
  ANTSJacobian 3 ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp.nii.gz ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}d
  gzip -f ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dgrid.nii ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii
  if [ "$MODALITY" == "MPRAGE" ]; then
    if [ "$DOMPSUB" == "1" -o "$ALTMODESEG" == "true" ]; then
      c3d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz -resample 500% -o ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz
    fi
  fi

  # Map Jacobian to template space
  if [ "$MODALITY" == "TSE" ]; then
    if [ "$side" == "L" ]; then
      lside="left"
    WTHK=${LDIR}/${id}/sfseglatest/${bltp}/thickness/caphg/$lside
#    TEMPLATE=$HOME/wd/ashs/data/template/roi/consensus_${lside}_caphg.nii.gz
#    WarpImageMultiTransform 3 ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian_to_template.nii.gz \
#      -R $TEMPLATE $WTHK/roi_antsWarp.nii.gz $WTHK/roi_antsAffine.txt ${WDDIR}/omRAS_half_itk.txt   
#    tetsample ${LDIR}/template/consensus_${side}_caphg_tet.vtk ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian_to_template.vtk \
#      ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian_to_template.nii.gz jacobian
    else
      lside="right"
    fi
  else
    echo "Mapping Jacobian for T1 deformation field to PM template TODO"
  fi

  if [ "$DEFREGPROG" == "ants" ]; then
    for ((l=0; l < ${#llist[*]}; l++)); do 
      i=`printf %02d ${llist[l]}` 
      if [ "$RIGIDMODE" == "HW" ]; then
        WarpImageMultiTransform 3 ${tmpdir}/label${i}.nii.gz ${tmpdir}/warpedlabel${i}_${DEFTYPE}d.nii.gz -R $FUSPACE \
          ${WDDIR}/omRAS_half_inv_itk.txt ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz ${WDDIR}/omRAS_half_inv_itk.txt; 
        WarpImageMultiTransform 3 ${tmpdir}/labelhw${i}.nii.gz ${tmpdir}/warpedlabelhw${i}_${DEFTYPE}d.nii.gz -R $HWSPACE \
          ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz;
      else
        WarpImageMultiTransform 3 ${tmpdir}/label${i}.nii.gz ${tmpdir}/warpedlabel${i}_${DEFTYPE}d.nii.gz -R $FUSPACE \
          ${WDDIR}/omRAS_inv_itk.txt ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz;
      fi
    done
    for ((l=0; l<nROI; l++)) ; do
      i=`printf %02d ${l}`
      if [ "$RIGIDMODE" == "HW" ]; then
        WarpImageMultiTransform 3 ${tmpdir}/roilabel${i}.nii.gz ${tmpdir}/warpedroilabel${i}_${DEFTYPE}d.nii.gz -R $FUSPACE \
          ${WDDIR}/omRAS_half_inv_itk.txt ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz ${WDDIR}/omRAS_half_inv_itk.txt; 
        WarpImageMultiTransform 3 ${tmpdir}/roilabelhw${i}.nii.gz ${tmpdir}/warpedroilabelhw${i}_${DEFTYPE}d.nii.gz -R $HWSPACE \
          ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz;
      else
        WarpImageMultiTransform 3 ${tmpdir}/roilabel${i}.nii.gz ${tmpdir}/warpedroilabel${i}_${DEFTYPE}d.nii.gz -R $FUSPACE \
          ${WDDIR}/omRAS_inv_itk.txt ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz;
      fi
    done


    c3d ${tmpdir}/warpedlabel??_${DEFTYPE}d.nii.gz -vote -o ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz
    c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -replace  $LABELMAP -o ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz

    if [ "$RIGIDMODE" == "HW" ]; then
      c3d ${tmpdir}/warpedlabelhw??_${DEFTYPE}d.nii.gz -vote -o ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz
      c3d ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz -replace  $LABELMAP -o ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz
    fi
  fi


  # Baseline volume measurements
  unset BLSF BLVOLS FUSF FUVOLS FULIST JACBLVOLS JACFUVOLS
  if [[ "$RIGIDMODE" == "HW" && "$ATRMODE" == "HW" ]]; then
    if $USEPLABELMAP; then
      for ((l=0; l<nROI; l++)) ; do
        i=`printf %02d ${l}`
        BLSF[l]=$l
        BLVOLS[l]=`c3d ${WDDIR}/seghw.nii.gz -replace ${CMD[l]} -thresh inf inf 1 0 -voxel-sum | awk '{print $3}'`
        if [ "${BLVOLS[l]}" == "" ]; then BLVOLS[l]=0; fi
      done
    else
      BLSF=(`c3d ${WDDIR}/seghw.nii.gz ${WDDIR}/seghw.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
      BLVOLS=(`c3d ${WDDIR}/seghw.nii.gz ${WDDIR}/seghw.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
    fi
  else
    if $USEPLABELMAP; then
      for ((l=0; l<nROI; l++)) ; do
        i=`printf %02d ${l}`
        BLSF[l]=$l
        BLVOLS[l]=`c3d ${WDDIR}/segbltrim.nii.gz -replace ${CMD[l]} -thresh inf inf 1 0 -voxel-sum | awk '{print $3}'`
        if [ "${BLVOLS[l]}" == "" ]; then BLVOLS[l]=0; fi
      done
    else
      BLSF=(`c3d ${WDDIR}/segbltrim.nii.gz ${WDDIR}/segbltrim.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
      BLVOLS=(`c3d ${WDDIR}/segbltrim.nii.gz ${WDDIR}/segbltrim.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
    fi
  fi

  # Followup volume measurements
  if [ "$DEFREGPROG" == "ants" ]; then
    if [ "$RIGIDMODE" == "HW" ]; then
      if $USEPLABELMAP; then
        for ((l=0; l<nROI; l++)) ; do
          i=`printf %02d ${l}`
          FUSF[l]=$l
          FUVOLS[l]=`c3d ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz -replace ${CMD[l]} -thresh inf inf 1 0 -voxel-sum | awk '{print $3}'`
          if [ "${FUVOLS[l]}" == "" ]; then FUVOLS[l]=0; fi
        done
      else
        FUSF=(`c3d ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
        FUVOLS=(`c3d ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
      fi
    else
      if $USEPLABELMAP; then
        for ((l=0; l<nROI; l++)) ; do
          i=`printf %02d ${l}`
          FUSF[l]=$l
          FUVOLS[l]=`c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -replace ${CMD[l]} -thresh inf inf 1 0 -voxel-sum | awk '{print $3}'`
          if [ "${FUVOLS[l]}" == "" ]; then FUVOLS[l]=0; fi
        done
      else
        FUSF=(`c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
        FUVOLS=(`c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
      fi
    fi
  fi
  MANBLVOLS=(`c3d $BLSEG $BLSEG -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
  MANFUVOLS=(`c3d $FUSEG $FUSEG -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
  JACBLVOLS=$BLVOLS
  if [ "$RIGIDMODE" == "HW" ]; then
      if $USEPLABELMAP; then
        for ((l=0; l<nROI; l++)) ; do
          i=`printf %02d ${l}`
          FULIST[l]=$l
          JACFUVOLS[l]=`c3d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz ${WDDIR}/seghw.nii.gz -replace ${CMD[l]} -thresh inf inf 1 0 -times -voxel-sum | awk '{print $3}'`
          if [ "${JACFUVOLS[l]}" == "" ]; then JACFUVOLS[l]=0; fi
        done
      else
        JACFUVOLS=(`c3d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz -popas J ${WDDIR}/seghw.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  
        FULIST=($( c3d ${WDDIR}/seghw.nii.gz -dup -lstat | sed -n -e '3,$p' | awk '{print $1}'))
      fi
  else
      if $USEPLABELMAP; then
        for ((l=0; l<nROI; l++)) ; do
          i=`printf %02d ${l}`
          FULIST[l]=$l
          JACFUVOLS[l]=`c3d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz ${WDDIR}/segbltrim.nii.gz -replace ${CMD[l]} -thresh inf inf 1 0 -times -voxel-sum | awk '{print $3}'`
          if [ "${JACFUVOLS[l]}" == "" ]; then JACFUVOLS[l]=0; fi
        done
      else
        JACFUVOLS=(`c3d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz -popas J ${WDDIR}/segbltrim.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  
        FULIST=($( c3d ${WDDIR}/segbltrim.nii.gz -dup -lstat | sed -n -e '3,$p' | awk '{print $1}'))
      fi
  fi

  for ((j=0; j<${#BLVOLS[*]}; j++)) ; do
      sfi=${BLSF[j]}
      SFBL[sfi]=${BLVOLS[j]}
      MANSFBL[sfi]=${MANBLVOLS[j]}
      MANSFFU[sfi]=${MANFUVOLS[j]}
      JACSFBL[sfi]=${BLVOLS[j]}
      THISFUVOL=0
      for((ii=0;ii<${#FULIST[*]};ii++)); do
        if [ ${FULIST[$ii]} -eq $sfi ]; then
          THISFUVOL=${JACFUVOLS[ii]}
        fi
      done  
      JACSFFU[sfi]=$THISFUVOL
  done
  if [ "$DEFREGPROG" == "ants" ]; then
    for ((j=0; j<${#FUVOLS[*]}; j++)) ; do
      sfi=${FUSF[j]}
      SFFU[sfi]=${FUVOLS[j]}
    done
  fi
  
  for ((i=1; i<nROI; i++)) ; do
    if [ "$DEFREGPROG" == "ants" ]; then
      ATR=$( echo "( ${SFBL[i]} -  ${SFFU[i]})/${SFBL[i]} " | bc -l )
      echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFBL[i]} ${SFFU[i]} $ATR $grp >> $RESFILE
    fi
    if [ -f $FUSEG ]; then
      ATR=$( echo "( ${MANSFBL[i-1]} -  ${MANSFFU[i-1]})/${MANSFBL[i-1]} " | bc -l )
      echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${MANSFBL[i-1]} ${MANSFFU[i-1]} $ATR $grp >> $MANRESFILE
    fi
    ATR=$( echo "( ${JACSFBL[i]} -  ${JACSFFU[i]})/${JACSFBL[i]} " | bc -l )
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${JACSFBL[i]} ${JACSFFU[i]} $ATR $grp >> $JACRESFILE
  done
# ----------------------------------------------------------------------------------------------------
else # is3d = 0, 2D registration
  # Reslice each label to HW space and combine for HW segmentation

# This doesn't work for missing labels 
#  c3d $HWSPACE -popas HW ${tmpdir}/label??.nii.gz \
#    -foreach -insert HW 1 -reslice-matrix ${WDDIR}/omRAS_halfinv.mat -endfor \
#    -oo ${tmpdir}/labelhw%02d.nii.gz

  if [ "$RIGIDMODE" == "HW" ]; then
    zsize=`c3d $HWSPACE -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
  else
    zsize=`c3d $BLSPACE -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
  fi
  for ((i=0; i<nROI; i++)) ; do
    SFBL[i]=0
    SFFU[i]=0
    JACSFBL[i]=0
    JACSFFU[i]=0
  done

  # Don't use the boundary slices
  zsize=$(expr $zsize - 1) 
  for ((i=1; i < ${zsize}; i++)) do
    ANTSJacobian 2 ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warp.nii.gz ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}
    gzip -f ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}grid.nii ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}jacobian.nii
    for ((l=0; l < ${#llist[*]}; l++)); do 
      sf=`printf %02d ${llist[l]}` 
      # Create the label image for the slice and warp it 
      if [ "$RIGIDMODE" == "HW" ]; then
        c3d ${tmpdir}/labelhw${sf}.nii.gz -slice z $i -o ${tmpdir}/labelhw${sf}_${i}.nii.gz
        c2d ${tmpdir}/labelhw${sf}_${i}.nii.gz -o ${tmpdir}/labelhw${sf}_${i}.nii.gz
        c2d ${tmpdir}/labelhw${sf}_${i}.nii.gz $SUPERRES -o ${tmpdir}/labelhw${sf}_${i}.nii.gz
      else
        c3d ${tmpdir}/label${sf}.nii.gz -slice z $i -o ${tmpdir}/label${sf}_${i}.nii.gz
        c2d ${tmpdir}/label${sf}_${i}.nii.gz -o ${tmpdir}/label${sf}_${i}.nii.gz
        c2d ${tmpdir}/label${sf}_${i}.nii.gz $SUPERRES -o ${tmpdir}/label${sf}_${i}.nii.gz
      fi
      if [ "$DEFREGPROG" == "ants" ]; then
        if [ "$RIGIDMODE" == "HW" ]; then
          WarpImageMultiTransform 2 ${tmpdir}/labelhw${sf}_${i}.nii.gz ${tmpdir}/warpedlabelhw${sf}_${i}.nii.gz -R ${WDDIR}/hwtrimdef_${i}.nii.gz \
            ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}InverseWarp.nii.gz
          c2d ${tmpdir}/warpedlabelhw${sf}_${i}.nii.gz -o ${tmpdir}/warpedlabelhw${sf}_${i}.nii.gz
        else
          WarpImageMultiTransform 2 ${tmpdir}/label${sf}_${i}.nii.gz ${tmpdir}/warpedlabel${sf}_${i}.nii.gz -R ${WDDIR}/bltrimdef_${i}.nii.gz \
            ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}InverseWarp.nii.gz
          c2d ${tmpdir}/warpedlabel${sf}_${i}.nii.gz -o ${tmpdir}/warpedlabel${sf}_${i}.nii.gz

        fi
      fi
    done
    for ((j=0; j<nROI; j++)) ; do
      sf=`printf %02d ${j}`
      if [ "$RIGIDMODE" == "HW" ]; then
        c3d ${tmpdir}/roilabelhw${sf}.nii.gz -slice z $i -o ${tmpdir}/roilabelhw${sf}_${i}.nii.gz
        c2d ${tmpdir}/roilabelhw${sf}_${i}.nii.gz -o ${tmpdir}/roilabelhw${sf}_${i}.nii.gz
        c2d ${tmpdir}/roilabelhw${sf}_${i}.nii.gz $SUPERRES -o ${tmpdir}/roilabelhw${sf}_${i}.nii.gz
      else
        c3d ${tmpdir}/roilabel${sf}.nii.gz -slice z $i -o ${tmpdir}/roilabel${sf}_${i}.nii.gz
        c2d ${tmpdir}/roilabel${sf}_${i}.nii.gz -o ${tmpdir}/roilabel${sf}_${i}.nii.gz
        c2d ${tmpdir}/roilabel${sf}_${i}.nii.gz $SUPERRES -o ${tmpdir}/roilabel${sf}_${i}.nii.gz
      fi
      if [ "$DEFREGPROG" == "ants" ]; then
        if [ "$RIGIDMODE" == "HW" ]; then
          WarpImageMultiTransform 2 ${tmpdir}/roilabelhw${sf}_${i}.nii.gz ${tmpdir}/warpedroilabelhw${sf}_${i}.nii.gz -R ${WDDIR}/hwtrimdef_${i}.nii.gz \
            ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}InverseWarp.nii.gz
          c2d ${tmpdir}/warpedroilabelhw${sf}_${i}.nii.gz -o ${tmpdir}/warpedroilabelhw${sf}_${i}.nii.gz
        else
          WarpImageMultiTransform 2 ${tmpdir}/roilabel${sf}_${i}.nii.gz ${tmpdir}/warpedroilabel${sf}_${i}.nii.gz -R ${WDDIR}/bltrimdef_${i}.nii.gz \
            ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}InverseWarp.nii.gz
          c2d ${tmpdir}/warpedroilabel${sf}_${i}.nii.gz -o ${tmpdir}/warpedroilabel${sf}_${i}.nii.gz
        fi
      fi
    done

    # Vote to create original and warped segmentation for each slice
    if [ "$RIGIDMODE" == "HW" ]; then
      c2d ${tmpdir}/labelhw??_${i}.nii.gz -vote -o ${WDDIR}/seghw_${i}.nii.gz
      c2d ${WDDIR}/seghw_${i}.nii.gz -replace  $LABELMAP -o ${WDDIR}/seghw_${i}.nii.gz
      if [ "$DEFREGPROG" == "ants" ]; then
        c2d ${tmpdir}/warpedlabelhw??_${i}.nii.gz -vote -o ${WDDIR}/seghwwarped_${i}.nii.gz
        c2d ${WDDIR}/seghwwarped_${i}.nii.gz -replace $LABELMAP -o ${WDDIR}/seghwwarped_${i}.nii.gz
      fi
    else
      c2d ${tmpdir}/label??_${i}.nii.gz -vote -o ${WDDIR}/segbltrim_${i}.nii.gz
      c2d ${WDDIR}/segbltrim_${i}.nii.gz -replace  $LABELMAP -o ${WDDIR}/segbltrim_${i}.nii.gz
      if [ "$DEFREGPROG" == "ants" ]; then
        c2d ${tmpdir}/warpedlabel??_${i}.nii.gz -vote -o ${WDDIR}/segwarped_${i}.nii.gz
        c2d ${WDDIR}/segwarped_${i}.nii.gz -replace $LABELMAP -o ${WDDIR}/segwarped_${i}.nii.gz
      fi
    fi
    if $USEBNDMASK ; then
      c2d ${tmpdir}/labelhw01_${i}.nii.gz -thresh 0.3 1.0 nan 1 -o ${tmpdir}/invmasklabelhw01_${i}.nii.gz
      MASKOPT="${tmpdir}/invmasklabelhw01_${i}.nii.gz -times -replace nan 1"
    else
      MASKOPT=""
    fi

    unset BLSF BLVOLS FUSF FUVOLS FULIST JACBLVOLS JACFUVOLS
    if [ "$RIGIDMODE" == "HW" ]; then
      if $USEPLABELMAP; then
        for ((j=0; j<nROI; j++)) ; do
          sf=`printf %02d ${j}`
          BLSF[j]=$j
          BLVOLS[j]=`c2d ${WDDIR}/seghw_${i}.nii.gz -replace ${CMD[j]} -thresh inf inf 1 0 -voxel-sum | awk '{print $3}'`
          if [ "${BLVOLS[j]}" == "" -o "${BLVOLS[j]}" == "nan" ]; then BLVOLS[j]=0; fi
          if [ "$DEFREGPROG" == "ants" ]; then
            FUSF[j]=$j
            FUVOLS[j]=`c2d ${WDDIR}/seghwwarped_${i}.nii.gz -replace ${CMD[j]} -thresh inf inf 1 0 -voxel-sum | awk '{print $3}'`
            if [ "${FUVOLS[j]}" == "" -o "${BLVOLS[j]}" == "0" -o "${FUVOLS[j]}" == "nan" ]; then FUVOLS[j]=0; BLVOLS[j]=0; fi
          fi
          JACBLVOLS[j]=${BLVOLS[j]}
          JACFUVOLS[j]=`c2d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}jacobian.nii.gz $MASKOPT ${WDDIR}/seghw_${i}.nii.gz -replace ${CMD[j]} -thresh inf inf 1 0 -times -voxel-sum | awk '{print $3}'`
          if [ "${JACFUVOLS[j]}" == "" -o "${BLVOLS[j]}" == "0" -o "${JACFUVOLS[j]}" == "nan" ]; then JACFUVOLS[j]=0; JACBLVOLS[j]=0; fi
        done
      else
        BLSF=(`c2d ${WDDIR}/seghw_${i}.nii.gz ${WDDIR}/seghw_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
        BLVOLS=(`c2d ${WDDIR}/seghw_${i}.nii.gz ${WDDIR}/seghw_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
        if [ "$DEFREGPROG" == "ants" ]; then
          FUSF=(`c2d ${WDDIR}/seghwwarped_${i}.nii.gz ${WDDIR}/seghwwarped_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
          FUVOLS=(`c2d ${WDDIR}/seghwwarped_${i}.nii.gz ${WDDIR}/seghwwarped_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
        fi
        JACBLVOLS=(`c2d ${WDDIR}/seghw_${i}.nii.gz ${WDDIR}/seghw_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
        JACFUVOLS=(`c2d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}jacobian.nii.gz $MASKOPT -popas J ${WDDIR}/seghw_${i}.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  
      fi
    else
      if $USEPLABELMAP; then
        for ((j=0; j<nROI; j++)) ; do
          sf=`printf %02d ${j}`
          BLSF[j]=$j
          BLVOLS[j]=`c2d ${WDDIR}/segbltrim_${i}.nii.gz -replace ${CMD[j]} -thresh inf inf 1 0 -voxel-sum | awk '{print $3}'`
          if [ "${BLVOLS[j]}" == "" -o "${BLVOLS[j]}" == "nan" ]; then BLVOLS[j]=0; fi
          if [ "$DEFREGPROG" == "ants" ]; then
            FUSF[j]=$j
            FUVOLS[j]=`c2d ${WDDIR}/segwarped_${i}.nii.gz -replace ${CMD[j]} -thresh inf inf 1 0 -voxel-sum | awk '{print $3}'`
            if [ "${FUVOLS[j]}" == "" -o "${BLVOLS[j]}" == "0" -o "${FUVOLS[j]}" == "nan" ]; then FUVOLS[j]=0; BLVOLS[j]=0; fi
          fi
          JACBLVOLS[j]=${BLVOLS[j]}
          JACFUVOLS[j]=`c2d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}jacobian.nii.gz $MASKOPT ${WDDIR}/segbltrim_${i}.nii.gz -replace ${CMD[j]} -thresh inf inf 1 0 -times -voxel-sum | awk '{print $3}'`
          if [ "${JACFUVOLS[j]}" == "" -o "${BLVOLS[j]}" == "0" -o "${JACFUVOLS[j]}" == "nan" ]; then JACFUVOLS[j]=0; JACBLVOLS[j]=0; fi
        done
      else
        BLSF=(`c2d ${WDDIR}/segbltrim_${i}.nii.gz ${WDDIR}/segbltrim_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
        BLVOLS=(`c2d ${WDDIR}/segbltrim_${i}.nii.gz ${WDDIR}/segbltrim_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
        if [ "$DEFREGPROG" == "ants" ]; then
          FUSF=(`c2d ${WDDIR}/segwarped_${i}.nii.gz ${WDDIR}/segwarped_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
          FUVOLS=(`c2d ${WDDIR}/segwarped_${i}.nii.gz ${WDDIR}/segwarped_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
        fi
        JACBLVOLS=(`c2d ${WDDIR}/segbltrim_${i}.nii.gz ${WDDIR}/segbltrim_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
        JACFUVOLS=(`c2d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}jacobian.nii.gz $MASKOPT -popas J ${WDDIR}/segbltrim_${i}.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  
      fi

    fi


    for ((j=0; j<${#BLVOLS[*]}; j++)) ; do
      sfi=${BLSF[j]}
      SFBL[sfi]=`echo "${SFBL[${sfi}]} + ${BLVOLS[j]}" | bc`
      if [ "${JACBLVOLS[j]}" == "nan" -o "${JACFUVOLS[j]}" == "" -o "${JACBLVOLS[j]}" == "0" -o "${JACFUVOLS[j]}" == "nan" ]; then JACFUVOLS[j]=0; JACBLVOLS[j]=0; fi
      JACSFBL[sfi]=`echo "${JACSFBL[${sfi}]} + ${JACBLVOLS[j]}" | bc`
      JACSFFU[sfi]=`echo "${JACSFFU[${sfi}]} + ${JACFUVOLS[j]}" | bc`
    done
    if [ "$DEFREGPROG" == "ants" ]; then
      for ((j=0; j<${#FUVOLS[*]}; j++)) ; do
        sfi=${FUSF[j]}
        if [ "${BLVOLS[j]}" == "nan" -o "${FUVOLS[j]}" == "" -o "${BLVOLS[j]}" == "0" -o "${FUVOLS[j]}" == "nan" ]; then FUVOLS[j]=0; BLVOLS[j]=0; fi
        SFFU[sfi]=`echo "${SFFU[${sfi}]} + ${FUVOLS[j]}" | bc`
      done
    fi
  done
  for ((i=1; i<nROI; i++)) ; do
    if [ "$DEFREGPROG" == "ants" ]; then
      ATR=$( echo "( ${SFBL[i]} -  ${SFFU[i]})/${SFBL[i]} " | bc -l )
      echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFBL[i]} ${SFFU[i]} $ATR $grp >> $RESFILE
    fi
    ATR=$( echo "( ${JACSFBL[i]} -  ${JACSFFU[i]})/${JACSFBL[i]} " | bc -l )
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${JACSFBL[i]} ${JACSFFU[i]} $ATR $grp >> $JACRESFILE
  done
#  rm -rf ${tmpdir}
fi

# code snippet for adding up volume of a subfield over the slices
# for ((i=0 ; i<24; i++)); do vol=`c2d seghw_${i}.nii.gz  seghw_${i}.nii.gz -lstat | sed -e "s/^[ \t]*//" | grep "^1 " | awk '{print $6}'`; echo $vv $vol;if [ ! -z $vol ]; then vv=`echo "${vv} + ${vol}" | bc`; fi;done

: << 'SKIP3'
# levelset smoothing and warping
RESFILE=${WDIR}/imwarp_longvol.txt
rm -f $RESFILE
rm -f /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}*label*.nii.gz
c3d $BLSPACE $BLSEG -int NN -reslice-identity -o ${WDIR}/segbltrim.nii.gz
c3d ${WDIR}/segbltrim.nii.gz -split -oo /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}_label%02d.nii.gz
for i in 00 01 02 03 04 05 06 07 08 09 10; do
  c3d /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}_label${i}.nii.gz -as A -thresh 1 1 1 -1 -push A -thresh 1 1 -1 1\
  -levelset-curvature 0.2  -levelset 200 -o /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}_labelsm${i}.nii.gz
  WarpImageMultiTransform 3 /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}_labelsm${i}.nii.gz \
  /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}_warpedlabelsm${i}.nii.gz -R ${WDIR}/futrim_om.nii.gz \
   ${WDIR}/omRAS_half_inv_itk.txt ${WDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz ${WDIR}/omRAS_half_inv_itk.txt;
done
c3d /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}_warpedlabelsm??.nii.gz -foreach -scale -1 -endfor -vote -o ${WDIR}/segfutrim_om.nii.gz
BLVOLS=(`c3d ${WDIR}/segbltrim.nii.gz ${WDIR}/segbltrim.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
FUVOLS=(`c3d ${WDIR}/segfutrim_om.nii.gz ${WDIR}/segfutrim_om.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
for ((i=0; i<${#BLVOLS[*]}; i++)) ; do
  echo $id `expr $i + 1` ${BLVOLS[i]} ${FUVOLS[i]} >> $RESFILE
done


SKIP3

if $USEMESH; then

# Mesh warping and thickness based long volume calculation
RESFILE=${WDDIR}/meshwarp_longvol_${DEFTYPE}d.txt
THKFILE=${WDDIR}/meshwarp_longthick_${DEFTYPE}d.txt
rm -f $RESFILE
rm -f $THKFILE

if $USEPLABELMAP; then
  nl=nROI
else
  nl=${#llist[*]}
fi
if [ $is3d == 1 ]; then
  for ((i=0; i<nROI; i++)) ; do
    SFBL[i]=0
    SFFU[i]=0
    SFTBL[i]=0
    SFTFU[i]=0
  done

  for ((l=0; l<nl; l++)) ; do
    if $USEPLABELMAP ; then
      if [ ${l} -eq 0 ]; then
        continue
      fi
    else
      if [ ${llist[l]} -eq 0 ]; then
        continue
      fi
    fi
    
      if $USEPLABELMAP; then
        i=`printf %02d $l`;
        THRESHCMD="-replace ${CMD[l]} -thresh inf inf 1 0"
        sfi=$l
      else
        i=`printf %02d ${llist[l]}`
        THRESHCMD="-thresh ${llist[l]} ${llist[l]} 1 0"
        sfi=${llist[l]}
      fi
   # Create image to create mesh from
      # baseline space baseline measurement
#    c3d ${WDDIR}/segbltrim.nii.gz -interp NN -resample 100x100x500% -as M \
#        -interp linear -thresh ${llist[l]} ${llist[l]} 1 -1 -push M -thresh ${llist[l]} ${llist[l]} -1 1  \
#        -levelset-curvature 1.2 -levelset 400 -scale -1 -shift 4 -o ${tmpdir}/labellevelset${i}.nii.gz
#    ~pauly/bin/vtklevelset ${tmpdir}/labellevelset${i}.nii.gz ${tmpdir}/label${i}.vtk 4.0

      # halfway space baseline measurement
      # c3d ${WDDIR}/seghw.nii.gz -thresh ${llist[l]} ${llist[l]} 1 0 \
      #   -int Gaussian 0.2x0.2x1.0mm -trim 10x10x2vox -resample 100x100x500% -thresh 0.5 inf 1 0 \
      #   -pad 1x1x1vox 1x1x1vox 0 -o ${tmpdir}/labelbinarytarget${i}.nii.gz
      # ~pauly/bin/vtklevelset ${tmpdir}/labelbinarytarget${i}.nii.gz ${tmpdir}/label${i}.vtk 0.5
  
      labelmissing=false
      if [[ "$RIGIDMODE" == "HW" && "$ATRMODE" == "HW" ]]; then
# No Gaussian interpolation
        c3d ${WDDIR}/seghw.nii.gz $THRESHCMD \
          -trim 10x10x${MESHTRIM}vox -resample 100x100x${MESHRES}% -thresh 0.5 inf 1 0 \
          -pad 1x1x1vox 1x1x1vox 0 -o ${tmpdir}/labelhwbinarytarget${i}.nii.gz

# Why this Gaussian interpolation ? This decimates small subfields. For T2, it didn't as much because of 500% resampling in z
# -int Gaussian 0.2x0.2x1.0mm

        blrange=`c3d ${tmpdir}/labelhwbinarytarget${i}.nii.gz -info | cut -f 4 -d ";" | cut -f 2 -d "="`
        if [ "$blrange" == " [0, 0]" ]; then labelmissing=true; fi;
        # Get the largest connected component
        ~pauly/bin/c3d ${tmpdir}/labelhwbinarytarget${i}.nii.gz -comp -thresh 1 1 1 0 -o ${tmpdir}/labelhwbinarytarget${i}.nii.gz
        ~pauly/bin/vtklevelset ${tmpdir}/labelhwbinarytarget${i}.nii.gz ${tmpdir}/labelhw${i}.vtk 0.5
      else
# No Gaussian interpolation
        c3d ${WDDIR}/segbltrim.nii.gz $THRESHCMD \
          -trim 10x10x${MESHTRIM}vox -resample 100x100x${MESHRES}% -thresh 0.5 inf 1 0 \
          -pad 1x1x1vox 1x1x1vox 0 -o ${tmpdir}/labelbinarytarget${i}.nii.gz
        blrange=`c3d ${tmpdir}/labelbinarytarget${i}.nii.gz -info | cut -f 4 -d ";" | cut -f 2 -d "="`
        if [ "$blrange" == " [0, 0]" ]; then labelmissing=true; fi;
        # Get the largest connected component
        ~pauly/bin/c3d ${tmpdir}/labelbinarytarget${i}.nii.gz -comp -thresh 1 1 1 0 -o ${tmpdir}/labelbinarytarget${i}.nii.gz
        ~pauly/bin/vtklevelset ${tmpdir}/labelbinarytarget${i}.nii.gz ${tmpdir}/label${i}.vtk 0.5
      fi
      if $labelmissing; then
        BLVOL=0;
        FUVOL=0;
        THICKBL=0;
        THICKFU=0;
      else
      
        if $USETHICK; then
          # Compute skeleton at baseline
          if [[ "$RIGIDMODE" == "HW" && "$ATRMODE" == "HW" ]]; then
            ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
              -I ${tmpdir}/labelhwbinarytarget${i}.nii.gz ${tmpdir}/labelhwthickness${i}.nii.gz ${tmpdir}/labelhwdepthmap${i}.nii.gz  \
              ${tmpdir}/labelhw${i}.vtk ${tmpdir}/labelhwskeleton${i}.vtk
          else
            ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
              -I ${tmpdir}/labelbinarytarget${i}.nii.gz ${tmpdir}/labelthickness${i}.nii.gz ${tmpdir}/labeldepthmap${i}.nii.gz  \
              ${tmpdir}/label${i}.vtk ${tmpdir}/labelskeleton${i}.vtk
          fi

          # Compute thickness 
          if [[ "$RIGIDMODE" == "HW" && "$ATRMODE" == "HW" ]]; then
            THICKBL=`~srdas/bin/cmrep/mesharrstat ${tmpdir}/labelhwskeleton${i}.vtk Radius`   
          else
            THICKBL=`~srdas/bin/cmrep/mesharrstat ${tmpdir}/labelskeleton${i}.vtk Radius`   
          fi

          #  rm -f ${tmpdir}/labellevelset${i}.nii.gz
          # Move the mesh to the halfway point
          # ~srdas/bin/cmrep/warpmesh ${tmpdir}/label${i}.vtk ${tmpdir}/label_2hw${i}.vtk $WDDIR/omRAS_half.mat

          # Apply the warp to the mesh
          # baseline space baseline measurements
          # ~srdas/bin/cmrep/warpmesh -w ants ${tmpdir}/label_2hw${i}.vtk ${tmpdir}/warpedlabel${i}.vtk $WDDIR/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp?vec.nii.gz
        else
          THICKBL=0;
        fi
        if [[ "$RIGIDMODE" == "HW" && "$ATRMODE" == "HW" ]]; then
          ~srdas/bin/cmrep/warpmesh -w ants ${tmpdir}/labelhw${i}.vtk ${tmpdir}/warpedlabelhw${i}.vtk $WDDIR/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp?vec.nii.gz
        elif [[ "$RIGIDMODE" == "HW" && "$ATRMODE" == "BL" ]]; then
          ~srdas/bin/cmrep/warpmesh ${tmpdir}/label${i}.vtk ${tmpdir}/label_2hw${i}.vtk $WDDIR/omRAS_half.mat
          ~srdas/bin/cmrep/warpmesh -w ants ${tmpdir}/label_2hw${i}.vtk ${tmpdir}/warpedlabel${i}.vtk $WDDIR/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp?vec.nii.gz
          # Crashes for 009_S_2208, it appears that Paul's version doesn't crash so try it but it doesn't report stats
          # ~pauly/bin/warpmesh -w ants ${tmpdir}/label_2hw${i}.vtk ${tmpdir}/warpedlabel${i}.vtk $WDDIR/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp?vec.nii.gz
          ~srdas/bin/cmrep/warpmesh ${tmpdir}/warpedlabel${i}.vtk ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk $WDDIR/omRAS_half.mat
        else
          ~srdas/bin/cmrep/warpmesh -w ants ${tmpdir}/label${i}.vtk ${tmpdir}/warpedlabel${i}.vtk $WDDIR/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp?vec.nii.gz
          ~srdas/bin/cmrep/warpmesh ${tmpdir}/warpedlabel${i}.vtk ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk $WDDIR/omRAS.mat
        fi
      
        if $USETHICK; then

          if [[ "$RIGIDMODE" == "HW" && "$ATRMODE" == "HW" ]]; then
            # Compute skeleton at followup -- from original warped image mask or from warped mesh ? Do it from warped mesh
            ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
              ${tmpdir}/warpedlabelhw${i}.vtk ${tmpdir}/warpedlabelhwskeleton${i}.vtk
            # Compute thickness 
            THICKFU=`~srdas/bin/cmrep/mesharrstat ${tmpdir}/warpedlabelhwskeleton${i}.vtk Radius`   
          else
            # Compute skeleton at followup -- from original warped image mask or from warped mesh ? Do it from warped mesh
            ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
              ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk ${tmpdir}/warpedlabel_to_futrim_omskeleton${i}.vtk
            # Compute thickness 
            THICKFU=`~srdas/bin/cmrep/mesharrstat ${tmpdir}/warpedlabel_to_futrim_omskeleton${i}.vtk Radius`   
          fi
        else
          THICKFU=0;
        fi

:<<'NOMESHWARP'
      # Compute skeleton at followup -- from original warped image mask or from warped mesh ? Do it from warped image mask
      c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -thresh ${llist[l]} ${llist[l]} 1 0 \
        -int Gaussian 0.2x0.2x1.0mm -trim 10x10x2vox -resample 100x100x400% -thresh 0.5 inf 1 0 \
        -pad 1x1x1vox 1x1x1vox 0 -o ${tmpdir}/warpedlabelbinarytarget${i}.nii.gz
      ~pauly/bin/vtklevelset ${tmpdir}/warpedlabelbinarytarget${i}.nii.gz ${tmpdir}/warpedlabelimage${i}.vtk 0.5

      # Compute skeleton at followup
      ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
        -I ${tmpdir}/warpedlabelbinarytarget${i}.nii.gz ${tmpdir}/warpedlabelthickness${i}.nii.gz ${tmpdir}/warpedlabeldepthmap${i}.nii.gz  \
        ${tmpdir}/warpedlabelimage${i}.vtk ${tmpdir}/warpedlabelimageskeleton${i}.vtk


      # Compute thickness 
      THICKFU=`~srdas/bin/cmrep/mesharrstat ${tmpdir}/warpedlabelimageskeleton${i}.vtk Radius`   
NOMESHWARP

        # Compute volume
        # baseline space
        # BLVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/label${i}.vtk ${tmpdir}/label${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
        # FUVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
        # halfway space
        if [[ "$RIGIDMODE" == "HW" && "$ATRMODE" == "HW" ]]; then
       #   BLVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/labelhw${i}.vtk ${tmpdir}/labelhw${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
       #   FUVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/warpedlabelhw${i}.vtk ${tmpdir}/warpedlabelhw${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
          BLVOL=`~pauly/bin/vtkmeshvol ${tmpdir}/labelhw${i}.vtk | awk '{print $4}'`
          FUVOL=`~pauly/bin/vtkmeshvol ${tmpdir}/warpedlabelhw${i}.vtk | awk '{print $4}'`
        else
       #   BLVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/label${i}.vtk ${tmpdir}/label${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
       #   FUVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
          BLVOL=`~pauly/bin/vtkmeshvol ${tmpdir}/label${i}.vtk | awk '{print $4}'`
          FUVOL=`~pauly/bin/vtkmeshvol ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk | awk '{print $4}'`
        fi
      fi

:<<'NOMATLAB'
/home/local/matlab_r2009b/bin/matlab -nodisplay -singleCompThread <<MAT2
  mesh=vtk_polydata_read(char('${tmpdir}/labelskeleton${i}.vtk'));
  rad=vtk_get_point_data(mesh, 'Radius');
  thickbl=median(rad);

  mesh=vtk_polydata_read(char('${tmpdir}/warpedlabelskeleton${i}.vtk'));
  rad=vtk_get_point_data(mesh, 'Radius');
  thickfu=median(rad);

  fd=fopen('${tmpdir}/thick${i}.txt');
  fprintf(fd,'%f %f\n', thickbl, thickfu);
  fclose(fd);

MAT2
    
NOMATLAB

      SFBL[sfi]=$BLVOL
      SFFU[sfi]=$FUVOL
      SFTBL[sfi]=$THICKBL
      SFTFU[sfi]=$THICKFU
      #  rm -f /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}_${sf}*.vtk

  done
  for ((i=1; i<nROI; i++)) ; do
    ATR=$( echo "( ${SFBL[i]} -  ${SFFU[i]})/${SFBL[i]} " | bc -l )
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFBL[i]} ${SFFU[i]} $ATR $grp >> $RESFILE
    ATR=$( echo "( ${SFTBL[i]} -  ${SFTFU[i]})/${SFTBL[i]} " | bc -l )
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFTBL[i]} ${SFTFU[i]} $ATR $grp >> $THKFILE
  done

else # 2d mesh
  
  if [ "$RIGIDMODE" == "HW" ]; then
    zsize=`c3d $HWSPACE -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
  else
    zsize=`c3d $BLSPACE -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
  fi
  
  for ((i=0; i<nROI; i++)) ; do
    SFBL[i]=0
    SFFU[i]=0
  done

  # Don't use the boundary slices
  zsize=$(expr $zsize - 1) 
  for ((i=1; i < ${zsize}; i++)) do
    for ((l=0; l<nl; l++)) ; do
      if $USEPLABELMAP ; then
        if [ ${l} -eq 0 ]; then
          continue
        fi
      else
        if [ ${llist[l]} -eq 0 ]; then
          continue
        fi
      fi

      if $USEPLABELMAP; then
        sf=`printf %02d $l`;
        sfi=$l
        THRESHCMD="-replace ${CMD[l]} -thresh inf inf 1 0"
      else
        sf=`printf %02d ${llist[l]}`
        THRESHCMD="-thresh ${llist[l]} ${llist[l]} 1 0"
        sfi=${llist[l]}
      fi



      if [ "$RIGIDMODE" == "HW" ]; then
        # c2d ${tmpdir}/labelhw${sf}_${i}.nii.gz -o ${tmpdir}/labelhw${sf}_${i}.nii.gz
        c2d ${WDDIR}/seghw_${i}.nii.gz $THRESHCMD -o ${tmpdir}/labelhw${sf}_${i}.nii.gz
        c2d ${tmpdir}/labelhw${sf}_${i}.nii.gz $SUPERRES -o ${tmpdir}/labelhw${sf}_${i}.nii.gz
      
        # Get the contour
        vtkcontour ${tmpdir}/labelhw${sf}_${i}.nii.gz ${tmpdir}/labelhw${sf}_${i}_contour.vtk 0.5
      else
        # c2d ${tmpdir}/label${sf}_${i}.nii.gz -o ${tmpdir}/label${sf}_${i}.nii.gz
        c2d ${WDDIR}/segbltrim_${i}.nii.gz $THRESHCMD -o ${tmpdir}/label${sf}_${i}.nii.gz
        c2d ${tmpdir}/label${sf}_${i}.nii.gz $SUPERRES -o ${tmpdir}/label${sf}_${i}.nii.gz
      
        # Get the contour
        vtkcontour ${tmpdir}/label${sf}_${i}.nii.gz ${tmpdir}/label${sf}_${i}_contour.vtk 0.5
      fi

      # if [[ $USEBNDMASK && "$sf" == "01" ]]; then
      if $USEBNDMASK ; then
        MASKOPT="-n ${tmpdir}/labelhw01_${i}.nii.gz 0.3"
      else
        MASKOPT=""
      fi
      if [ "$RIGIDMODE" == "HW" ]; then
        # Is there any contour ?
        nPoints=`grep POINTS ${tmpdir}/labelhw${sf}_${i}_contour.vtk | awk '{print $2}'`
        if [ $nPoints -ne 0 ]; then

          # Triangulate the contour
          contour2surf ${tmpdir}/labelhw${sf}_${i}_contour.vtk ${tmpdir}/labelhw${sf}_${i}_trimesh.vtk zYpq32a0.1

          # Warp the mesh
          AREA_STATS=`warpmesh -w ants $MASKOPT ${tmpdir}/labelhw${sf}_${i}_trimesh.vtk ${tmpdir}/labelhw${sf}_${i}_warpedtrimesh.vtk \
            ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warp?vec.nii.gz | grep AREA_STATS`
        
          BLVOL=`echo $AREA_STATS | awk '{print $2}'`    
          FUVOL=`echo $AREA_STATS | awk '{print $3}'`

          if [ "${BLVOL}" == "nan" -o "${FUVOL}" == "" -o "${BLVOL}" == "0" -o "${FUVOL}" == "nan" ]; then FUVOL=0; BLVOL=0; fi

          echo $sf $BLVOl $FUVOL ${SFBL[${llist[l]}]} ${SFFU[${llist[l]}]}

          SFBL[sfi]=`echo "${SFBL[${sfi}]} + ${BLVOL}" | bc`     
          SFFU[sfi]=`echo "${SFFU[${sfi}]} + ${FUVOL}" | bc`     

        fi
      else
        # Is there any contour ?
        nPoints=`grep POINTS ${tmpdir}/label${sf}_${i}_contour.vtk | awk '{print $2}'`
        if [ $nPoints -ne 0 ]; then

          # Triangulate the contour
          contour2surf ${tmpdir}/label${sf}_${i}_contour.vtk ${tmpdir}/label${sf}_${i}_trimesh.vtk zYpq32a0.1

          # Warp the mesh
          AREA_STATS=`warpmesh -w ants $MASKOPT ${tmpdir}/label${sf}_${i}_trimesh.vtk ${tmpdir}/label${sf}_${i}_warpedtrimesh.vtk \
            ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warp?vec.nii.gz | grep AREA_STATS`
        
          BLVOL=`echo $AREA_STATS | awk '{print $2}'`    
          FUVOL=`echo $AREA_STATS | awk '{print $3}'`

          if [ "${BLVOL}" == "nan" -o "${FUVOL}" == "" -o "${BLVOL}" == "0" -o "${FUVOL}" == "nan" ]; then FUVOL=0; BLVOL=0; fi

          echo $sf $BLVOl $FUVOL ${SFBL[${llist[l]}]} ${SFFU[${llist[l]}]}

          SFBL[sfi]=`echo "${SFBL[${sfi}]} + ${BLVOL}" | bc`     
          SFFU[sfi]=`echo "${SFFU[${sfi}]} + ${FUVOL}" | bc`     
        fi

      fi
    done
  done  
  for ((i=1; i<nROI; i++)) ; do
    ATR=$( echo "( ${SFBL[i]} -  ${SFFU[i]})/${SFBL[i]} " | bc -l )
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFBL[i]} ${SFFU[i]} $ATR $grp >> $RESFILE
  done
  
fi

fi # USEMESH
# while true
# do
#   echo "Press [CTRL+C] to stop.."
#   sleep 1000
# done
 

# Clean up
rm -f $WRDIR/reslice*nii.gz $WDDIR/regdiff* $WDDIR/ants/antsreg3d0*nii.gz $WDDIR/ants/antsreg*grid.nii.gz $WRDIR/futrim_om_to_hw_warped_3d_ITKv4.nii.gz

if $CLEANALL; then
  rm -f $WDDIR/ants/antsreg* $WDDIR/../*nii.gz $WDDIR/../../*nii.gz $WDDIR/bltrimdef.nii.gz $WDDIR/bltrim.nii.gz  $WDDIR/futrimdef.nii.gz $WDDIR/futrim.nii.gz $WDDIR/futrim_om.nii.gz $WDDIR/futrim_om_to_bltrim_warped_3d.nii.gz $WDDIR/hwtrimdef.nii.gz $WDDIR/segbltrim.nii.gz $WDDIR/segfutrim_om_3d.nii.gz  $WDDIR/seghwwarped_3d.nii.gz
fi

date
