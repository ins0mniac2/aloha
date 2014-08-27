# ROOT=~/wd/Pfizer/VACIND/testretest
ROOT=~/wd/Pfizer/ADC/long/structural
tp=$1
mode_dir="flirt_chunk"
# t1fromt2 means t2 label, t1 space dbm
# stepsize=full1nsteps2dt0.05
stepsize=t2chunkhw0.25
# stepsize="altseg0.5"
for measure in vol thick; do
  for method in jac imwarp meshwarp; do
    for dim in 2  3;do # 2.5 3; do
      if [[ "$dim" == "2" && "$measure" == "thick" ]]; then
        LFILE=$ROOT//${method}${measure}${dim}d_${tp}_${stepsize}.txt
        echo > $LFILE
      elif [[ "$measure" == "thick" && "$method" == "jac" ]]; then
        LFILE=$ROOT//${method}${measure}${dim}d_${tp}_${stepsize}.txt
        echo > $LFILE

      elif [[ "$measure" == "thick" && "$method" == "meshwarp" ]]; then
        LFILE=$ROOT//${method}${measure}${dim}d_${tp}_${stepsize}.txt
        echo > $LFILE

      else

        LFILE=$ROOT//${method}${measure}${dim}d_${tp}_${stepsize}.txt
        > $LFILE
        for sub in `cat $ROOT//long_sublist_${tp}.txt | grep " L " | cut -f 1 -d " "`; do
          cat $ROOT//${sub}/${tp}_affine12/unbiased_t1natnat_chunk/ibn_work_?/$mode_dir/normcorr_asym/${method}_long${measure}_${dim}d.txt >> $LFILE
        done
        for excl_subj in `cat $ROOT//excl_subj.txt | grep ${tp} | cut -f 1 -d " "`; do
          grep -v $excl_subj $LFILE > /tmp/srdas_stats.txt
          mv /tmp/srdas_stats.txt $LFILE
        done  
      fi
    done
  done
       # cat $ROOT/long/FCD*/unbiased_t1natnat_chunk/ibn_work_?/$mode_dir/normcorr_asym/manual_longvol.txt > $ROOT/long/manual_longvol.txt
       # cat $ROOT/testretest/FAD*/unbiased_t1natnat_chunk/ibn_work_?/$mode_dir/normcorr_asym/manual_longvol.txt > $ROOT/testretest/manual_longvol.txt
done
:<<'COMM'
if [ "${1}" == "ANTS" ]; then
  mstr=mutualinfo_asym
else
  mstr=normcorr_asym
fi
for i in /home/srdas/wd/Pfizer/VACIND/long/FCD*/T*_T*/unbiased_t1natnat_chunk/ibn_work_L/${1}_mp/${mstr}_${2}/meshwarp_longvol_3d.txt; do
# for i in /home/srdas/wd/Pfizer/VACIND/long/FCD*/T00_T*/unbiased_t1natnat_chunk/ibn_work_L/flirt_mp/normcorr_asym_${2}/meshwarp_longvol_3d.txt; do 
  bltp=$(echo $i | cut -f 9 -d "/" | cut -f 1 -d "_");
  futp=$(echo $i | cut -f 9 -d "/" | cut -f 2 -d "_");
  sub=$(echo $i | cut -f 8 -d "/" ) ;
  side=$(grep " 1 3 1 "  $i | awk '{print $2}');
  blvol=$(grep " 1 3 1 "  $i | awk '{print $13}');
  fuvol=$(grep " 1 3 1 "  $i | awk '{print $14}');
  atr=$(grep " 1 3 1 "  $i | awk '{print $15}');
  grp=$(grep " 1 3 1 "  $i | awk '{print $16}');
  echo $sub $grp $side ${bltp#T} ${futp#T} $blvol $fuvol $atr ;
done > results_${1}_${2}.txt
COMM  
