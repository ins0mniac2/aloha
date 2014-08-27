#!/bin/bash
# Call like vacind_long_launch.sh chunk flirt ants asym 3 T01 L

# Set up the PATH
PATH=${HOME}/bin/ants:$PATH

# Set the root and work directories
ROOT=${HOME}/wd/Pfizer/VACIND

# t2natnat: t2 rigid, rigid native, def native
# t2hireshires: t2 rigid, rigid hires, def hires
# t2nathires: t2rigid, rigid native, def hires
# t1natnat: t1 rigid, rigid native, def native
# t1hireshires: t1 rigid, rigid hires, def hires
# t1nathires: t1 rigid, rigid native, def hires

if [ $# -lt 8 ]; then
  echo "Usage: $0 REGTYPE GLOBALREGPROG SYMMTYPE DEFTYPE FUTIMEPOINT BLTIMEPOINT SIDE"
  echo "./vacind_long_launch.sh chunk flirt ants asym 2 T01 T04 L"
  exit -1
fi

REGTYPE=$1 # full or chunk
GLOBALREGPROG=$2 # flirt ANTS evolreg bfreg
DEFREGPROG=$3 # flirt ANTS evolreg bfreg
SYMMTYPE=$4 # asym symm
DEFTYPE=$5 # 2, 2.5, 3
TIMEPOINT=$6 # T01, T02, T03, T04
BLTIMEPOINT=$7 # T01, T02, T03, T04
SIDE=$8 #L, R
INITTYPE=chunk
USEMASK=1
USEDEFMASK=1
MASKRAD=3
RESAMPLE="0"
RFIT=0
ASTEPSIZE=0.25
REGUL1=2.0
REGUL2=0.5
RIGIDMODE=HW
MODALITY=MPRAGE
ALTMODESEG=false
DOMPSUB=0
SEGALT=orig
ANTSVER=v3

# for FLAVOR in t2natnat t2hireshires t2nathires t1natnat t1hireshires t1nathires; do
for FLAVOR in t1natnat ; do
  ./vacind_long_pipeline_test.sh $FLAVOR $INITTYPE $DEFTYPE $GLOBALREGPROG $USEMASK $SYMMTYPE $REGTYPE $USEDEFMASK $MASKRAD $RESAMPLE $RFIT $ASTEPSIZE $DEFREGPROG $TIMEPOINT $RIGIDMODE  $MODALITY $DOMPSUB $SEGALT $ALTMODESEG $SIDE $BLTIMEPOINT $ANTSVER $REGUL1 $REGUL2 
#  sleep 3

done
