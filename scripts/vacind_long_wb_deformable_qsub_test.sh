#$ -S /bin/bash
set -x -e

BLTP=T01
LDIR=$DROOT
BLMPGRAY=$LDIR/${sub}/${BLTP}/tissueseg/t1biascorrected.nii.gz
FUMPGRAY=$LDIR/${sub}/${TP}/tissueseg/t1biascorrected.nii.gz
BLMPGRAY=$LDIR/${sub}/${BLTP}_${sub}_mprage.nii.gz
FUMPGRAY=$LDIR/${sub}/${TP}_${sub}_mprage.nii.gz
BLSEG=$LDIR/${sub}/${TP}_${sub}_ventricleseg.nii.gz
BRAINSEG=$LDIR/${sub}/${TP}_${sub}_brainmask.nii.gz

if [ -f $WORK/ibn_work_L/ANTS_mp/ANTS_RAS_mutualinfo_asym.mat ]; then


/home/srdas/wd/Pfizer/VACIND/scripts/bash/vacind_long_deformable_ITKv4_test.sh -d \
    -b $BLMPGRAY \
    -c $BLMPGRAY -e MPRAGE \
    -f $FUMPGRAY \
    -g $FUMPGRAY \
    -s $BLSEG \
    -w $WORK/ibn_work_wb -q 3 -n ${sub}_wb \
    -a $WORK/ibn_work_L/ANTS_mp/ANTS_RAS_mutualinfo_asym.mat

else
  echo "Global registration not found"
  exit -1
fi

# Make Jacobian-based change measurement
# Faking the ouTPut format of hemispheric atrophy rate measurements
if [ $(echo $sub | cut -c 3) == '1' ]; then
  grp=Control
else
  grp=aMCI
fi
grp=Unknown

/home/srdas/bin/ants/ANTSJacobian 3 $WORK/ibn_work_wb/ants/antsreg3dWarp.nii.gz $WORK/ibn_work_wb/ants/antsreg3d
gzip -f $WORK/ibn_work_wb/ants/antsreg3dgrid.nii $WORK/ibn_work_wb/ants/antsreg3djacobian.nii

c3d $WORK/ibn_work_wb/hwtrimdef.nii.gz $BLSEG -thresh 1 1 1 0 -smooth 0.24mm \
  -reslice-matrix $WORK/ibn_work_wb/omRAS_halfinv.mat -o $WORK/ibn_work_wb/labelhw_ven_fg.nii.gz
c3d $WORK/ibn_work_wb/hwtrimdef.nii.gz $BLSEG  -thresh 0 0 1 0 -smooth 0.24mm \
  -reslice-matrix $WORK/ibn_work_wb/omRAS_halfinv.mat -o $WORK/ibn_work_wb/labelhw_ven_bg.nii.gz
c3d $WORK/ibn_work_wb/hwtrimdef.nii.gz $BRAINSEG -thresh 1 1 1 0 -smooth 0.24mm \
  -reslice-matrix $WORK/ibn_work_wb/omRAS_halfinv.mat -o $WORK/ibn_work_wb/labelhw_brain_fg.nii.gz
c3d $WORK/ibn_work_wb/hwtrimdef.nii.gz $BRAINSEG  -thresh 0 0 1 0 -smooth 0.24mm \
  -reslice-matrix $WORK/ibn_work_wb/omRAS_halfinv.mat -o $WORK/ibn_work_wb/labelhw_brain_bg.nii.gz


c3d $WORK/ibn_work_wb/labelhw_ven* -vote -o $WORK/ibn_work_wb/seghw_ven.nii.gz
c3d $WORK/ibn_work_wb/labelhw_brain* -vote -o $WORK/ibn_work_wb/seghw_brain.nii.gz

BLVOL=$(c3d $WORK/ibn_work_wb/seghw_ven.nii.gz -dup -lstat | sed -n -e '3,$p' | awk '{print $6}')
FUVOL=$(c3d $WORK/ibn_work_wb/ants/antsreg3djacobian.nii.gz $WORK/ibn_work_wb/seghw_ven.nii.gz -thresh 1 1 1 0 -times -voxel-sum | awk '{print $3}')
echo $sub L chunk 3 mutualinfo ANTS 1 asym full 1 3 1 $FUVOL $BLVOL $grp > $WORK/ibn_work_wb/jac_longvol_ven_3d.txt
echo $sub R chunk 3 mutualinfo ANTS 1 asym full 1 3 1 $FUVOL $BLVOL $grp >> $WORK/ibn_work_wb/jac_longvol_ven_3d.txt

BLVOL=$(c3d $WORK/ibn_work_wb/seghw_brain.nii.gz -dup -lstat | sed -n -e '3,$p' | awk '{print $6}')
FUVOL=$(c3d $WORK/ibn_work_wb/ants/antsreg3djacobian.nii.gz $WORK/ibn_work_wb/seghw_brain.nii.gz -thresh 1 1 1 0 -times -voxel-sum | awk '{print $3}')
echo $sub L chunk 3 mutualinfo ANTS 1 asym full 1 3 1 $FUVOL $BLVOL $grp > $WORK/ibn_work_wb/jac_longvol_brain_3d.txt
echo $sub R chunk 3 mutualinfo ANTS 1 asym full 1 3 1 $FUVOL $BLVOL $grp >> $WORK/ibn_work_wb/jac_longvol_brain_3d.txt










