#!/bin/bash
#$ -S /bin/bash
set -x -e

date

# Verify all the necessary inputs
cat <<-BLOCK1
	Script: vacind_long_pipeline_qsub.sh
	Subject: ${id?}
	Root: ${ROOT?}
	Longdir: ${LDIR?}
	Working directory: ${WORK?}
	PATH: ${PATH?}
	SIDE: ${side?}
	GROUP: ${grp?}
	BLTIME: ${bltp?}
	FUTIME: ${tp?}
        FLAVOR: ${FLAVOR?}
        INITTYPE: ${INITTYPE?}
        DEFTYPE: ${DEFTYPE?}
        METRIC: ${METRIC?}
        GLOBALREGPROG: ${GLOBALREGPROG?}
        REGTYPE: ${REGTYPE?}
        USEMASK: ${USEMASK?}
        USEDEFMASK: ${USEDEFMASK?}
        MASKRAD: ${MASKRAD?}
        RESAMPLE: ${RESAMPLE?}
        RFIT: ${RFIT?}
        ASTEPSIZE: ${ASTEPSIZE?}
        DEFREGPROG: ${DEFREGPROG?}
        RIGIDMODE: ${RIGIDMODE?}
        MODALITY: ${MODALITY?}
        ALTMODESEG: ${ALTMODESEG?}
        DOMPSUB: ${DOMPSUB?}
        SEGALT: ${SEGALT?}
        TIMEPOINT: ${TIMEPOINT?}
        ANTSVER: ${ANTSVER?}
        REGUL1: ${REGUL2?}
        REGUL2: ${REGUL2?}
BLOCK1

# Define Rater 
RATER=JP

# Define smoothing
SM="0.24mm"

if [ "$SEGALT" == "orig" ]; then
  SEGALT=""
fi

# Define the raw images
BLGRAY=$LDIR/${id}/${bltp}_${id}_tse.nii.gz
FUGRAY=$LDIR/${id}/${tp}_${id}_tse.nii.gz
BLMPGRAY=$LDIR/${id}/${bltp}_${id}_mprage.nii.gz
FUMPGRAY=$LDIR/${id}/${tp}_${id}_mprage.nii.gz
BLSEG=$LDIR/${id}/${bltp}_${id}_${SEGALT}subseg_${side}.nii.gz
FUSEG=$LDIR/${id}/${tp}_${id}_${SEGALT}subseg_${side}.nii.gz
BLLSEG=$LDIR/${id}/${bltp}_${id}_${SEGALT}subseg_L.nii.gz
FULSEG=$LDIR/${id}/${tp}_${id}_${SEGALT}subseg_L.nii.gz
BLRSEG=$LDIR/${id}/${bltp}_${id}_${SEGALT}subseg_R.nii.gz
FURSEG=$LDIR/${id}/${tp}_${id}_${SEGALT}subseg_R.nii.gz
BLMPSEG=$LDIR/${id}/${bltp}_${id}_hippseg_${side}.nii.gz
FUMPSEG=$LDIR/${id}/${tp}_${id}_hippseg_${side}.nii.gz
BLMPLSEG=$LDIR/${id}/${bltp}_${id}_hippseg_L.nii.gz
FUMPLSEG=$LDIR/${id}/${tp}_${id}_hippseg_L.nii.gz
BLMPRSEG=$LDIR/${id}/${bltp}_${id}_hippseg_R.nii.gz
FUMPRSEG=$LDIR/${id}/${tp}_${id}_hippseg_R.nii.gz
BLMPSUBSEG=$LDIR/${id}/${bltp}_${id}_t1subseg_${side}.nii.gz
FUMPSUBSEG=$LDIR/${id}/${tp}_${id}_t1subseg_${side}.nii.gz
BLMPLSUBSEG=$LDIR/${id}/${bltp}_${id}_t1subseg_L.nii.gz
FUMPLSUBSEG=$LDIR/${id}/${tp}_${id}_t1subseg_L.nii.gz
BLMPRSUBSEG=$LDIR/${id}/${bltp}_${id}_t1subseg_R.nii.gz
FUMPRSUBSEG=$LDIR/${id}/${tp}_${id}_t1subseg_R.nii.gz

