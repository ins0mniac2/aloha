WHICHANTS=ANTS
ASTEPSIZE="0.1"
RIGIDMODE=HW
export WHICHANTS RIGIDMODE ASTEPSIZE
bash ${ROOT}/scripts/bash/pmatlas_ibn_long_papergrid.sh -d \
    -b ${BLGRAY} \
    -f ${FUGRAY} \
    -s ${BLSEG} \
    -w ibn_work_${side} \
    -n ${id}_${side}


