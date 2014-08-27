if [ $# -lt 2 ]; then
  echo Usage: $0 timepoint baselinetimepoint 
  exit -1
fi


DROOT=/home/hwang3/atrophychallenge/organizedData
# for sub in `cat $DROOT/long_sublist_${1}.txt | cut -f 1 -d " " |uniq`; do
for sub in 188 ; do

  echo $sub
  export sub
  export RIGIDMODE=HW
  export DEFREGPROG=ants
  export ASTEPSIZE=0.25

  export DROOT
  export TP=$1
  export BLTP=$2
  export WORK=$DROOT/$sub/${BLTP}_${TP}/unbiased_t1natnat_chunk
  
if [ -f $WORK/ibn_work_L/ANTS_mp/ANTS_RAS_mutualinfo_asym.mat ]; then
  
  qsub -pe serial 2 -o $WORK/dump/mprage_wb_measurement.out -e $WORK/dump/mprage_wb_measurement.err \
   -wd $WORK -N "s${sub}_mprage_wb_measurement" -V vacind_long_wb_deformable_qsub.sh
# ./vacind_long_wb_deformable_qsub.sh
else
  echo "Global registration does not exist"
fi

done