# Bias corrected
# BLMPGRAY=$LDIR/${id}/${bltp}/tissueseg/t1biascorrected.nii.gz
# FUMPGRAY=$LDIR/${id}/${tp}/tissueseg/t1biascorrected.nii.gz

if [ ! -f $LDIR/${id}/bl_tse_fullmask.nii.gz -a -f $BLGRAY ]; then
  c3d $BLGRAY   -thresh -inf inf 1 0 -o $LDIR/${id}/bl_tse_fullmask.nii.gz
fi
if [ ! -f $LDIR/${id}/fu_tse_fullmask.nii.gz -a -f $BLGRAY ]; then
  c3d $FUGRAY   -thresh -inf inf 1 0 -o $LDIR/${id}/fu_tse_fullmask.nii.gz
fi


# Resample to isotropic
BLHRGRAY=${WORK}/${bltp}_${id}_tse_hires.nii.gz
FUHRGRAY=${WORK}/${tp}_${id}_tse_hires.nii.gz
BLHRSEG=${WORK}/${bltp}_${id}_seg_${side}_hires.nii.gz
FUHRSEG=${WORK}/${tp}_${id}_seg_${side}_hires.nii.gz

export id side BLGRAY FUGRAY BLMPGRAY FUMPGRAY BLSEG FUSEG BLMPSEG FUMPSEG BLHRGRAY FUHRGRAY BLHRSEG FUHRSEG WORK INITTYPE DEFTYPE METRIC GLOBALREGPROG USEMASK SYMMTYPE REGTYPE USEDEFMASK MASKRAD RESAMPLE RFIT ASTEPSIZE DEFREGPROG RIGIDMODE DOMPSUB ALTMODESEG ANTSVER REGUL1 REGUL2

# Registration is done by the script
 source ${ROOT}/scripts/bash/vacind_long_pipeline_${FLAVOR}_test.sh



# Now do measurements
 source ${ROOT}/scripts/bash/vacind_long_measurements_test.sh



:<<'NORUN'
WDIR=${WORK}/ibn_work_${side}
if [ "$REGTYPE" == "chunk" ]; then
  WRDIR=$WDIR/${GLOBALREGPROG}_${REGTYPE}
  REGSUFF="_chunk"
else
  WRDIR=$WDIR/${GLOBALREGPROG}
  REGSUFF=""
fi

if [ "$RFIT" == "0" ]; then
  WDCDIR=${WRDIR}/${METRIC}_${SYMMTYPE}
else
  WDCDIR=${WRDIR}/${METRIC}_${SYMMTYPE}_rfit
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
JACRESFILE=${WDDIR}/jac_longvol_${DEFTYPE}d.txt
rm -f $JACRESFILE
# tmpdir=`mktemp -d`
tmpdir=${WDDIR}/debug
# rm -rf $tmpdir
mkdir -p $tmpdir
tmpdir=$TMPDIR

