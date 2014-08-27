set -x
for i in `cat long_sublist_T01.txt | cut -f 1 -d " " | uniq`; do 
  echo $i ;
  segleft=/home/hwang3/sandy/DW/malf/T01_${i}_seg_2.nii.gz
  WDIR=$i/T01_affine12/unbiased_t1natnat_chunk/ibn_work_L/flirt_chunk_mp/normcorr_asym
  BLORIG=($(c3d $WDIR/bltrim.nii.gz -info-full | head -n 3 | tail -n 1 | sed -e "s/.*{\[//" -e "s/\],.*//")) 
  c3d $WDIR/futrim_om_to_hw.nii.gz $WDIR/futrim.nii.gz $segleft -interp NN -reslice-identity \
    -interp Linear -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm \
     -smooth 0.24mm -reslice-itk $WDIR/omRAS_half_itk.txt -thresh 0.5 1 1 0 -o $WDIR/fuseg_to_hw.nii.gz; 
  segright=/home/hwang3/sandy/DW/malf/T01_${i}_seg_1.nii.gz
  WDIR=$i/T01_affine12/unbiased_t1natnat_chunk/ibn_work_R/flirt_chunk_mp/normcorr_asym
  BLORIG=($(c3d $WDIR/bltrim.nii.gz -info-full | head -n 3 | tail -n 1 | sed -e "s/.*{\[//" -e "s/\],.*//")) 
  c3d $WDIR/futrim_om_to_hw.nii.gz $WDIR/futrim.nii.gz $segright -interp NN -reslice-identity \
    -interp Linear -origin ${BLORIG[0]}x${BLORIG[1]}x${BLORIG[2]}mm \
     -smooth 0.24mm -reslice-itk $WDIR/omRAS_half_itk.txt -thresh 0.5 1 1 0 -o $WDIR/fuseg_to_hw.nii.gz; 
done
