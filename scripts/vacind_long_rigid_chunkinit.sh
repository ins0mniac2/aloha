set -x
# Run a series of affine registration to initialize the T2 longitudinal registration


if [ -f $FUGRAY -a -f $BLGRAY ]; then
	# Register T2 followup to T1 followup
	# Make the TSE image isotropic and extract a chunk
	c3d $FUGRAY -resample 100x100x500% -region 20x20x0% 60x60x60% -o ${WDIR}/tse_fu_iso.nii.gz

	# Reslice T1 into space of T2 chunk
	c3d ${WDIR}/tse_fu_iso.nii.gz $FUMPGRAY  -reslice-identity -o ${WDIR}/mprage_to_tse_fu_iso.nii.gz
:<<'COMM'
	# Run flirt -usesqform 
	# TODO The searchx/y/z parameters need to be -4 4 for FCD012 to work -- fix this, i mean do all subjects with
	# -4 4 and hope they all work 
        # They don't all work. Fix this. Perhaps try a search range, check metric and try again
	searchrange="-5 5"
	flirt -usesqform -v -in  ${WDIR}/mprage_to_tse_fu_iso.nii.gz -ref ${WDIR}/tse_fu_iso.nii.gz -omat ${WDIR}/fu_mprage_tse.mat \
  		-cost normmi -searchcost normmi -dof 6 -out ${WDIR}/mprage_to_tse_fu_iso_resliced.nii.gz \
  		 -searchrx $searchrange -searchry $searchrange -searchrz $searchrange  -coarsesearch 3 -finesearch 1
	flirt -usesqform -v -in  ${WDIR}/mprage_to_tse_fu_iso.nii.gz -ref ${WDIR}/tse_fu_iso.nii.gz -omat ${WDIR}/fu_mprage_tse_norange.mat \
  		-cost normmi -searchcost normmi -dof 6 -out ${WDIR}/mprage_to_tse_fu_iso_resliced_norange.nii.gz 
        
        MET=$(c3d ${WDIR}/tse_fu_iso.nii.gz ${WDIR}/mprage_to_tse_fu_iso_resliced.nii.gz -nmi | awk '{print int(1000*$3)}')
        METNORANGE=$(c3d ${WDIR}/tse_fu_iso.nii.gz ${WDIR}/mprage_to_tse_fu_iso_resliced_norange.nii.gz -nmi | awk '{print int(1000*$3)}')
  
        if [[ $MET -gt $METNORANGE ]]; then
          rm ${WDIR}/mprage_to_tse_fu_iso_resliced_norange.nii.gz ${WDIR}/fu_mprage_tse_norange.mat
        else
          mv ${WDIR}/mprage_to_tse_fu_iso_resliced_norange.nii.gz ${WDIR}/mprage_to_tse_fu_iso_resliced.nii.gz
          mv ${WDIR}/fu_mprage_tse_norange.mat ${WDIR}/fu_mprage_tse.mat
        fi
          

	c3d_affine_tool -src ${WDIR}/mprage_to_tse_fu_iso.nii.gz -ref ${WDIR}/tse_fu_iso.nii.gz ${WDIR}/fu_mprage_tse.mat \
  		-fsl2ras -o ${WDIR}/fu_mprage_tse_RAS.mat
COMM
      # Use ANTs instead of flirt
      /data/picsl/avants/bin/ants/antsRegistration -d 3 \
      -m Mattes[  $WDIR/tse_fu_iso.nii.gz, $WDIR/mprage_to_tse_fu_iso.nii.gz , 1 , 32, random , 0.1 ] \
      -t Rigid[ 0.2 ] \
      -c [1000x1000x1000,1.e-7,20]  \
      -s 4x2x0  \
      -f 4x2x1 -l 1 \
      -r [ $WDIR/tse_fu_iso.nii.gz, $WDIR/mprage_to_tse_fu_iso.nii.gz , 1 ] \
      -a 1 \
      -o [ $WDIR/fu_mprage_tse, $WDIR/mprage_to_tse_fu_iso_resliced.nii.gz, $WDIR/mprage_to_tse_fu_iso_resliced_inverse.nii.gz ]
    ConvertTransformFile 3 $WDIR/fu_mprage_tse0GenericAffine.mat \
        $WDIR/fu_mprage_tse_RAS.mat --hm



fi

# Register T1 followup to T1 baseline
flirt -usesqform -v -ref $BLMPGRAY -in $FUMPGRAY -omat ${WDIR}/mprage_long.mat -out ${WDIR}/mprage_fu_to_bl_resliced.nii.gz -dof 9
c3d_affine_tool -ref $BLMPGRAY -src $FUMPGRAY ${WDIR}/mprage_long.mat -fsl2ras -o ${WDIR}/mprage_long_RAS.mat

if [ -f $FUGRAY -a -f $BLGRAY ]; then
	# Register T2 baseline to T1 baseline
	# Make the TSE image isotropic and extract a chunk
	c3d $BLGRAY -resample 100x100x500% -region 20x20x0% 60x60x60% -o ${WDIR}/tse_bl_iso.nii.gz

	# Reslice T1 into space of T2 chunk
	c3d ${WDIR}/tse_bl_iso.nii.gz $BLMPGRAY  -reslice-identity -o ${WDIR}/mprage_to_tse_bl_iso.nii.gz


