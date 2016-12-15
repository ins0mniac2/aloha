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

#if [ ! -f $LDIR/${id}/bl_tse_fullmask.nii.gz -a -f $BLGRAY ]; then
#  c3d $BLGRAY   -thresh -inf inf 1 0 -o $LDIR/${id}/bl_tse_fullmask.nii.gz
#fi
#if [ ! -f $LDIR/${id}/fu_tse_fullmask.nii.gz -a -f $BLGRAY ]; then
#  c3d $FUGRAY   -thresh -inf inf 1 0 -o $LDIR/${id}/fu_tse_fullmask.nii.gz
#fi


# Resample to isotropic
BLHRGRAY=${WORK}/${bltp}_${id}_tse_hires.nii.gz
FUHRGRAY=${WORK}/${tp}_${id}_tse_hires.nii.gz
BLHRSEG=${WORK}/${bltp}_${id}_seg_${side}_hires.nii.gz
FUHRSEG=${WORK}/${tp}_${id}_seg_${side}_hires.nii.gz

export id side BLGRAY FUGRAY BLMPGRAY FUMPGRAY BLSEG FUSEG BLMPSEG FUMPSEG BLHRGRAY FUHRGRAY BLHRSEG FUHRSEG WORK INITTYPE DEFTYPE METRIC GLOBALREGPROG USEMASK SYMMTYPE REGTYPE USEDEFMASK MASKRAD RESAMPLE RFIT ASTEPSIZE DEFREGPROG RIGIDMODE DOMPSUB ALTMODESEG ANTSVER REGUL1 REGUL2

# Registration is done by the script
 source ${ROOT}/scripts/bash/vacind_long_pipeline_${FLAVOR}.sh



# Now do measurements
 source ${ROOT}/scripts/bash/vacind_long_measurements.sh



