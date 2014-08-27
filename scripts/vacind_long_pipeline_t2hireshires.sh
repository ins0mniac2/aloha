WHICHANTS=ANTS
ASTEPSIZE="0.1"
RIGIDMODE=HW
export WHICHANTS RIGIDMODE ASTEPSIZE

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
    -w ibn_work_${side} \
    -n ${id}_${side}