llist=($(c3d $BLSEG $BLSEG -lstat | grep -v LabelID | awk '{print $1}'))
LABELMAP=''
for ((i=0; i < ${#llist[*]}; i++)); do 
  LABELMAP="$LABELMAP $i ${llist[i]}"
done

# Map segmentation to halfway space
for ((i=0; i < ${#llist[*]}; i++)); do 
  c3d ${WDDIR}/bltrimdef.nii.gz $BLSEG \
    -thresh ${llist[i]} ${llist[i]} 1 0  -smooth 0.24mm -reslice-identity \
    -o ${tmpdir}/label`printf %02d ${llist[i]}`.nii.gz

  c3d ${WDDIR}/hwtrimdef.nii.gz ${tmpdir}/label`printf %02d ${llist[i]}`.nii.gz \
    -reslice-matrix ${WDDIR}/omRAS_halfinv.mat \
    -o ${tmpdir}/labelhw`printf %02d ${llist[i]}`.nii.gz
done

c3d ${tmpdir}/labelhw??.nii.gz -vote -o ${WDDIR}/seghw.nii.gz
  
c3d ${WDDIR}/seghw.nii.gz -replace $LABELMAP -o ${WDDIR}/seghw.nii.gz

# This doesn't work for missing labels 
# c3d ${WDDIR}/bltrimdef.nii.gz -popas BB $BLSEG -split -foreach -smooth 0.24mm -insert BB 1 -reslice-identity -endfor \
# -oo ${tmpdir}/label%02d.nii.gz 

export id side BLGRAY FUGRAY BLMPGRAY FUMPGRAY BLSEG FUSEG BLHRGRAY FUHRGRAY BLHRSEG FUHRSEG WORK INITTYPE DEFTYPE METRIC GLOBALREGPROG USEMASK SYMMTYPE REGTYPE USEDEFMASK MASKRAD

is3d=`echo "$DEFTYPE > 2" | bc`
if [ $is3d == 1 ]; then
  
  MANRESFILE=${WDDIR}/manual_longvol.txt
  rm -f $MANRESFILE
  c3d ${WDDIR}/bltrimdef.nii.gz $BLSEG -interp NN -reslice-identity -o ${WDDIR}/segbltrim.nii.gz
  for ((i=0; i<11; i++)) ; do
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
  if [ "$DEFREGPROG" == "ants" ]; then
    for ((l=0; l < ${#llist[*]}; l++)); do 
      i=`printf %02d ${llist[l]}` 
      if [ "$RIGIDMODE" == "HW" ]; then
        WarpImageMultiTransform 3 ${tmpdir}/label${i}.nii.gz ${tmpdir}/warpedlabel${i}_${DEFTYPE}d.nii.gz -R ${WDDIR}/futrim_om.nii.gz \
          ${WDDIR}/omRAS_half_inv_itk.txt ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz ${WDDIR}/omRAS_half_inv_itk.txt; 
        WarpImageMultiTransform 3 ${tmpdir}/labelhw${i}.nii.gz ${tmpdir}/warpedlabelhw${i}_${DEFTYPE}d.nii.gz -R ${WDDIR}/hwtrimdef.nii.gz \
          ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dInverseWarp.nii.gz;
      else
        WarpImageMultiTransform 3 ${tmpdir}/label${i}.nii.gz ${tmpdir}/warpedlabel${i}_${DEFTYPE}d.nii.gz -R ${WDDIR}/futrim_om.nii.gz \
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
#   rm -rf ${tmpdir}

# Here we are using baseline volumes, not halfway volumes. To be consistent with jac measures which have to be in the halfway space, we do
# other measurements in halfway space as well 
#  BLSF=(`c3d ${WDDIR}/segbltrim.nii.gz ${WDDIR}/segbltrim.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
#  FUSF=(`c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
#  BLVOLS=(`c3d ${WDDIR}/segbltrim.nii.gz ${WDDIR}/segbltrim.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
#  FUVOLS=(`c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
#  MANBLVOLS=(`c3d $BLSEG $BLSEG -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
#  MANFUVOLS=(`c3d $FUSEG $FUSEG -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
#  JACBLVOLS=$BLVOLS
#  JACFUVOLS=(`c3d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz -popas J ${WDDIR}/segbltrim.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  

  if [ "$RIGIDMODE" == "HW" ]; then
    BLSF=(`c3d ${WDDIR}/seghw.nii.gz ${WDDIR}/seghw.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
    BLVOLS=(`c3d ${WDDIR}/seghw.nii.gz ${WDDIR}/seghw.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
  else
    BLSF=(`c3d ${WDDIR}/segbltrim.nii.gz ${WDDIR}/segbltrim.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
    BLVOLS=(`c3d ${WDDIR}/segbltrim.nii.gz ${WDDIR}/segbltrim.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
  fi
  if [ "$DEFREGPROG" == "ants" ]; then
    if [ "$RIGIDMODE" == "HW" ]; then
      FUSF=(`c3d ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
      FUVOLS=(`c3d ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz ${WDDIR}/seghwwarped_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
    else
      FUSF=(`c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
      FUVOLS=(`c3d ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz ${WDDIR}/segfutrim_om_${DEFTYPE}d.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
    fi
  fi
  MANBLVOLS=(`c3d $BLSEG $BLSEG -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
  MANFUVOLS=(`c3d $FUSEG $FUSEG -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
  JACBLVOLS=$BLVOLS
  if [ "$RIGIDMODE" == "HW" ]; then
    JACFUVOLS=(`c3d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz -popas J ${WDDIR}/seghw.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  
  else
    JACFUVOLS=(`c3d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}djacobian.nii.gz -popas J ${WDDIR}/segbltrim.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  
  fi

  for ((j=0; j<${#BLVOLS[*]}; j++)) ; do
      sfi=${BLSF[j]}
      SFBL[sfi]=${BLVOLS[j]}
      MANSFBL[sfi]=${MANBLVOLS[j]}
      MANSFFU[sfi]=${MANFUVOLS[j]}
      JACSFBL[sfi]=${BLVOLS[j]}
      JACSFFU[sfi]=${JACFUVOLS[j]}
  done
  if [ "$DEFREGPROG" == "ants" ]; then
    for ((j=0; j<${#FUVOLS[*]}; j++)) ; do
      sfi=${FUSF[j]}
      SFFU[sfi]=${FUVOLS[j]}
    done
  fi
  
  for ((i=1; i<11; i++)) ; do
    if [ "$DEFREGPROG" == "ants" ]; then
      echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFBL[i]} ${SFFU[i]} $grp >> $RESFILE
    fi
    if [ -f $FUSEG ]; then
      echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${MANSFBL[i]} ${MANSFFU[i]} $grp >> $MANRESFILE
    fi
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${JACSFBL[i]} ${JACSFFU[i]} $grp >> $JACRESFILE
  done
# ----------------------------------------------------------------------------------------------------
else # is3d = 0, 2D registration
  # Reslice each label to HW space and combine for HW segmentation

# This doesn't work for missing labels 
#  c3d ${WDDIR}/hwtrimdef.nii.gz -popas HW ${tmpdir}/label??.nii.gz \
#    -foreach -insert HW 1 -reslice-matrix ${WDDIR}/omRAS_halfinv.mat -endfor \
#    -oo ${tmpdir}/labelhw%02d.nii.gz

  if [ "$RIGIDMODE" == "HW" ]; then
    zsize=`c3d ${WDDIR}/hwtrimdef.nii.gz -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
  else
    zsize=`c3d ${WDDIR}/bltrimdef.nii.gz -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
  fi
  for ((i=0; i<11; i++)) ; do
    SFBL[i]=0
    SFFU[i]=0
    JACSFBL[i]=0
    JACSFFU[i]=0
  done

 
  for ((i=0; i < ${zsize}; i++)) do
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
    if [ "$RIGIDMODE" == "HW" ]; then
      BLSF=(`c2d ${WDDIR}/seghw_${i}.nii.gz ${WDDIR}/seghw_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
      BLVOLS=(`c2d ${WDDIR}/seghw_${i}.nii.gz ${WDDIR}/seghw_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
      if [ "$DEFREGPROG" == "ants" ]; then
        FUSF=(`c2d ${WDDIR}/seghwwarped_${i}.nii.gz ${WDDIR}/seghwwarped_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
        FUVOLS=(`c2d ${WDDIR}/seghwwarped_${i}.nii.gz ${WDDIR}/seghwwarped_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
      fi
      JACBLVOLS=(`c2d ${WDDIR}/seghw_${i}.nii.gz ${WDDIR}/seghw_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
      JACFUVOLS=(`c2d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}jacobian.nii.gz -popas J ${WDDIR}/seghw_${i}.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  
    else
      BLSF=(`c2d ${WDDIR}/segbltrim_${i}.nii.gz ${WDDIR}/segbltrim_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
      BLVOLS=(`c2d ${WDDIR}/segbltrim_${i}.nii.gz ${WDDIR}/segbltrim_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
      if [ "$DEFREGPROG" == "ants" ]; then
        FUSF=(`c2d ${WDDIR}/segwarped_${i}.nii.gz ${WDDIR}/segwarped_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $1}'`)
        FUVOLS=(`c2d ${WDDIR}/segwarped_${i}.nii.gz ${WDDIR}/segwarped_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
      fi
      JACBLVOLS=(`c2d ${WDDIR}/segbltrim_${i}.nii.gz ${WDDIR}/segbltrim_${i}.nii.gz -lstat | sed -n -e '3,$p' | awk '{print $6}'`)
      JACFUVOLS=(`c2d ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}jacobian.nii.gz -popas J ${WDDIR}/segbltrim_${i}.nii.gz  -split -foreach -push J -times -voxel-sum -pop -endfor | sed -n -e '2,$p' | awk '{print $3}'`)  

    fi
    for ((j=0; j<${#BLVOLS[*]}; j++)) ; do
      sfi=${BLSF[j]}
      SFBL[sfi]=`echo "${SFBL[${sfi}]} + ${BLVOLS[j]}" | bc`
      JACSFBL[sfi]=`echo "${JACSFBL[${sfi}]} + ${JACBLVOLS[j]}" | bc`
      JACSFFU[sfi]=`echo "${JACSFFU[${sfi}]} + ${JACFUVOLS[j]}" | bc`
    done
    if [ "$DEFREGPROG" == "ants" ]; then
      for ((j=0; j<${#FUVOLS[*]}; j++)) ; do
        sfi=${FUSF[j]}
        SFFU[sfi]=`echo "${SFFU[${sfi}]} + ${FUVOLS[j]}" | bc`
      done
    fi
  done
  for ((i=1; i<11; i++)) ; do
    if [ "$DEFREGPROG" == "ants" ]; then
      echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFBL[i]} ${SFFU[i]} $grp >> $RESFILE
    fi
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${JACSFBL[i]} ${JACSFFU[i]} $grp >> $JACRESFILE
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
c3d ${WDIR}/bltrimdef.nii.gz $BLSEG -int NN -reslice-identity -o ${WDIR}/segbltrim.nii.gz
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

# Mesh warping and thickness based long volume calculation
RESFILE=${WDDIR}/meshwarp_longvol_${DEFTYPE}d.txt
THKFILE=${WDDIR}/meshwarp_longthick_${DEFTYPE}d.txt
rm -f $RESFILE
rm -f $THKFILE

if [ $is3d == 1 ]; then
  for ((i=0; i<11; i++)) ; do
    SFBL[i]=0
    SFFU[i]=0
    SFTBL[i]=0
    SFTFU[i]=0
  done

  for ((l=0; l < ${#llist[*]}; l++)); do
    if [ ${llist[l]} -ne 0 ]; then
      i=`printf %02d ${llist[l]}`

   # Create image to create mesh from
#    c3d ${WDDIR}/segbltrim.nii.gz -interp NN -resample 100x100x500% -as M \
#        -interp linear -thresh ${llist[l]} ${llist[l]} 1 -1 -push M -thresh ${llist[l]} ${llist[l]} -1 1  \
#        -levelset-curvature 1.2 -levelset 400 -scale -1 -shift 4 -o ${tmpdir}/labellevelset${i}.nii.gz
#    ~pauly/bin/vtklevelset ${tmpdir}/labellevelset${i}.nii.gz ${tmpdir}/label${i}.vtk 4.0

      # baseline space baseline measurement
      # c3d ${WDDIR}/seghw.nii.gz -thresh ${llist[l]} ${llist[l]} 1 0 \
      #   -int Gaussian 0.2x0.2x1.0mm -trim 10x10x2vox -resample 100x100x500% -thresh 0.5 inf 1 0 \
      #   -pad 1x1x1vox 1x1x1vox 0 -o ${tmpdir}/labelbinarytarget${i}.nii.gz
      # ~pauly/bin/vtklevelset ${tmpdir}/labelbinarytarget${i}.nii.gz ${tmpdir}/label${i}.vtk 0.5

      if [ "$RIGIDMODE" == "HW" ]; then
        c3d ${WDDIR}/seghw.nii.gz -thresh ${llist[l]} ${llist[l]} 1 0 \
          -int Gaussian 0.2x0.2x1.0mm -trim 10x10x2vox -resample 100x100x500% -thresh 0.5 inf 1 0 \
          -pad 1x1x1vox 1x1x1vox 0 -o ${tmpdir}/labelhwbinarytarget${i}.nii.gz
        ~pauly/bin/vtklevelset ${tmpdir}/labelhwbinarytarget${i}.nii.gz ${tmpdir}/labelhw${i}.vtk 0.5
      else
        c3d ${WDDIR}/segbltrim.nii.gz -thresh ${llist[l]} ${llist[l]} 1 0 \
          -int Gaussian 0.2x0.2x1.0mm -trim 10x10x2vox -resample 100x100x500% -thresh 0.5 inf 1 0 \
          -pad 1x1x1vox 1x1x1vox 0 -o ${tmpdir}/labelbinarytarget${i}.nii.gz
        ~pauly/bin/vtklevelset ${tmpdir}/labelbinarytarget${i}.nii.gz ${tmpdir}/label${i}.vtk 0.5
      fi

      # Compute skeleton at baseline
      if [ "$RIGIDMODE" == "HW" ]; then
        ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
          -I ${tmpdir}/labelhwbinarytarget${i}.nii.gz ${tmpdir}/labelhwthickness${i}.nii.gz ${tmpdir}/labelhwdepthmap${i}.nii.gz  \
          ${tmpdir}/labelhw${i}.vtk ${tmpdir}/labelhwskeleton${i}.vtk
      else
        ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
          -I ${tmpdir}/labelbinarytarget${i}.nii.gz ${tmpdir}/labelthickness${i}.nii.gz ${tmpdir}/labeldepthmap${i}.nii.gz  \
          ${tmpdir}/label${i}.vtk ${tmpdir}/labelskeleton${i}.vtk
      fi

      # Compute thickness 
      if [ "$RIGIDMODE" == "HW" ]; then
        THICKBL=`~/bin/cmrep/mesharrstat ${tmpdir}/labelhwskeleton${i}.vtk Radius`   
      else
        THICKBL=`~/bin/cmrep/mesharrstat ${tmpdir}/labelskeleton${i}.vtk Radius`   
      fi

      #  rm -f ${tmpdir}/labellevelset${i}.nii.gz
      # Move the mesh to the halfway point
      # ~/bin/cmrep/warpmesh ${tmpdir}/label${i}.vtk ${tmpdir}/label_2hw${i}.vtk $WDDIR/omRAS_half.mat

      # Apply the warp to the mesh
      # baseline space baseline measurements
      # ~/bin/cmrep/warpmesh -w ants ${tmpdir}/label_2hw${i}.vtk ${tmpdir}/warpedlabel${i}.vtk $WDDIR/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp?vec.nii.gz
      if [ "$RIGIDMODE" == "HW" ]; then
        ~/bin/cmrep/warpmesh -w ants ${tmpdir}/labelhw${i}.vtk ${tmpdir}/warpedlabelhw${i}.vtk $WDDIR/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp?vec.nii.gz
      else
        ~/bin/cmrep/warpmesh -w ants ${tmpdir}/label${i}.vtk ${tmpdir}/warpedlabel${i}.vtk $WDDIR/${DEFREGPROG}/${DEFREGPROG}reg${DEFTYPE}dWarp?vec.nii.gz
        ~/bin/cmrep/warpmesh ${tmpdir}/warpedlabel${i}.vtk ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk $WDDIR/omRAS.mat
      fi
      

      # Apply the second half of the rigid transform to the mesh
      # ~/bin/cmrep/warpmesh ${tmpdir}/warpedlabel${i}.vtk ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk $WDDIR/omRAS_half.mat

      if [ "$RIGIDMODE" == "HW" ]; then
        # Compute skeleton at followup -- from original warped image mask or from warped mesh ? Do it from warped mesh
        ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
          ${tmpdir}/warpedlabelhw${i}.vtk ${tmpdir}/warpedlabelhwskeleton${i}.vtk
        # Compute thickness 
        THICKFU=`~/bin/cmrep/mesharrstat ${tmpdir}/warpedlabelhwskeleton${i}.vtk Radius`   
      else
        # Compute skeleton at followup -- from original warped image mask or from warped mesh ? Do it from warped mesh
        ~pauly/bin/cmrep_vskel -Q ~pauly/bin/qvoronoi -p 1.6 -c 1 \
          ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk ${tmpdir}/warpedlabel_to_futrim_omskeleton${i}.vtk
        # Compute thickness 
        THICKFU=`~/bin/cmrep/mesharrstat ${tmpdir}/warpedlabel_to_futrim_omskeleton${i}.vtk Radius`   
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
      THICKFU=`~/bin/cmrep/mesharrstat ${tmpdir}/warpedlabelimageskeleton${i}.vtk Radius`   
NOMESHWARP

      # Compute volume
      # baseline space
      # BLVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/label${i}.vtk ${tmpdir}/label${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
      # FUVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
      # halfway space
      if [ "$RIGIDMODE" == "HW" ]; then
        BLVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/labelhw${i}.vtk ${tmpdir}/labelhw${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
        FUVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/warpedlabelhw${i}.vtk ${tmpdir}/warpedlabelhw${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
      else
        BLVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/label${i}.vtk ${tmpdir}/label${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`
        FUVOL=`~pauly/bin/meshdiff -s 0.2 ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk ${tmpdir}/warpedlabel_to_futrim_om${i}.vtk | grep Volume | cut -f 5 -d " " | tail -n 1`

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

      sfi=${llist[l]}
      SFBL[sfi]=$BLVOL
      SFFU[sfi]=$FUVOL
      SFTBL[sfi]=$THICKBL
      SFTFU[sfi]=$THICKFU
      #  rm -f /tmp/${id}_${side}_${FLAVOR}_${INITTYPE}_${sf}*.vtk
    fi

  done
  for ((i=1; i<11; i++)) ; do
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFBL[i]} ${SFFU[i]} $grp >> $RESFILE
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFTBL[i]} ${SFTFU[i]} $grp >> $THKFILE
  done

else
  
  if [ "$RIGIDMODE" == "HW" ]; then
    zsize=`c3d ${WDDIR}/hwtrimdef.nii.gz -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
  else
    zsize=`c3d ${WDDIR}/bltrimdef.nii.gz -info | cut -f 1 -d ";" | cut -f 3 -d "," | sed -e 's/]//g' -e 's/ //g'`;
  fi
  
  for ((i=0; i<11; i++)) ; do
    SFBL[i]=0
    SFFU[i]=0
  done

  for ((i=0; i < ${zsize}; i++)) do
    for ((l=0; l < ${#llist[*]}; l++)); do
      sf=`printf %02d ${llist[l]}`
      if [ "$sf" != "00" ]; then
      
      if [ "$RIGIDMODE" == "HW" ]; then
        c2d ${tmpdir}/labelhw${sf}_${i}.nii.gz -o ${tmpdir}/labelhw${sf}_${i}.nii.gz
        c2d ${tmpdir}/labelhw${sf}_${i}.nii.gz $SUPERRES -o ${tmpdir}/labelhw${sf}_${i}.nii.gz
      
        # Get the contour
        vtkcontour ${tmpdir}/labelhw${sf}_${i}.nii.gz ${tmpdir}/labelhw${sf}_${i}_contour.vtk 0.5
      else
        c2d ${tmpdir}/label${sf}_${i}.nii.gz -o ${tmpdir}/label${sf}_${i}.nii.gz
        c2d ${tmpdir}/label${sf}_${i}.nii.gz $SUPERRES -o ${tmpdir}/label${sf}_${i}.nii.gz
      
        # Get the contour
        vtkcontour ${tmpdir}/label${sf}_${i}.nii.gz ${tmpdir}/label${sf}_${i}_contour.vtk 0.5
      fi

      if [ "$RIGIDMODE" == "HW" ]; then
        # Is there any contour ?
        nPoints=`grep POINTS ${tmpdir}/labelhw${sf}_${i}_contour.vtk | awk '{print $2}'`
        if [ $nPoints -ne 0 ]; then

          # Triangulate the contour
          contour2surf ${tmpdir}/labelhw${sf}_${i}_contour.vtk ${tmpdir}/labelhw${sf}_${i}_trimesh.vtk zYpq32a0.1

          # Warp the mesh
          AREA_STATS=`warpmesh -w ants ${tmpdir}/labelhw${sf}_${i}_trimesh.vtk ${tmpdir}/labelhw${sf}_${i}_warpedtrimesh.vtk \
            ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warp?vec.nii.gz | grep AREA_STATS`
        
          BLVOL=`echo $AREA_STATS | awk '{print $2}'`    
          FUVOL=`echo $AREA_STATS | awk '{print $3}'`

          echo $sf $BLVOl $FUVOL ${SFBL[${llist[l]}]} ${SFFU[${llist[l]}]}

          SFBL[llist[l]]=`echo "${SFBL[${llist[l]}]} + ${BLVOL}" | bc`     
          SFFU[llist[l]]=`echo "${SFFU[${llist[l]}]} + ${FUVOL}" | bc`     

        fi
      else
        # Is there any contour ?
        nPoints=`grep POINTS ${tmpdir}/label${sf}_${i}_contour.vtk | awk '{print $2}'`
        if [ $nPoints -ne 0 ]; then

          # Triangulate the contour
          contour2surf ${tmpdir}/label${sf}_${i}_contour.vtk ${tmpdir}/label${sf}_${i}_trimesh.vtk zYpq32a0.1

          # Warp the mesh
          AREA_STATS=`warpmesh -w ants ${tmpdir}/label${sf}_${i}_trimesh.vtk ${tmpdir}/label${sf}_${i}_warpedtrimesh.vtk \
            ${WDDIR}/${DEFREGPROG}/${DEFREGPROG}reg_${i}Warp?vec.nii.gz | grep AREA_STATS`
        
          BLVOL=`echo $AREA_STATS | awk '{print $2}'`    
          FUVOL=`echo $AREA_STATS | awk '{print $3}'`

          echo $sf $BLVOl $FUVOL ${SFBL[${llist[l]}]} ${SFFU[${llist[l]}]}

          SFBL[llist[l]]=`echo "${SFBL[${llist[l]}]} + ${BLVOL}" | bc`     
          SFFU[llist[l]]=`echo "${SFFU[${llist[l]}]} + ${FUVOL}" | bc`     
        fi

      fi
      fi
    done
  done  
  for ((i=1; i<11; i++)) ; do
    echo $id $side $INITTYPE $DEFTYPE $METRIC $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $i ${SFBL[i]} ${SFFU[i]} $grp >> $RESFILE
  done
  
fi

NORUN
