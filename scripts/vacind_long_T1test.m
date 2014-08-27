ROOT=/home/srdas/wd/Pfizer/VACIND/long/T1longtest
DROOT=/home/pauly/adni/pylong

for i in $ROOT/*_S_*; do 
  sub=`basename $i`;
  mkdir -p $ROOT/$sub
  c3d_affine_tool $DROOT/$sub//valor_test_exp03_L/T02/wbFlirtRAS.mat -sqrt -o $ROOT/$sub/T02_wbFlirtRAS_half.mat
  c3d_affine_tool $DROOT/$sub//valor_test_exp03_L/T02/wbFlirtRAS.mat -inv -sqrt -o $ROOT/$sub/T02_wbFlirtRAS_halfinv.mat
  
  c3d_affine_tool -sform $DROOT/$sub/valor_test_exp03_L/T02/moving.nii.gz \
    -sform $DROOT/$sub/valor_test_exp03_L/target.nii.gz \
    -inv -mult -sqrt -sform $DROOT/$sub/valor_test_exp03_L/target.nii.gz \
    -mult -o $ROOT/$sub/T02_hwspace.mat
  c3d $DROOT/$sub/valor_test_exp03_L/target.nii.gz -set-sform $ROOT/$sub/T02_hwspace.mat \
    $DROOT/$sub/valor_test_exp03_L/target.nii.gz -reslice-matrix $ROOT/$sub/T02_wbFlirtRAS_halfinv.mat \
    -o $ROOT/$sub/T02_hwimage.nii.gz
  c3d $ROOT/$sub/T02_hwimage.nii.gz $DROOT/$sub/valor_test_exp03_L/target.nii.gz \
    -reslice-matrix $ROOT/$sub/T02_wbFlirtRAS_halfinv.mat -o $ROOT/$sub/T02_bltrim_to_hw.nii.gz
  c3d $ROOT/$sub/T02_hwimage.nii.gz $DROOT/$sub/valor_test_exp03_L/T02/moving.nii.gz \
    -reslice-matrix $ROOT/$sub/T02_wbFlirtRAS_half.mat -o $ROOT/$sub/T02_futrim_to_hw.nii.gz
done
  
