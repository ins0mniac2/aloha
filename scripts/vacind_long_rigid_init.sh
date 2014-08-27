# Run a series of affine registration to initilize the T2 longitudinal registration

# Register T2 followup to T1 followup
# Reslice T1 into space of T2 
c3d $FUGRAY $FUMPGRAY  -reslice-identity -o ${WDIR}/mprage_to_tse_fu.nii.gz
flirt -usesqform -v -ref  $FUGRAY -in ${WDIR}/mprage_to_tse_fu.nii.gz -omat ${WDIR}/fu_mprage_tse.mat -cost normmi -searchcost normmi -dof 6 \
  -out ${WDIR}/mprage_to_tse_fu_resliced.nii.gz -searchrx -5 5 -searchry -5 5 -searchrz -5 5 -coarsesearch 3 -finesearch 1
c3d_affine_tool -ref $FUGRAY -src ${WDIR}/mprage_to_tse_fu.nii.gz ${WDIR}/fu_mprage_tse.mat -fsl2ras -o ${WDIR}/fu_mprage_tse_RAS.mat 

# Register T1 followup to T1 baseline
flirt -usesqform -v -ref $BLMPGRAY -in $FUMPGRAY -omat ${WDIR}/mprage_long.mat -dof 6 -out ${WDIR}/mprage_fu_to_bl_resliced.nii.gz
c3d_affine_tool -ref $BLMPGRAY -src $FUMPGRAY ${WDIR}/mprage_long.mat -fsl2ras -o ${WDIR}/mprage_long_RAS.mat

# Register T2 baseline to T1 baseline
# Reslice T1 into space of T2 
c3d $BLGRAY $BLMPGRAY  -reslice-identity -o ${WDIR}/mprage_to_tse_bl.nii.gz
flirt -usesqform -v -ref $BLGRAY -in ${WDIR}/mprage_to_tse_bl.nii.gz -omat ${WDIR}/bl_mprage_tse.mat -cost normmi -searchcost normmi -dof 6 \
  -out ${WDIR}/mprage_to_tse_bl_resliced.nii.gz -searchrx -5 5 -searchry -5 5 -searchrz -5 5 -coarsesearch 3 -finesearch 1
c3d_affine_tool -ref $BLGRAY -src ${WDIR}/mprage_to_tse_bl.nii.gz ${WDIR}/bl_mprage_tse.mat -fsl2ras -o ${WDIR}/bl_mprage_tse_RAS.mat


# Combine the 3 transformations above to get initial T2 longitudinal transform
#convert_xfm -omat ${WDIR}/fu_tse_bl_mprage.mat -concat ${WDIR}/mprage_long.mat ${WDIR}/fu_tse_mprage.mat  
#convert_xfm -omat ${WDIR}/bl_mprage_tse.mat -inverse ${WDIR}/bl_tse_mprage.mat
#convert_xfm -omat ${WDIR}/tse_long.mat -concat ${WDIR}/bl_mprage_tse.mat  ${WDIR}/fu_tse_bl_mprage.mat 

c3d_affine_tool ${WDIR}/bl_mprage_tse_RAS.mat  \
  ${WDIR}/mprage_long_RAS.mat ${WDIR}/fu_mprage_tse_RAS.mat -inv -o ${WDIR}/fu_tse_mprage_RAS.mat -mult -o ${WDIR}/fu_tse_bl_mprage_RAS.mat \
  -mult -o ${WDIR}/tse_long_RAS.mat


c3d_affine_tool -ref $BLGRAY -src $FUGRAY ${WDIR}/tse_long_RAS.mat -ras2fsl -o ${WDIR}/tse_long.mat

# Initial resliced image for QA
# why doesn't this work ?
flirt -usesqform -v -ref $BLGRAY  -in $FUGRAY -out ${WDIR}/resliced_init_flirt.nii.gz -init ${WDIR}/tse_long.mat -applyxfm
c3d $BLGRAY  $FUGRAY -reslice-matrix ${WDIR}/tse_long_RAS.mat -o ${WDIR}/resliced_init.nii.gz

