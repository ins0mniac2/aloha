#!/bin/bash

# Set up the PATH
PATH=${HOME}/bin/ants:$PATH

# Set the root and work directories
ROOT=${HOME}/wd/Pfizer/VACIND
DROOT=${HOME}/wd/Pfizer/VACIND
LDIR=$ROOT/testretest/testretestreversed
LDIR=$ROOT/testretest
#LDIR=$ROOT/long


 DROOT=/home/hwang3/atrophy
 LDIR=/home/hwang3/atrophy/organizedData

 DROOT=/home/srdas/wd/John
 LDIR=/home/srdas/wd/John/long

 DROOT=/home/srdas/wd/BerlinSimone
 LDIR=/home/srdas/wd/BerlinSimone/long

 DROOT=/home/srdas/wd/ect
 LDIR=/home/srdas/wd/ect

 DROOT=/home/srdas/wd/Pfizer/ADC
 LDIR=/home/srdas/wd/Pfizer/ADC/long/structural

 DROOT=/home/srdas/wd/MEMORIES
 LDIR=/home/srdas/wd/MEMORIES/long

 DROOT=/home/srdas/wd/ADNI2
 LDIR=/home/srdas/wd/ADNI2/longBLT1


FLAVOR=$1
INITTYPE=$2
DEFTYPE=$3
GLOBALREGPROG=$4
USEMASK=$5
SYMMTYPE=$6
REGTYPE=$7
USEDEFMASK=$8
MASKRAD=$9
RESAMPLE=${10}
RFIT=${11}
ASTEPSIZE=${12}
DEFREGPROG=${13}
TIMEPOINT=${14}
RIGIDMODE=${15}
MODALITY=${16} 
DOMPSUB=${17}
SEGALT=${18}
ALTMODESEG=${19}
MYSIDE=${20}
BLTIMEPOINT=${21}
ANTSVER=${22}
REGUL1=${23}
REGUL2=${24}


# t2natnat: t2 rigid, rigid native, def native
# t2hireshires: t2 rigid, rigid hires, def hires
# t2nathires: t2rigid, rigid native, def hires
# t1natnat: t1 rigid, rigid native, def native
# t1hireshires: t1 rigid, rigid hires, def hires
# t1nathires: t1 rigid, rigid native, def hires


# Get the list of all IDS -- all FCD subjects which have 4 Final segmentations, i.e. both L and R for both TP1 and TP2
# cd ${ROOT}/SubfieldSeg/FCD/Final
#ALLIDS=($(for i in FCD*; do echo $i `ls -1 ${i}/JP/*gz | wc -l`; done | grep " 4" | cut -f 1 -d " "))
#ALLIDS=FCD*

if [ "$REGTYPE" == "full" ]; then
# Only left
  ALLIDS=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt | grep " L " | cut -f 1 -d " "))
  SIDES=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt | grep " L " | cut -f 2 -d " "))
  ALLGRP=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt | grep " L " | cut -f 3 -d " "))
  ALLIDS=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt | cut -f 1 -d " "))
  SIDES=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt  | cut -f 2 -d " "))
  ALLGRP=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt | cut -f 3 -d " "))
fi

if [ "$REGTYPE" == "chunk" ]; then
# Both sides
  ALLIDS=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt |  cut -f 1 -d " "))
  SIDES=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt |  cut -f 2 -d " "))
  ALLGRP=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt |  cut -f 3 -d " "))
fi

ALLIDS=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt | grep " L " | cut -f 1 -d " "))
SIDES=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt | grep " L " | cut -f 2 -d " "))
ALLGRP=($(cat $LDIR/long_sublist_${TIMEPOINT}.txt | grep " L " | cut -f 3 -d " "))

# T01
# ALLIDS=(FCD041 FCD041 FCD025 FCD018 FCD024 FCD028)
# SIDES=(L R R R R R)
# T02
# ALLIDS=(FCD045 )
# SIDES=(L )
# ALLIDS=(FCD013)
# T03
# ALLIDS=(FCD009 FCD045)
# SIDES=(R L)
# T04
# ALLIDS=(FCD027 FCD025 FCD005)
# SIDES=(R R R)
# ALLIDS=(FCD100)
# SIDES=(L)
# ALLGRP=()

 ALLIDS=(${25})
# ALLIDS=(200)
# SIDES=(R)


if [ "$GLOBALREGPROG" == "ANTS" ]; then
  METRICLIST="mutualinfo"
elif [ "$GLOBALREGPROG" == "reuter" ]; then
  METRICLIST="normcorr"
elif [ "$GLOBALREGPROG" == "flirt" ]; then
  #METRICLIST="mutualinfo normcorr normmi leastsq"
  #METRICLIST="normcorr leastsq"
  METRICLIST="normcorr"
elif [ "$GLOBALREGPROG" == "evolreg" ]; then
  # METRICLIST="mutualinfo normcorr normmi leastsq"
   METRICLIST="normcorr leastsq"
else # bfreg
  # METRICLIST="mutualinfo normcorr normmi leastsq"
   METRICLIST="leastsq normcorr"
fi
  

if [ "$REGTYPE" == "chunk" ]; then
  REGSUFF="_chunk"
else
  REGSUFF=""
fi