:<<'BLCOMM'
	# Run flirt -usesqform 
	searchrange="-5 5"
	flirt -usesqform -v -in ${WDIR}/mprage_to_tse_bl_iso.nii.gz -ref ${WDIR}/tse_bl_iso.nii.gz -omat ${WDIR}/bl_mprage_tse.mat \
  		-cost normmi -searchcost normmi -dof 6 -out ${WDIR}/mprage_to_tse_bl_iso_resliced.nii.gz \
  		-searchrx $searchrange -searchry $searchrange -searchrz $searchrange -coarsesearch 3 -finesearch 1
	flirt -usesqform -v -in ${WDIR}/mprage_to_tse_bl_iso.nii.gz -ref ${WDIR}/tse_bl_iso.nii.gz -omat ${WDIR}/bl_mprage_tse_norange.mat \
  		-cost normmi -searchcost normmi -dof 6 -out ${WDIR}/mprage_to_tse_bl_iso_resliced_norange.nii.gz 

        MET=$(c3d ${WDIR}/tse_bl_iso.nii.gz ${WDIR}/mprage_to_tse_bl_iso_resliced.nii.gz -nmi | awk '{print int(1000*$3)}')
        METNORANGE=$(c3d ${WDIR}/tse_bl_iso.nii.gz ${WDIR}/mprage_to_tse_bl_iso_resliced_norange.nii.gz -nmi | awk '{print int(1000*$3)}')
  
        if [[ $MET -gt $METNORANGE ]]; then
          rm ${WDIR}/mprage_to_tse_bl_iso_resliced_norange.nii.gz ${WDIR}/bl_mprage_tse_norange.mat
        else
          mv ${WDIR}/mprage_to_tse_bl_iso_resliced_norange.nii.gz ${WDIR}/mprage_to_tse_bl_iso_resliced.nii.gz
          mv ${WDIR}/bl_mprage_tse_norange.mat ${WDIR}/bl_mprage_tse.mat
        fi

	c3d_affine_tool -src  ${WDIR}/mprage_to_tse_bl_iso.nii.gz -ref ${WDIR}/tse_bl_iso.nii.gz ${WDIR}/bl_mprage_tse.mat \
  		-fsl2ras -o ${WDIR}/bl_mprage_tse_RAS.mat
BLCOMM

      # Use ANTs instead of flirt
      /data/picsl/avants/bin/ants/antsRegistration -d 3 \
      -m Mattes[  $WDIR/tse_bl_iso.nii.gz, $WDIR/mprage_to_tse_bl_iso.nii.gz , 1 , 32, random , 0.1 ] \
      -t Rigid[ 0.2 ] \
      -c [1000x1000x1000,1.e-7,20]  \
      -s 4x2x0  \
      -f 4x2x1 -l 1 \
      -r [ $WDIR/tse_bl_iso.nii.gz, $WDIR/mprage_to_tse_bl_iso.nii.gz , 1 ] \
      -a 1 \
      -o [ $WDIR/bl_mprage_tse, $WDIR/mprage_to_tse_bl_iso_resliced.nii.gz, $WDIR/mprage_to_tse_bl_iso_resliced_inverse.nii.gz ]
    ConvertTransformFile 3 $WDIR/bl_mprage_tse0GenericAffine.mat \
        $WDIR/bl_mprage_tse_RAS.mat --hm
	# Combine the 3 transformations above to get initial T2 longitudinal transform
	#convert_xfm -omat ${WDIR}/fu_tse_bl_mprage.mat -concat ${WDIR}/mprage_long.mat ${WDIR}/fu_tse_mprage.mat  
	#convert_xfm -omat ${WDIR}/bl_mprage_tse.mat -inverse ${WDIR}/bl_tse_mprage.mat
	#convert_xfm -omat ${WDIR}/tse_long.mat -concat ${WDIR}/bl_mprage_tse.mat  ${WDIR}/fu_tse_bl_mprage.mat 

	c3d_affine_tool ${WDIR}/bl_mprage_tse_RAS.mat  \
  		${WDIR}/mprage_long_RAS.mat ${WDIR}/fu_mprage_tse_RAS.mat -inv -o ${WDIR}/fu_tse_mprage_RAS.mat -mult -o ${WDIR}/fu_tse_bl_mprage_RAS.mat \
  		-mult -o ${WDIR}/tse_long_RAS.mat
	c3d_affine_tool -ref $BLGRAY -src $FUGRAY ${WDIR}/tse_long_RAS.mat -ras2fsl -o ${WDIR}/tse_long.mat

	#Initial resliced image for QA
	# why doesn't this work ?
	flirt -usesqform -v -ref $BLGRAY  -in $FUGRAY -out ${WDIR}/resliced_init_flirt.nii.gz -init ${WDIR}/tse_long.mat -applyxfm
	c3d $BLGRAY  $FUGRAY -reslice-matrix ${WDIR}/tse_long_RAS.mat -o ${WDIR}/resliced_init.nii.gz
fi
