WHICHANTS=ANTS
ASTEPSIZE="0.1"
RIGIDMODE=HW
export WHICHANTS RIGIDMODE ASTEPSIZE

FSLOUTPUTTYPE=NIFTI_GZ
export FSLOUTPUTTYPE
WDIR=${WORK}/ibn_work_${side}
mkdir -p $WDIR

if [ "$INITTYPE" == "chunk" ]; then
  source ${ROOT}/scripts/bash/vacind_long_rigid_chunkinit.sh
elif [ "$INITTYPE" == "full" ]; then
  source ${ROOT}/scripts/bash/vacind_long_rigid_init.sh
else
  echo "Unknown initialization type"
  exit -1
fi


# Now we are ready to register folloup T2 to baseline T2 with this initialization

#:<<COMMENT
c3d $BLGRAY -resample 100x100x500% -o $BLHRGRAY
c3d $FUGRAY -resample 100x100x500% -o $FUHRGRAY
c3d $BLSEG -split -foreach -smooth $SM -resample 100x100x500% \
  -endfor -merge -o $BLHRSEG
c3d $FUSEG -split -foreach -smooth $SM -resample 100x100x500% \
  -endfor -merge -o $FUHRSEG


bash ${ROOT}/scripts/bash/pmatlas_ibn_long_papergrid.sh -d \
    -b ${BLHRGRAY} \
    -f ${FUHRGRAY} \
    -s ${BLSEG} \
    -a ${WDIR}/tse_long.mat \
    -w ${WDIR} \
    -n ${id}_${side}
#COMMENT