#for id in ${ALLIDS[*]}; do
for ((i=0; i<${#ALLIDS[*]}; i++)); do
  id=${ALLIDS[i]}

:<<'COMM'
  badsegbl=`grep $id $LDIR/segmentation_qa.txt | egrep -e $BLTIMEPOINT -e $TIMEPOINT` 
  if [ "$badsegbl" == "" ]; then
    echo "Segmentations ok $id $BLTIMEPOINT $TIMEPOINT"
    continue;
  else
    echo "rerunning $id $BLTIMEPOINT $TIMEPOINT"
  fi  
COMM
exclbool=`grep $id $LDIR/excl_subj.txt | egrep -e $BLTIMEPOINT -e $TIMEPOINT`
  if [ "$exclbool" == "" ]; then
    echo "Time points not excluded $id $BLTIMEPOINT --> $TIMEPOINT"
  else
    echo "One or both time points excluded $id $BLTIMEPOINT --> $TIMEPOINT"
    # rm -f $LDIR/${id}/${TIMEPOINT}/unbiased_${FLAVOR}_${INITTYPE}/ibn_work_${SIDES[i]}/flirt*/normcorr_asym/ants/*ants*output*txt
    continue;
  fi  
#  grp=${ALLGRP[i]}
  grp=$(grep $id $LDIR/long_sublist_${TIMEPOINT}_snap.txt | grep " L " | cut -f 3 -d " ")
  tp=$TIMEPOINT
  bltp=$BLTIMEPOINT
  # Create dump
#  if [ -f $LDIR/${id}/bl.txt ]; then
#    bltp=`cat $LDIR/${id}/bl.txt`
#  else
#    bltp=$BLTIMEPOINT
#  fi
  # if we want to test all combinations of BL and FU timepoints: more general
  WORK=$LDIR/${id}/${bltp}_${tp}/unbiased_${FLAVOR}_${INITTYPE}
#  WORK=$LDIR/${id}/${tp}/unbiased_${FLAVOR}_${INITTYPE}
# Using 9/12 parameter affine
#  WORK=$LDIR/${id}/${tp}_affine9/unbiased_${FLAVOR}_${INITTYPE}
  if [ "$bltp" == "$tp" ]; then
    continue;
  fi
  #rm -rf $WORK
  mkdir -p $WORK/dump

#  if [ -f $WORK/ibn_work_L/ANTS_mp/mutualinfo_asym_${ASTEPSIZE}_${REGUL1}_${REGUL2}/meshwarp_longvol_3d.txt ]; then
#    echo "$id $bltp $tp done"
#    continue;
#  fi

#  side=${SIDES[i]}
  side=$MYSIDE

  # Export variables
  export id grp bltp tp side ROOT LDIR PATH WORK FLAVOR INITTYPE DEFTYPE GLOBALREGPROG USEMASK SYMMTYPE REGTYPE USEDEFMASK MASKRAD RESAMPLE RFIT ASTEPSIZE DEFREGPROG RIGIDMODE MODALITY DOMPSUB SEGALT ALTMODESEG TIMEPOINT ANTSVER REGUL1 REGUL2

  for METRIC in $METRICLIST ;do 
    # logname=${id}_${side}_${GLOBALREGPROG}_${METRIC}_${SYMMTYPE}_${REGTYPE}
    if [ "$USEDEFMASK" == "0" ]; then 
      logmask="nomask${MASKRAD}" 
    else 
      logmask="mask${MASKRAD}" 
    fi
    logname=atr_${id}_${side}_${REGTYPE}_def${DEFTYPE}_${GLOBALREGPROG}_ANTS${ANTSVER}_step${ASTEPSIZE}_${REGUL1}_${REGUL2}_${RIGIDMODE}_altmodeseg${ALTMODESEG}_mpsub${DOMPSUB}_${MODALITY}
    # logname=atr_${id}_${side}_${REGTYPE}_def${DEFTYPE}_bsplinesyn_${RIGIDMODE}_altmodeseg${ALTMODESEG}_mpsub${DOMPSUB}_${MODALITY}

    export METRIC
#     if [ -f $WORK/ibn_work_${side}/${GLOBALREGPROG}${REGSUFF}/${GLOBALREGPROG}_RAS_${METRIC}_${SYMMTYPE}.mat ]; then
#       echo "file exists $id $side"
#     else

    WAIT=TRUE
    while [ "$WAIT" == "TRUE" ]; do
      Njobs=`qstat | grep srdas | grep 'atr_'  | wc -l`
      if [ $Njobs -lt 2000 ]; then
        WAIT=FALSE
        echo $Njobs jobs running, will run subject $subname
      else
        echo $Njobs jobs running, will wait subject $subname
        sleep 60
        NUMBER=$[ ( $RANDOM % 5 )  + 1 ]
        sleep $NUMBER
      fi
    done


        rm -f $WORK/dump/${logname}.out $WORK/dump/${logname}.err
        echo "$id $bltp $tp submitting"
        qsub -pe serial 1 -o $WORK/dump/${logname}.out -e $WORK/dump/${logname}.err -wd $WORK -N "${logname}" -V ${ROOT}/scripts/bash/vacind_long_pipeline_qsub.sh
#        ${ROOT}/scripts/bash/vacind_long_pipeline_qsub.sh
#     fi
    echo
#     ${ROOT}/scripts/bash/vacind_long_pipeline_qsub.sh
    NUMBER=$[ ( $RANDOM % 5 )  + 1 ]
     sleep $NUMBER
  done	
done
