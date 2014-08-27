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


bash ${ROOT}/scripts/bash/pmatlas_ibn_long_papergrid.sh -d \
    -b ${BLGRAY} \
    -f ${FUGRAY} \
    -s ${BLSEG} \
    -r 100x100x500% \
    -a ${WDIR}/tse_long.mat \
    -w ${WDIR} \
    -n ${id}_${side}

