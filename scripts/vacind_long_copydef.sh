#!/bin/bash

# Set up the PATH
PATH=${HOME}/bin/ants:$PATH

# Set the root and work directories
ROOT=${HOME}/wd/Pfizer/VACIND
REGTYPE=chunk
GLOBALREGPROG=flirt
SYMMTYPE=asym
LDIR=$ROOT/long

if [ "$REGTYPE" == "chunk" ]; then
  REGSUFF="_chunk" 
else
  REGSUFF=""
fi


# Get the list of all IDS -- all FCD subjects which have 4 Final segmentations, i.e. both L and R for both TP1 and TP2
cd ${ROOT}/SubfieldSeg/FCD/Final
#ALLIDS=($(for i in FCD*; do echo $i `ls -1 ${i}/JP/*gz | wc -l`; done | grep " 4" | cut -f 1 -d " "))
#ALLIDS=FCD*

if [ "$REGTYPE" == "full" ]; then
# Only left
  ALLIDS=($(cat $LDIR/long_sublist.txt | grep " L " | cut -f 1 -d " "))
  SIDES=($(cat $LDIR/long_sublist.txt | grep " L " | cut -f 2 -d " "))
  ALLGRP=($(cat $LDIR/long_sublist.txt | grep " L " | cut -f 3 -d " "))
#  ALLIDS=($(cat $LDIR/long_sublist.txt | cut -f 1 -d " "))
#  SIDES=($(cat $LDIR/long_sublist.txt  | cut -f 2 -d " "))
#  ALLGRP=($(cat $LDIR/long_sublist.txt | cut -f 3 -d " "))
fi

if [ "$REGTYPE" == "chunk" ]; then
# Both sides
  ALLIDS=($(cat $LDIR/long_sublist.txt |  cut -f 1 -d " "))
  SIDES=($(cat $LDIR/long_sublist.txt |  cut -f 2 -d " "))
  ALLGRP=($(cat $LDIR/long_sublist.txt |  cut -f 3 -d " "))
fi


# ALLIDS=(FCD005)
# ALLIDS=(FAD363)
# SIDES=(L)
# ALLGRP=(Patient)



if [ "$GLOBALREGPROG" == "ANTS" ]; then
  METRICLIST="mutualinfo"
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
  

#for id in ${ALLIDS[*]}; do
for ((i=0; i<${#ALLIDS[*]}; i++)); do
  id=${ALLIDS[i]}
  grp=${ALLGRP[i]}
  tp=T01
  # Create dump
  # WORK=$LDIR/${id}/${tp}/unbiased_${FLAVOR}_${INITTYPE}
   WORK=$LDIR/${id}/unbiased_t1natnat_chunk

  side=${SIDES[i]}

  echo ${id} ${side}
  # Export variables
  export id grp tp side ROOT LDIR PATH WORK FLAVOR INITTYPE DEFTYPE GLOBALREGPROG USEMASK SYMMTYPE REGTYPE USEDEFMASK MASKRAD RESAMPLE RFIT ASTEPSIZE DEFREGPROG
  for METRIC in $METRICLIST ;do 
    # logname=${id}_${side}_${GLOBALREGPROG}_${METRIC}_${SYMMTYPE}_${REGTYPE}
    if [ "$USEDEFMASK" == "0" ]; then 
      logmask="nomask${MASKRAD}" 
    else 
      logmask="mask${MASKRAD}" 
    fi
    logname=${id}_${side}_${GLOBALREGPROG}_${DEFREGPROG}_${METRIC}_${SYMMTYPE}_${REGTYPE}_def${DEFTYPE}_${logmask}_master_unchanged_rfit${RFIT}_resample${RESAMPLE}_step${ASTEPSIZE}
    rm -rf $WORK/ibn_work_${side}/${GLOBALREGPROG}${REGSUFF}/${METRIC}_${SYMMTYPE}/debug
    cp -pr $WORK/ibn_work_${side}/${GLOBALREGPROG}${REGSUFF}/${METRIC}_${SYMMTYPE} \
      $WORK/ibn_work_${side}/${GLOBALREGPROG}${REGSUFF}/${METRIC}_${SYMMTYPE}_${DEFREGPROG}_def${DEFTYPE}_${logmask}_step${ASTEPSIZE}_${1}
  done	
done
