#!/bin/bash - 

#######################################################################
#
#  Program:   ALOHA (Automatic Longitudinal Hippocampal Atrophy)
#  Module:    $Id: aloha_main.sh 101 2014-04-14 17:02:49Z srdas $
#  Language:  BASH Shell Script
#  Copyright (c) 2014 Sandhitsu R. Das, University of Pennsylvania
#  
#  This file is part of ALOHA
#
#  ALOHA is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details. 
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################


# ----------------------------------------------------
# A library of routines shared by all the ALOHA scripts
# ----------------------------------------------------

# The ALOHA_ROOT variable must be set
if [[ ! $ALOHA_ROOT ]]; then
  echo "ALOHA_ROOT is not set. Please set this variable to point to the root ALOHA directory"
  exit -1;
fi

echo "Script: $0"

# Get the architecture and check ability to run binaries
ARCH=$(uname);
ALOHA_BIN=$ALOHA_ROOT/ext/$ARCH/bin
ALOHA_ANTS=$ALOHA_BIN/ants
ALOHA_FSL=$ALOHA_BIN/fsl
if [[ ! $($ALOHA_BIN/c3d -version | grep 'Version') ]]; then
  echo "Can not execute command \'$ALOHA_BIN/c3d -version\'. Wrong architecture?"
  exit -1
fi

# Set the path for the ALOHA programs, to ensure that we don't call some other
# version of ants or c3d. This is nicer than having to prefix every call to
# c3d by the path. 
export PATH=$ALOHA_BIN:$ALOHA_ANTS:$ALOHA_FSL:$PATH


# If a custom config file specified, first read the default config file
if [[ ! ${ALOHA_CONFIG?} == ${ALOHA_ROOT?}/scripts/aloha_config.sh ]]; then
  source ${ALOHA_ROOT?}/scripts/aloha_config.sh
fi

# Read the config file
source ${ALOHA_CONFIG?}

# Determine the TMDDIR parameter for the child scripts
function get_tmpdir()
{
  # If TMPDIR is already set (i.e., aloha_main is run from qsub)
  # then this will create a subdirectory in TMPDIR. Otherwise
  # this will create a subdirectory in /tmp
  echo $(mktemp -d -t aloha.XXXXXXXX)
}

# Simulate qsub environment in bash (i.e., create and set tempdir)
# This function expects the name of the job as first parameter
function fake_qsub()
{
  local MYNAME=$1
  shift 1

  local PARENTTMPDIR=$TMPDIR
  TMPDIR=$(get_tmpdir)
  export TMPDIR

  bash $* 2>&1 | tee $ALOHA_WORK/dump/${MYNAME}.o$(date +%Y%m%d_%H%M%S)

  rm -rf $TMPDIR
  TMPDIR=$PARENTTMPDIR
}


# Submit a job to the queue (or just run job) and wait until it finishes
function qsubmit_sync()
{
  local MYNAME=$1
  shift 1

  if [[ $ALOHA_USE_QSUB ]]; then
    qsub $QOPTS -sync y -j y -o $ALOHA_WORK/dump -cwd -V -N $MYNAME $*
  else
    fake_qsub $MYNAME $*
  fi
}

# Submit an array of jobs parameterized by a single parameter. The parameter is passed in 
# to the job after all other positional parameters
function qsubmit_single_array()
{
  local NAME=$1
  local PARAM=$2
  shift 2;

  # Generate unique name to prevent clashing with qe
  local UNIQ_NAME=${NAME}_${$}

  for p1 in $PARAM; do

    if [[ $ALOHA_USE_QSUB ]]; then

      qsub $QOPTS -j y -o $ALOHA_WORK/dump -cwd -V -N ${UNIQ_NAME}_${p1} $* $p1

    else

      fake_qsub ${NAME}_${p1} $* $p1

    fi
  done

  # Wait for the jobs to be done
  qwait "${UNIQ_NAME}_*"
}


# Submit an array of jobs parameterized by a single parameter. The parameter is passed in 
# to the job after all other positional parameters
function qsubmit_double_array()
{
  local NAME=$1
  local PARAM1=$2
  local PARAM2=$3
  shift 3;

  # Generate unique name to prevent clashing with qe
  local UNIQ_NAME=${NAME}_${$}

  for p1 in $PARAM1; do
    for p2 in $PARAM2; do

      if [[ $ALOHA_USE_QSUB ]]; then

        qsub $QOPTS -j y -o $ALOHA_WORK/dump -cwd -V -N ${UNIQ_NAME}_${p1}_${p2} $* $p1 $p2

      else

        fake_qsub ${NAME}_${p1}_${p2} $* $p1 $p2

      fi
    done
  done

  # Wait for the jobs to be done
  qwait "${UNIQ_NAME}_*"
}


      



# Submit an array of jobs to the queue
function qsubmit_array()
{
  local NAME=$1
  local SIZE=$2
  local CMD="$3 $4 $5 $6 $7 $8 $9"

  if [[ $ALOHA_USE_QSUB ]]; then
    qsub $QOPTS -t 1-${SIZE} -sync y -j y -o $ALOHA_WORK/dump -cwd -V -N $NAME $CMD
  else
    for ((i=1; i<=$SIZE;i++)); do

      local PARENTTMPDIR=$TMPDIR
      TMPDIR=$(get_tmpdir)
      export TMPDIR

      local SGE_TASK_ID=$i
      export SGE_TASK_ID

      bash $CMD 2>&1 | tee $ALOHA_WORK/dump/${NAME}.o$(date +%Y%m%d_%H%M%S)

      rm -rf $TMPDIR
      TMPDIR=$PARENTTMPDIR
    done
  fi
}

# Wait for qsub to finish
function qwait() 
{
  if [[ $ALOHA_USE_QSUB ]]; then
    qsub -b y -sync y -j y -o /dev/null -cwd -hold_jid "$1" /bin/sleep 1
  fi
}

# Report the version number
function vers() 
{
  ALOHA_VERSION_SVN=$(cat $ALOHA_ROOT/bin/aloha_version.txt)
  echo $ALOHA_VERSION_SVN
}


# Report the progress for a job - pass a float between 0 and 1 for the particular
# job that has been qsubbed - this function takes care of figuring out where it
# fits into the overall progress
#
# This function relies on ALOHA_JOB_INDEX, ALOHA_JOB_COUNT, ALOHA_BATCH_PSTART, ALOHA_BATCH_PEND
# variables being properly set in order to assemble the progress, and on ALOHA_HOOK_SCRIPT to
# report the actual progress
function job_progress()
{
  # First implement only overall progress
  # Read the reported progress
  local PROGRESS=${1}
:<<'NOCHUNK'

  # The start and end for the current chunk
  local CHUNK_PSTART CHUNK_PEND

  # Figure out the start and end of this particular job
  read CHUNK_PSTART CHUNK_PEND <<<$(
    echo 1 | awk -v bs=$ALOHA_BATCH_PSTART -v be=$ALOHA_BATCH_PEND \
      -v j=$ALOHA_JOB_INDEX -v n=$ALOHA_JOB_COUNT \
      '{print bs + ((be - bs) * j) / n, bs + ((be - bs) * (j+1)) / n}')

  # Send this information to the hook script
  echo "CHUNK $ALOHA_BATCH_PSTART $ALOHA_BATCH_PEND"

  echo 1 | awk -v bs=$ALOHA_BATCH_PSTART -v be=$ALOHA_BATCH_PEND \
      -v j=$ALOHA_JOB_INDEX -v n=$ALOHA_JOB_COUNT \
      '{print bs + ((be - bs) * j) / n, bs + ((be - bs) * (j+1)) / n}'
  echo "CHUNK $CHUNK_PSTART $CHUNK_PEND $PROGRESS"
NOCHUNK
  # bash $ALOHA_HOOK_SCRIPT progress 0 1 $PROGRESS
  echo progress $PROGRESS
}


# This function aligns the T1 and T2 images together. It takes two parameters: the 
# path to a directory containing images mprage.nii.gz and tse.nii.gz, and a path to 
# the directory where the output of the registration is stored.
function aloha_align_t1t2()
{
  ALOHA_WORK=${1?}
  WFSL=${2?}

  if [[ -f $WFSL/flirt_t2_to_t1_ITK.txt && $ALOHA_SKIP_RIGID ]]; then
    
    echo "Skipping Rigid Registration"

  else

    # Use FLIRT to match T2 to T1
    export FSLOUTPUTTYPE=NIFTI_GZ

    # Make the ALOHA_TSE image isotropic and extract a chunk
    c3d $ALOHA_WORK/tse.nii.gz -resample ${ALOHA_TSE_ISO_FACTOR?} -region ${ALOHA_TSE_ISO_REGION_CROP?} \
			-o $TMPDIR/tse_iso.nii.gz

    # Reslice T1 into space of T2 chunk
    c3d $TMPDIR/tse_iso.nii.gz $ALOHA_WORK/mprage.nii.gz -reslice-identity -o $TMPDIR/mprage_to_tse_iso.nii.gz

    # Run flirt with T2 as reference (does it matter at this point?)
    flirt -v -ref $TMPDIR/tse_iso.nii.gz -in $TMPDIR/mprage_to_tse_iso.nii.gz \
      -omat $WFSL/flirt_intermediate.mat -cost normmi -dof 6 ${ALOHA_FLIRT_MULTIMODAL_OPTS?}

    # Convert the T1-T2 transform to ITK
    c3d_affine_tool $WFSL/flirt_intermediate.mat -ref $TMPDIR/tse_iso.nii.gz \
			-src $TMPDIR/mprage_to_tse_iso.nii.gz \
      -fsl2ras -inv -oitk $WFSL/flirt_t2_to_t1_ITK.txt

  fi
}

# This function performs multi-modality ANTS registration between an atlas and the target image
# See below for the list of variables that should be defined.
# Lastly, there is a parameter, whether this is being run in altas building mode (1 yes, 0 no)
function aloha_ants_pairwise()
{
  # Check required variables
	local ATLAS_MODE=${1?}
  cat <<-CHECK_aloha_ants_pairwise
		Workdir : ${WREG?}
		AtlasDir: ${TDIR?}
		AtlasId: ${tid?}
		Side: ${side?}
		Atlas Mode: ${ATLAS_MODE}
	CHECK_aloha_ants_pairwise

  # Run ANTS with current image as fixed, training image as moving
  if [[ $ALOHA_SKIP_ANTS && \
        -f $WREG/antsregAffine.txt && \
        -f $WREG/antsregWarp.nii.gz && \
        -f $WREG/antsregInverseWarp.nii.gz ]]
  then

    # If registration exists, skip this step
    echo "Skipping ANTS registration $side/$tid"

  else

    # Are we running multi-component registration
    if [[ $(echo $ALOHA_PAIRWISE_ANTS_T1_WEIGHT | awk '{print $1 == 0.0}') -eq 1 ]]; then

      # T1 has a zero weight
      local ANTS_METRIC_TERM="-m PR[tse_to_chunktemp_${side}.nii.gz,$TDIR/tse_to_chunktemp_${side}.nii.gz,1,4]"
      
    else

      # T1 has non-zero weight
      local T2WGT=$(echo $ALOHA_PAIRWISE_ANTS_T1_WEIGHT | awk '{print 1.0 - $1}')
      local ANTS_METRIC_TERM=\
        "-m PR[mprage_to_chunktemp_${side}.nii.gz,$TDIR/mprage_to_chunktemp_${side}.nii.gz,$ALOHA_PAIRWISE_ANTS_T1_WEIGHT,4] \
         -m PR[tse_to_chunktemp_${side}.nii.gz,$TDIR/tse_to_chunktemp_${side}.nii.gz,$T2WGT,4] \
         --use-all-metrics-for-convergence"
    fi 

    ANTS 3 \
      -x tse_to_chunktemp_${side}_regmask.nii.gz $ANTS_METRIC_TERM -o $WREG/antsreg.nii.gz \
			-i $ALOHA_PAIRWISE_ANTS_ITER -t SyN[$ALOHA_PAIRWISE_ANTS_STEPSIZE] -v

    # Compress the warps
    shrink_warp 3 $WREG/antsregWarp.nii.gz $WREG/antsregWarp.nii.gz
    shrink_warp 3 $WREG/antsregInverseWarp.nii.gz $WREG/antsregInverseWarp.nii.gz

  fi

  # I think we want to use the full TSE so we don't get confusion in regions
  # where the native chunks don't overlap
  local ATLAS_TSE=$TDIR/tse.nii.gz

  # But we certainly don't need to use the full segmentation! It's zero outside
  # of the native chunk anyway...
  local ATLAS_SEG=$TDIR/tse_native_chunk_${side}_seg.nii.gz

	# Some things are in different locations depending on if this is atlas mode or not
	if [[ $ATLAS_MODE -eq 1 ]]; then
		local ATLAS_ANTS_WARP=$TDIR/ants_t1_to_temp/ants_t1_to_tempWarp.nii.gz
		local ATLAS_ANTS_AFFINE=$TDIR/ants_t1_to_temp/ants_t1_to_tempAffine.txt
		local ATLAS_FLIRT=$TDIR/flirt_t2_to_t1/flirt_t2_to_t1_ITK.txt
	else
		local ATLAS_ANTS_WARP=$TDIR/ants_t1_to_chunktemp_${side}Warp.nii.gz
		local ATLAS_ANTS_AFFINE=$TDIR/ants_t1_to_tempAffine.txt
		local ATLAS_FLIRT=$TDIR/flirt_t2_to_t1_ITK.txt
	fi

  # Reslice the atlas into target space
  if [[ $ALOHA_SKIP && \
        -f $WREG/atlas_to_native.nii.gz &&
        -f $WREG/atlas_to_native_segvote.nii.gz ]]
  then

    echo "Skipping reslicing into native space"
  
  else

    # Create a composite warp from atlas to target image (temporary)
    /usr/bin/time -f "ComposeMultiTransform: walltime=%E, memory=%M" \
      ComposeMultiTransform 3 \
        $TMPDIR/fullWarp.nii \
        -R tse_native_chunk_${side}.nii.gz \
        -i flirt_t2_to_t1/flirt_t2_to_t1_ITK.txt \
        -i ants_t1_to_temp/ants_t1_to_tempAffine.txt \
        ants_t1_to_temp/ants_t1_to_tempInverseWarp.nii.gz \
        $WREG/antsregWarp.nii.gz \
        $WREG/antsregAffine.txt \
        $ATLAS_ANTS_WARP $ATLAS_ANTS_AFFINE $ATLAS_FLIRT

    # Apply the composite warp to the tse image
    /usr/bin/time -f "Warp TSE: walltime=%E, memory=%M" \
      WarpImageMultiTransform 3 $ATLAS_TSE \
        $WREG/atlas_to_native.nii.gz \
        $TMPDIR/fullWarp.nii

    # Warp the segmentation labels the same way. This should work with WarpImageMultiTransform --use-ML
    # but for some reason that is still broken. Let's use the old way
    local LSET=($(c3d $ATLAS_SEG -dup -lstat | awk 'NR > 1 {print $1}'))

    for ((i=0; i < ${#LSET[*]}; i++)); do

      local LID=$(printf '%03d' $i)
      c3d $ATLAS_SEG -thresh ${LSET[i]} ${LSET[i]} 1 0 -smooth $ALOHA_LABEL_SMOOTHING -o $TMPDIR/label_${LID}.nii.gz

      /usr/bin/time -f "Warp label ${LID}: walltime=%E, memory=%M" \
        WarpImageMultiTransform 3 $TMPDIR/label_${LID}.nii.gz \
          $TMPDIR/label_${LID}_warp.nii.gz \
          $TMPDIR/fullWarp.nii

    done

    # Perform voting using replacement rules
    local RULES=$(for ((i=0; i < ${#LSET[*]}; i++)); do echo $i ${LSET[i]}; done)
    c3d $TMPDIR/label_*_warp.nii.gz -vote -replace $RULES -o $WREG/atlas_to_native_segvote.nii.gz

  fi

	# In tidy mode, we can clean up after this step
	if [[ $ALOHA_TIDY ]]; then
		rm -rf $WREG/antsreg*
	fi
}

# This function performs what

# This function maps histogram-corrected whole-brain images into the 
# reference space of the template. Parameters are the atlas directory
# containing the input images, and the atlas directory
function aloha_reslice_to_template()
{
  ALOHA_WORK=${1?}
  ATLAS=${2?}
  WANT=$ALOHA_WORK/ants_t1_to_temp
  WFSL=$ALOHA_WORK/flirt_t2_to_t1

  # Apply the transformation to the masks
  for side in left right; do

    # Only generate these targets if needed
    if [[ $ALOHA_SKIP && \
          -f $ALOHA_WORK/tse_to_chunktemp_${side}.nii.gz && \
          -f $ALOHA_WORK/mprage_to_chunktemp_${side}.nii.gz && \
          -f $ALOHA_WORK/tse_to_chunktemp_${side}_regmask.nii.gz && \
          -f $ALOHA_WORK/tse_native_chunk_${side}.nii.gz ]]
    then
      echo "Skipping reslicing of data to template and native ROI"
    else

      # Define the reference space
      REFSPACE=$ATLAS/template/refspace_${side}.nii.gz

      # Map the image to the target space
      WarpImageMultiTransform 3 $ALOHA_WORK/tse_histmatch.nii.gz \
        $ALOHA_WORK/tse_to_chunktemp_${side}.nii.gz -R $REFSPACE \
        $WANT/ants_t1_to_tempWarp.nii.gz $WANT/ants_t1_to_tempAffine.txt $WFSL/flirt_t2_to_t1_ITK.txt

      # Map the image to the target space
      WarpImageMultiTransform 3 $ALOHA_WORK/mprage_histmatch.nii.gz \
        $ALOHA_WORK/mprage_to_chunktemp_${side}.nii.gz -R $REFSPACE \
        $WANT/ants_t1_to_tempWarp.nii $WANT/ants_t1_to_tempAffine.txt 

      # Create a custom mask for the ALOHA_TSE image
      c3d $ALOHA_WORK/tse_to_chunktemp_${side}.nii.gz -verbose -pim r -thresh 0.001% inf 1 0 \
        -erode 0 4x4x4 $REFSPACE -times -type uchar -o $ALOHA_WORK/tse_to_chunktemp_${side}_regmask.nii.gz

      # Create a combined warp from chunk template to T2 native space - and back
      ComposeMultiTransform 3 $TMPDIR/ants_t2_to_temp_fullWarp.nii.gz -R $REFSPACE \
        $WANT/ants_t1_to_tempWarp.nii.gz $WANT/ants_t1_to_tempAffine.txt $WFSL/flirt_t2_to_t1_ITK.txt

      ComposeMultiTransform 3 $TMPDIR/ants_t2_to_temp_fullInverseWarp.nii.gz \
        -R $ALOHA_WORK/tse.nii.gz -i $WFSL/flirt_t2_to_t1_ITK.txt \
        -i $WANT/ants_t1_to_tempAffine.txt $WANT/ants_t1_to_tempInverseWarp.nii.gz

      # Create a native-space chunk of the ALOHA_TSE image 
      WarpImageMultiTransform 3 $ALOHA_WORK/tse_to_chunktemp_${side}_regmask.nii.gz \
        $TMPDIR/natmask.nii.gz -R $ALOHA_WORK/tse.nii.gz $TMPDIR/ants_t2_to_temp_fullInverseWarp.nii.gz

      # Notice that we pad a little in the z-direction. This is to make sure that we get all the 
      # slices in the image, otherwise there will be problems with the voting code.
      c3d $TMPDIR/natmask.nii.gz -thresh 0.5 inf 1 0 -trim 0x0x2vox $ALOHA_WORK/tse.nii.gz \
        -reslice-identity -o $ALOHA_WORK/tse_native_chunk_${side}.nii.gz 

    fi

    # We also resample the segmentation (if it exists, i.e., training mode)
    if [[ -f $ALOHA_WORK/seg_${side}.nii.gz ]]; then
      if [[ $ALOHA_SKIP && -f $ALOHA_WORK/tse_native_chunk_${side}_seg.nii.gz ]]
      then
        echo "Skipping reslicing the segmentation to native space"
      else
        c3d $ALOHA_WORK/tse_native_chunk_${side}.nii.gz $ALOHA_WORK/seg_${side}.nii.gz \
          -int 0 -reslice-identity -o $ALOHA_WORK/tse_native_chunk_${side}_seg.nii.gz
      fi
    fi

  done
}

# This function call the label fusion command given the set of training images, the id of the 
# subject to segment, the side, and the output filename
function aloha_label_fusion()
{
  id=${1?}
  FNOUT=${2?}
  POSTERIOR=${3?}

cat <<-BLOCK1
	Script: aloha_atlas_pairwise.sh
	Root: ${ALOHA_ROOT?}
	Working directory: ${ALOHA_WORK?}
	PATH: ${PATH?}
	Subject: ${id?}
	Train Set: ${TRAIN?}
	Output: ${FNOUT?}
	Side: ${side?}
BLOCK1

  # Go to the atlas directory
  cd $ALOHA_WORK/atlas/$id

  # Perform label fusion using the atlases. We check for the existence of the atlases
  # so if one or two of the registrations failed, the whole process does not crash
  local ATLASES=""
  local ATLSEGS=""
  for id in $TRAIN; do
    local ACAND=pairwise/tseg_${side}_train${id}/atlas_to_native.nii.gz
    local SCAND=pairwise/tseg_${side}_train${id}/atlas_to_native_segvote.nii.gz
    if [[ -f $ACAND && -f $SCAND ]]; then
      ATLASES="$ATLASES $ACAND"
      ATLSEGS="$ATLSEGS $SCAND"
    fi
  done

  # If there are heuristics, make sure they are supplied to the LF program
  if [[ $ALOHA_HEURISTICS ]]; then
    EXCLCMD=$(for fn in $(ls heurex/heurex_${side}_*.nii.gz); do \
      echo "-x $(echo $fn | sed -e "s/.*_//g" | awk '{print 1*$1}') $fn"; \
      done)
  fi

  # Run the label fusion program
  /usr/bin/time -f "Label Fusion: walltime=%E, memory=%M" \
    label_fusion 3 -g $ATLASES -l $ATLSEGS \
      -m $ALOHA_MALF_STRATEGY -rp $ALOHA_MALF_PATCHRAD -rs $ALOHA_MALF_SEARCHRAD \
      $EXCLCMD \
      -p ${POSTERIOR} \
      tse_native_chunk_${side}.nii.gz $FNOUT
}

# This version of the function is called in aloha_main, where there are no
# ground truth segmentations to go on. It requires two rounds of label fusion
function aloha_label_fusion_apply()
{
	cd $ALOHA_WORK

	BOOTSTRAP=${1?}

cat <<-BLOCK1
	Script: aloha_atlas_pairwise.sh
	Root: ${ALOHA_ROOT?}
	Working directory: ${ALOHA_WORK?}
	PATH: ${PATH?}
	Side: ${side?}
	Bootstrap: ${BOOTSTRAP?}
BLOCK1

	if [[ $BOOTSTRAP -eq 1 ]]; then
		TDIR=$ALOHA_WORK/bootstrap
	else
		TDIR=$ALOHA_WORK/multiatlas
	fi

	mkdir -p $TDIR/fusion

  # Perform label fusion using the atlases
	local ATLASES=$(ls $TDIR/tseg_${side}_train*/atlas_to_native.nii.gz)
	local ATLSEGS=$(ls $TDIR/tseg_${side}_train*/atlas_to_native_segvote.nii.gz)

  # Run the label fusion program
	local RESULT=$TDIR/fusion/lfseg_raw_${side}.nii.gz
  label_fusion 3 -g $ATLASES -l $ATLSEGS \
    -m $ALOHA_MALF_STRATEGY -rp $ALOHA_MALF_PATCHRAD -rs $ALOHA_MALF_SEARCHRAD \
    -p $TDIR/fusion/posterior_${side}_%03d.nii.gz \
    tse_native_chunk_${side}.nii.gz $RESULT

  # If there are heuristics, make sure they are supplied to the LF program
  if [[ $ALOHA_HEURISTICS ]]; then

		# Apply the heuristics to generate exclusion maps
    mkdir -p $TDIR/heurex
    subfield_slice_rules $RESULT $ALOHA_HEURISTICS $TDIR/heurex/heurex_${side}_%04d.nii.gz

		# Rerun label fusion
    local EXCLCMD=$(for fn in $(ls $TDIR/heurex/heurex_${side}_*.nii.gz); do \
      echo "-x $(echo $fn | sed -e "s/.*_//g" | awk '{print 1*$1}') $fn"; \
      done)

		label_fusion 3 -g $ATLASES -l $ATLSEGS \
			-m $ALOHA_MALF_STRATEGY -rp $ALOHA_MALF_PATCHRAD -rs $ALOHA_MALF_SEARCHRAD \
			$EXCLCMD \
      -p $TDIR/fusion/posterior_${side}_%03d.nii.gz \
			tse_native_chunk_${side}.nii.gz $TDIR/fusion/lfseg_heur_${side}.nii.gz

	else
		# Just make a copy
		cp -a $TDIR/fusion/lfseg_raw_${side}.nii.gz $TDIR/fusion/lfseg_heur_${side}.nii.gz
	fi

	# Perform AdaBoost correction. In addition to outputing the corrected segmentation,
  # we output posterior probabilities for each label. 
  for kind in usegray nogray; do

    # The part of the command that's different for the usegray and nogray modes
    if [[ $kind = 'usegray' ]]; then GRAYCMD="-g tse_native_chunk_${side}.nii.gz"; else GRAYCMD=""; fi

    sa $TDIR/fusion/lfseg_heur_${side}.nii.gz \
      $ALOHA_ATLAS/adaboost/${side}/adaboost_${kind} \
      $TDIR/fusion/lfseg_corr_${kind}_${side}.nii.gz $EXCLCMD \
      $GRAYCMD -p $TDIR/fusion/posterior_${side}_%03d.nii.gz \
      -op $TDIR/fusion/posterior_corr_${kind}_${side}_%03d.nii.gz

  done
  
  # If there are reference segs, we have to repeat this again, but with heuristics from 
  # the reference segmentations. This allows us to make a more fair comparison
  if [[ $ALOHA_HEURISTICS && -f $ALOHA_WORK/refseg/refseg_${side}.nii.gz ]]; then

		# Rerun label fusion
    local EXCLCMD=$(for fn in $(ls $ALOHA_WORK/refseg/heurex/heurex_${side}_*.nii.gz); do \
      echo "-x $(echo $fn | sed -e "s/.*_//g" | awk '{print 1*$1}') $fn"; \
      done)

		label_fusion 3 -g $ATLASES -l $ATLSEGS \
			-m $ALOHA_MALF_STRATEGY -rp $ALOHA_MALF_PATCHRAD -rs $ALOHA_MALF_SEARCHRAD \
			$EXCLCMD \
      -p $TDIR/fusion/posterior_vsref_${side}_%03d.nii.gz \
			tse_native_chunk_${side}.nii.gz $TDIR/fusion/lfseg_vsref_heur_${side}.nii.gz

    # Rerun AdaBoost
    for kind in usegray nogray; do

      # The part of the command that's different for the usegray and nogray modes
      if [[ $kind = 'usegray' ]]; then GRAYCMD="-g tse_native_chunk_${side}.nii.gz"; else GRAYCMD=""; fi

      sa $TDIR/fusion/lfseg_vsref_heur_${side}.nii.gz \
        $ALOHA_ATLAS/adaboost/${side}/adaboost_${kind} \
        $TDIR/fusion/lfseg_vsref_corr_${kind}_${side}.nii.gz $EXCLCMD \
        $GRAYCMD -p $TDIR/fusion/posterior_vsref_${side}_%03d.nii.gz \
        -op $TDIR/fusion/posterior_corr_${kind}_vsref_${side}_%03d.nii.gz

    done

  fi
}




# *************************************************************
#  ENTRY-LEVEL ATLAS-BUILDING FUNCTIONS (Called by aloha_train)
# *************************************************************

# Initialize the atlas directory for each atlas
function aloha_atlas_initialize_directory()
{
  # Initialize Directory
  for ((i=0;i<$N;i++)); do
    id=${ATLAS_ID[i]}
    qsub $QOPTS -j y -o $ALOHA_WORK/dump -cwd -V -N "aloha_atlas_initdir_${id}" \
      $ALOHA_ROOT/bin/aloha_atlas_initdir_qsub.sh \
        $id ${ATLAS_T1[i]} ${ATLAS_T2[i]} ${ATLAS_LS[i]} ${ATLAS_RS[i]}
  done

  # Wait for jobs to complete
  qwait "aloha_atlas_initdir_*"
}

# Build the template using SYN
function aloha_atlas_build_template()
{
  # All work is done in the template directory
  mkdir -p $ALOHA_WORK/template_build
  pushd $ALOHA_WORK/template_build

  # Populate
  CMDLINE=""
  for id in ${ATLAS_ID[*]}; do
    ln -sf $ALOHA_WORK/atlas/${id}/mprage.nii.gz ./${id}_mprage.nii.gz
    CMDLINE="$CMDLINE ${id}_mprage.nii.gz"
  done

  # Run the template code
  if [[ -f atlastemplate.nii.gz && $ALOHA_SKIP_ANTS ]]; then
    echo "Skipping template building"
  else
    export ANTSPATH=$ALOHA_ANTS/
    export ANTS_QSUB_OPTS=$QOPTS
    buildtemplateparallel.sh -d 3 -o atlas -m ${ALOHA_TEMPLATE_ANTS_ITER?} -r 1 -t GR -s CC $CMDLINE
    
    # Compress the warps
    for id in ${ATLAS_ID[*]}; do
      shrink_warp 3 atlas${id}_mprageWarp.nii.gz atlas${id}_mprageWarp.nii.gz
      shrink_warp 3 atlas${id}_mprageInverseWarp.nii.gz atlas${id}_mprageInverseWarp.nii.gz
    done

    # Copy the template into the final folder
    mkdir -p $ALOHA_WORK/final/template/
    cp -av atlastemplate.nii.gz  $ALOHA_WORK/final/template/template.nii.gz

  fi

  # We should now map everyone's segmentation into the template to build a mask
  for side in left right; do

    if [[ $ALOHA_SKIP_ANTS && \
          -f $ALOHA_WORK/final/template/refspace_meanseg_${side}.nii.gz && \
          -f $ALOHA_WORK/final/template/refspace_mprage_${side}.nii.gz ]]
    then
      echo "Skipping template ROI definition"
    else

      # Create a working directory
      mkdir -p mask_${side}
      pushd mask_${side}

      # Warp each segmentation
      CMDLINE=""
      for id in ${ATLAS_ID[*]}; do

        WarpImageMultiTransform 3 $ALOHA_WORK/atlas/${id}/seg_${side}.nii.gz \
          ${id}_seg_${side}.nii.gz -R ../atlastemplate.nii.gz \
          ../atlas${id}_mprageWarp.nii.gz ../atlas${id}_mprageAffine.txt \
          $ALOHA_WORK/atlas/${id}/flirt_t2_to_t1/flirt_t2_to_t1_ITK.txt --use-NN

        CMDLINE="$CMDLINE ${id}_seg_${side}.nii.gz"
      done

      # Average the segmentations and create a target ROI with desired resolution
      c3d $CMDLINE \
        -foreach -thresh 0.5 inf 1 0 -endfor -mean -as M -thresh $ALOHA_TEMPLATE_MASK_THRESHOLD inf 1 0 \
        -o meanseg_${side}.nii.gz -dilate 1 ${ALOHA_TEMPLATE_ROI_DILATION} \
        -trim ${ALOHA_TEMPLATE_ROI_MARGIN?} \
        -resample-mm ${ALOHA_TEMPLATE_TARGET_RESOLUTION?} \
        -o refspace_${side}.nii.gz \
        ../atlastemplate.nii.gz -reslice-identity -o refspace_mprage_${side}.nii.gz \
        -push M -reslice-identity -thresh 0.5 inf 1 0 -o refspace_meanseg_${side}.nii.gz

      cp -a refspace*${side}.nii.gz $ALOHA_WORK/final/template/

      popd

    fi

  done

  # Use the first image in the atlas set as the reference for histogram matching
  if [[ $ALOHA_SKIP && \
        -f $ALOHA_WORK/final/ref_hm/ref_mprage.nii.gz && \
        -f $ALOHA_WORK/final/ref_hm/ref_tse.nii.gz ]]
  then
    echo "Skipping defining the histogram matching references"
  else
    mkdir -p $ALOHA_WORK/final/ref_hm
    HMID=${ATLAS_ID[${ALOHA_TARGET_ATLAS_FOR_HISTMATCH?}]}
    cp -av $ALOHA_WORK/atlas/$HMID/mprage.nii.gz $ALOHA_WORK/final/ref_hm/ref_mprage.nii.gz
    cp -av $ALOHA_WORK/atlas/$HMID/tse.nii.gz $ALOHA_WORK/final/ref_hm/ref_tse.nii.gz
  fi

  popd
}

# Resample all atlas images to the template
function aloha_atlas_resample_tse_to_template()
{
  # Now resample each atlas to the template ROI chunk, setting up for n-squared 
  # registration.
  for ((i=0;i<$N;i++)); do
    id=${ATLAS_ID[i]}
    qsub $QOPTS -j y -o $ALOHA_WORK/dump -cwd -V -N "aloha_atlas_resample_${id}" \
      $ALOHA_ROOT/bin/aloha_atlas_resample_to_template_qsub.sh $id
  done

  # Wait for jobs to complete
  qwait "aloha_atlas_resample_*"
}

# This is a high-level routine called from the atlas code to run the pairwise registration
function aloha_atlas_register_to_rest()
{
  # Launch all the individual registrations
  for id in ${ATLAS_ID[*]}; do
    for side in left right; do
      for tid in ${ATLAS_ID[*]}; do

        if [[ $id != $tid ]]; then

          qsub $QOPTS -j y -o $ALOHA_WORK/dump -cwd -V -N "aloha_nsq_${id}_${tid}" \
            $ALOHA_ROOT/bin/aloha_atlas_pairwise_qsub.sh $id $tid $side

        fi
      done
    done
  done

  # Wait for the jobs to be done
  qwait "aloha_nsq_*"
}


# Organize the output directory
function aloha_atlas_organize_final()
{
  # The final directory
  FINAL=$ALOHA_WORK/final

  # Generate a file that makes this an ALOHA atlas
  cat > $FINAL/aloha_atlas_vars.sh <<-CONTENT
		ALOHA_ATLAS_VERSION=$(aloha_version)
		ALOHA_ATLAS_N=$N
	CONTENT

  # Copy the heuristic rules if they exist
  if [[ $ALOHA_HEURISTICS ]]; then
    cp -av $ALOHA_HEURISTICS $FINAL/aloha_heuristics.txt
  else
    rm -rf $ALOHA_HEURISTICS $FINAL/aloha_heuristics.txt
  fi

  # Generate directories for each of the training images
  for ((i=0;i<$N;i++)); do

    # Use codes for atlas names, to make this publishable online
    CODE=$(printf train%03d $i)
    id=${ATLAS_ID[i]}

		# The output directory for this atlas
    ODIR=$FINAL/train/$CODE
    IDIR=$ALOHA_WORK/atlas/$id
    mkdir -p $ODIR

		# Copy the full ALOHA_TSE (fix this later!)
		cp -av $IDIR/tse.nii.gz $ODIR

    # Copy the stuff we need into the atlas directory
    for side in left right; do

      # Copy the images 
      cp -av \
        $IDIR/tse_native_chunk_${side}.nii.gz \
        $IDIR/tse_native_chunk_${side}_seg.nii.gz \
        $IDIR/tse_to_chunktemp_${side}.nii.gz \
        $IDIR/tse_to_chunktemp_${side}_regmask.nii.gz \
        $IDIR/mprage_to_chunktemp_${side}.nii.gz \
				$IDIR/seg_${side}.nii.gz \
        $ODIR/

      # Copy the transformation to the template space. We only care about
      # the part of this transformation that involves the template, to we
      # can save a little space here. 
      c3d $IDIR/mprage_to_chunktemp_${side}.nii.gz -popas REF \
        -mcs $IDIR/ants_t1_to_temp/ants_t1_to_tempWarp.nii.gz \
        -foreach -insert REF 1 -reslice-identity -info -endfor \
        -omc $ODIR/ants_t1_to_chunktemp_${side}Warp.nii.gz 

    done

    # Copy the affine transforms
    cp -av \
      $IDIR/ants_t1_to_temp/ants_t1_to_tempAffine.txt \
      $IDIR/flirt_t2_to_t1/flirt_t2_to_t1_ITK.txt \
      $ODIR/

  done

  # Copy the SNAP segmentation labels
  mkdir -p $FINAL/snap
  cp -av $ALOHA_LABELFILE $FINAL/snap/snaplabels.txt

  # If a custom config file specified, put a copy of it into the atlas directory
  if [[ ! ${ALOHA_CONFIG} == ${ALOHA_ROOT}/bin/aloha_config.sh ]]; then
    cp -av $ALOHA_CONFIG $FINAL/aloha_user_config.sh
  else
    rm -rf $FINAL/aloha_user_config.sh
    touch $FINAL/aloha_user_config.sh
  fi

  # Copy the system config as well
  cp -av $ALOHA_ROOT/bin/aloha_config.sh $FINAL/aloha_system_config.sh

  # Copy the adaboost training files
  for side in left right; do
    mkdir -p $FINAL/adaboost/${side}
    cp -av $ALOHA_WORK/train/main_${side}/adaboost* $FINAL/adaboost/${side}/
  done

  # Generate a brain mask for the template
  export FSLOUTPUTTYPE=NIFTI_GZ
  cd $FINAL/template
  bet2 template.nii.gz template_bet -m -v 
}


# Organize cross-validation directories for running cross-validation experiments
function aloha_atlas_organize_xval()
{
  # Training needs to be performed separately for the cross-validation experiments and for the actual atlas
  # building. We will do this all in one go to simplify the code. We create BASH arrays for the train/test
  local NXVAL=0
  if [[ -f $ALOHA_XVAL ]]; then
    NXVAL=$(cat $ALOHA_XVAL | wc -l)
  fi

  # Arrays for the main training
  XV_TRAIN[0]=${ATLAS_ID[*]}
  XV_TEST[0]=""
  XVID[0]="main"

  # Arrays for the cross-validation training
  for ((jx=1;jx<=$NXVAL;jx++)); do

    XV_TEST[$jx]=$(cat $ALOHA_XVAL | awk "NR==$jx { print \$0 }")
    XV_TRAIN[$jx]=$(echo $( for((i=0;i<$N;i++)); do echo ${ATLAS_ID[i]}; done | awk "\"{${XV_TEST[$jx]}}\" !~ \$1 {print \$1}"))
    XVID[$jx]=xval$(printf %04d $jx)

  done

  # Organize the directories
  for ((i=1; i<=$NXVAL; i++)); do

    # The x-validation ID
    local XID=${XVID[i]}
    local TRAIN=${XV_TRAIN[i]}

    # Create the atlas for this experiment (based on all the training cases for it)
    local XVATLAS=$ALOHA_WORK/xval/${XID}/atlas
    mkdir -p $XVATLAS

    # Create links to stuff from the main atlas
    for fn in $(ls $ALOHA_WORK/final | grep -v "\(adaboost\|train\)"); do
      ln -sf $ALOHA_WORK/final/$fn $XVATLAS/$fn
    done

    # For the train directory, only choose the atlases that are in the training set
    mkdir -p $XVATLAS/train
    local myidx=0
    for tid in $TRAIN; do

      # Get the index of the training ID among all training subjects
      local srcdir=$(for qid in ${ATLAS_ID[*]}; do echo $qid; done | awk "\$1~/$tid/ {printf \"train%03d\n\",NR-1}")
      local trgdir=$(printf "train%03d" $myidx)

      # Link the two directories
      ln -sf $ALOHA_WORK/final/train/$srcdir $XVATLAS/train/$trgdir

      # Increment the index
      myidx=$((myidx+1))
    done

    # For the adaboost directory, link the corresponding cross-validation experiment
    mkdir -p $XVATLAS/adaboost
    for side in left right; do
      ln -sf $ALOHA_WORK/train/${XID}_${side} $XVATLAS/adaboost/$side
    done

    # Now, for each test subject, initialize the ALOHA directory with links
    for testid in ${XV_TEST[i]}; do

      # Create the directory for this run
      local IDFULL=${XID}_test_${testid}
      local XVSUBJ=$ALOHA_WORK/xval/${XID}/test/$IDFULL
      mkdir -p $XVSUBJ

      # The corresponding atlas directory
      local MYATL=$ALOHA_WORK/atlas/$testid/

      # Populate the critical results to avoid having to run registrations twice
      mkdir -p $XVSUBJ/affine_t1_to_template
      ln -sf $MYATL/ants_t1_to_temp/ants_t1_to_tempAffine.txt $XVSUBJ/affine_t1_to_template/t1_to_template_ITK.txt

      mkdir -p $XVSUBJ/ants_t1_to_temp
      ln -sf $MYATL/ants_t1_to_temp/ants_t1_to_tempAffine.txt $XVSUBJ/ants_t1_to_temp/ants_t1_to_tempAffine.txt
      ln -sf $MYATL/ants_t1_to_temp/ants_t1_to_tempWarp.nii.gz $XVSUBJ/ants_t1_to_temp/ants_t1_to_tempWarp.nii.gz
      ln -sf $MYATL/ants_t1_to_temp/ants_t1_to_tempInverseWarp.nii.gz $XVSUBJ/ants_t1_to_temp/ants_t1_to_tempInverseWarp.nii.gz

      mkdir -p $XVSUBJ/flirt_t2_to_t1
      ln -sf $MYATL/flirt_t2_to_t1/flirt_t2_to_t1_ITK.txt $XVSUBJ/flirt_t2_to_t1/flirt_t2_to_t1_ITK.txt

      # We can also reuse the atlas-to-target stuff
      myidx=0
      for tid in $TRAIN; do
        for side in left right; do

          local tdir=$XVSUBJ/multiatlas/tseg_${side}_train$(printf %03d $myidx)  
          mkdir -p $tdir

          local sdir=$MYATL/pairwise/tseg_${side}_train${tid}

          for fname in antsregAffine.txt antsregInverseWarp.nii.gz antsregWarp.nii.gz; do
            ln -sf $sdir/$fname $tdir/$fname
          done
        done
        myidx=$((myidx+1))
      done

      # Now, we can launch the aloha_main segmentation for this subject!
      qsub $QOPTS -j y -o $ALOHA_WORK/dump -cwd -V -N "aloha_xval_${IDFULL}" \
        $ALOHA_ROOT/bin/aloha_main.sh \
          -a $XVATLAS -g $MYATL/mprage.nii.gz -f $MYATL/tse.nii.gz -w $XVSUBJ -N -d \
          -r "$MYATL/seg_left.nii.gz $MYATL/seg_right.nii.gz"

    done

  done

  # Wait for it all to be done
  qwait "aloha_xval_*"
}

# This function Qsubs the bl command unless the output is already present
function aloha_check_bl_result()
{
  local RESFILE=$1;

  if [[ -f $RESFILE ]]; then

    local LASTIT=$(cat $RESFILE | tail -n 1 | awk '{print $1}');

    if [[ $LASTIT -eq $ALOHA_EC_ITERATIONS ]]; then
      echo 1
      return
    fi
  fi
}


# This function runs the training for a single label in a training directory
function aloha_bl_train_qsub()
{
  local POSTLIST label id mode xvid side GRAYLIST
  xvid=${1?}
  side=${2?}
  label=${3?}

  # Generate the posterior list for this label
  POSTLIST=$(printf posteriorlist_%03d.txt $label)
  rm -rf $POSTLIST
  for id in $(cat trainids.txt); do
    echo $(printf loo_posterior_${id}_${side}_%03d.nii.gz $label) >> $POSTLIST
  done

  # We will generate two sets of training data: one with the grayscale information and
  # another that only uses the posterior maps, and no grayscale information
  for mode in usegray nogray; do

    # The extra parameter to bl
    if [[ $mode = "usegray" ]]; then GRAYLIST="-g graylist.txt"; else GRAYLIST=""; fi

    # Check if the training results already exist
    if [[ $ALOHA_SKIP && $(aloha_check_bl_result adaboost_${mode}-AdaBoostResults-Tlabel${label}) -eq 1 ]]; then

      echo "Skipping training for ${xvid}_${side} label $label adaboost_${mode}"

    else

      # Sampling factor used for dry runs
      local DRYFRAC=0.01

      # Execute a dry run, where we only check the number of samples at the maximum sampling rate
      NSAM=$(bl truthlist.txt autolist.txt $label \
        $ALOHA_EC_DILATION $ALOHA_EC_PATCH_RADIUS $DRYFRAC 0 adaboost_dryrun \
        $GRAYLIST -p $POSTLIST \
          | grep 'of training data' | tail -n 1 | awk -F '[: ]' '{print $13}')

      # Compute the fraction needed to obtain the desired number of samples per image
      local FRAC=$(echo 0 | awk "{ k=$NSAM / ($ALOHA_EC_TARGET_SAMPLES * $DRYFRAC); p=(k==int(k) ? k : 1 + int(k)); print p < 1 ? 1 : 1 / p }")

      # Now run for real
      /usr/bin/time -f "BiasLearn $mode: walltime=%E, memory=%M" \
        bl truthlist.txt autolist.txt $label \
          $ALOHA_EC_DILATION $ALOHA_EC_PATCH_RADIUS $FRAC $ALOHA_EC_ITERATIONS adaboost_${mode} \
            $GRAYLIST -p $POSTLIST

    fi

  done
}

# Top level code for AdaBoost training and cross-validation
function aloha_atlas_adaboost_train()
{
  # Training needs to be performed separately for the cross-validation experiments and for the actual atlas
  # building. We will do this all in one go to simplify the code. We create BASH arrays for the train/test
  local NXVAL=0
  if [[ -f $ALOHA_XVAL ]]; then 
    NXVAL=$(cat $ALOHA_XVAL | wc -l)
  fi

  # Arrays for the main training
  XV_TRAIN[0]=${ATLAS_ID[*]}
  XV_TEST[0]=""
  XVID[0]="main"

  # Arrays for the cross-validation training
  for ((jx=1;jx<=$NXVAL;jx++)); do

    XV_TEST[$jx]=$(cat $ALOHA_XVAL | awk "NR==$jx { print \$0 }")
    XV_TRAIN[$jx]=$(echo $( for((i=0;i<$N;i++)); do echo ${ATLAS_ID[i]}; done | awk "\"{${XV_TEST[$jx]}}\" !~ \$1 {print \$1}"))
    XVID[$jx]=xval$(printf %04d $jx)

  done

  # Perform initial multi-atlas segmentation
  for ((i=0; i<=$NXVAL; i++)); do
    for side in left right; do

      WTRAIN=$ALOHA_WORK/train/${XVID[i]}_${side}
      mkdir -p $WTRAIN

      # Perform the segmentation in a leave-one-out fashion among the training images
      for id in ${XV_TRAIN[i]}; do

        # The atlas set for the cross-validation
        TRAIN=$(echo ${XV_TRAIN[i]} | sed -e "s/\<$id\>//g")

        # The output path for the segmentation result
        FNOUT=$WTRAIN/loo_seg_${id}_${side}.nii.gz

        # The output path for the posteriors
        POSTERIOR=$WTRAIN/loo_posterior_${id}_${side}_%03d.nii.gz

        # Perform the multi-atlas segmentation if the outputs exist
        if [[ $ALOHA_SKIP && -f $FNOUT ]]; then
          echo "Skipping label fusion for ${XVID[i]}_${side}_loo_${id}"
        else
          qsub $QOPTS -j y -o $ALOHA_WORK/dump -cwd -V -N "aloha_lf_${XVID[i]}_${side}_loo_${id}" \
             $ALOHA_ROOT/bin/aloha_atlas_lf_qsub.sh $id "$TRAIN" $FNOUT $side $POSTERIOR
        fi
      done
    done
  done

  # Wait for all the segmentations to finish  
  qwait "aloha_lf_*_loo_*"

  # Now perform the training
  for ((i=0; i<=$NXVAL; i++)); do
    for side in left right; do

      WTRAIN=$ALOHA_WORK/train/${XVID[i]}_${side}
      pushd $WTRAIN

      # Create text files for input to bl
      rm -rf graylist.txt autolist.txt truthlist.txt trainids.txt
      for id in ${XV_TRAIN[i]}; do
        echo $ALOHA_WORK/atlas/$id/tse_native_chunk_${side}.nii.gz >> graylist.txt
        echo $ALOHA_WORK/atlas/$id/tse_native_chunk_${side}_seg.nii.gz >> truthlist.txt
        echo loo_seg_${id}_${side}.nii.gz >> autolist.txt
        echo $id >> trainids.txt
      done

      # Count the unique labels in the dataset. Note that for label 0 we perform the dilation to estimate
      # the actual number of background voxels
      for fn in $(cat truthlist.txt); do 
        c3d $fn -dup -lstat; 
      done | awk '$1 ~ /[0-9]+/ && $1 > 0 { h[$1]+=$6; h[0]+=$6 } END {for (q in h) print q,h[q] }' | sort -n > counts.txt

      # For each label, launch the training job. The number of samples is scaled to have roughly 1000 per label
      for label in $(cat counts.txt | awk '{print $1}'); do

        qsub $QOPTS $ALOHA_EC_QSUB_EXTRA_OPTIONS -j y -o $ALOHA_WORK/dump -cwd -V -N "aloha_bl_${XVID[i]}_${side}_${label}" \
           $ALOHA_ROOT/bin/aloha_atlas_bl_qsub.sh ${XVID[i]} $side $label

      done

      popd

    done
  done

  # Wait for the training to finish  
  qwait "aloha_bl_*"

}

# This function checks whether all ALOHA outputs have been created for a given stage
function aloha_check_train()
{
  local STAGE=$1
  local NERR=0
  local NWARN=0

  pushd $ALOHA_WORK

  for id in ${ATLAS_ID[*]}; do

    if [[ $STAGE -ge 0 ]]; then
      for image in tse.nii.gz mprage.nii.gz flirt_t2_to_t1/flirt_t2_to_t1_ITK.txt \
                   seg_left.nii.gz seg_right.nii.gz
      do
        if [[ ! -f atlas/$id/$image ]]; then
          echo "STAGE $STAGE: missing file atlas/$id/$image"
          let NERR=NERR+1
        fi
      done
    fi

    if [[ $STAGE -ge 1 ]]; then
      for kind in Warp InverseWarp; do
        if [[ ! -f template_build/atlas${id}_mprage${kind}.nii.gz ]]; then
          echo "STAGE $STAGE: missing file template_build/atlas${id}_mprage${kind}.nii.gz"
          let NERR=NERR+1
        fi
      done
    fi

    if [[ $STAGE -ge 2 ]]; then
      for side in left right; do
        for kind in \
          tse_native_chunk_${side} mprage_to_chunktemp_${side} \
          tse_to_chunktemp_${side} tse_to_chunktemp_${side}_regmask \
          seg_${side} 
        do
          if [[ ! -f atlas/$id/${kind}.nii.gz ]]; then
            echo "STAGE $STAGE: missing file atlas/$id/${kind}.nii.gz"
            let NERR=NERR+1
          fi
        done
      done
    fi

    if [[ $STAGE -ge 3 ]]; then
      for side in left right; do
        missing=0
        for tid in ${ATLAS_ID[*]}; do
          if [[ $id != $tid ]]; then
            base=atlas/$id/pairwise/tseg_${side}_train${tid}
            if [[ ! -f $base/atlas_to_native_segvote.nii.gz ]]; then
              echo "STAGE $STAGE: missing file $base/atlas_to_native_segvote.nii.gz"
              let NWARN=NWARN+1
              let missing=missing+1
            fi
          fi
        done
        if [[ $missing -ge $((N-1)) ]]; then
          echo "STAGE $STAGE: missing all pairwise results for atlas $id side $side"
          let NERR=NERR+1
        fi
      done
    fi

  done

  # Cross-validation
  local NXVAL=0
  if [[ -f $ALOHA_XVAL ]]; then 
    NXVAL=$(cat $ALOHA_XVAL | wc -l)
  fi

  # Arrays for the main training
  XV_TRAIN[0]=${ATLAS_ID[*]}
  XV_TEST[0]=""
  XVID[0]="main"

  # Arrays for the cross-validation training
  for ((jx=1;jx<=$NXVAL;jx++)); do

    XV_TEST[$jx]=$(cat $ALOHA_XVAL | awk "NR==$jx { print \$0 }")
    XV_TRAIN[$jx]=$(echo $( for((i=0;i<$N;i++)); do echo ${ATLAS_ID[i]}; done | awk "\"{${XV_TEST[$jx]}}\" !~ \$1 {print \$1}"))
    XVID[$jx]=xval$(printf %04d $jx)

  done

  # Loop over the cross-validation experiments
  if [[ $STAGE -ge 4 ]]; then

    for ((i=0; i<=$NXVAL; i++)); do
      for side in left right; do

        WTRAIN=$ALOHA_WORK/train/${XVID[i]}_${side}

        # Perform the segmentation in a leave-one-out fashion among the training images
        for id in ${XV_TRAIN[i]}; do

          if [[ ! -f $WTRAIN/loo_seg_${id}_${side}.nii.gz ]]; then
            echo "STAGE $STAGE: missing file $WTRAIN/loo_seg_${id}_${side}.nii.gz"
            let NERR=NERR+1
          fi

        done

        # Look for the adaboost results
        if [[ ! -f $WTRAIN/counts.txt ]]; then
          echo "STAGE $STAGE: missing file $WTRAIN/counts.txt"
          let NERR=NERR+1
        fi

        for label in $(cat $WTRAIN/counts.txt | awk '{print $1}'); do
          for kind in usegray nogray; do
            if [[ ! -f $WTRAIN/adaboost_${kind}-AdaBoostResults-Tlabel${label} ]]; then
              echo "STAGE $STAGE: missing file $WTRAIN/adaboost_${kind}-AdaBoostResults-Tlabel${label}"
              let NERR=NERR+1
            fi
          done
        done

      done
    done 

  fi

  popd

  echo "*****************************"
  echo "VALIDITY CHECK AT STAGE $STAGE FOUND $NERR ERRORS AND $NWARN WARNINGS"
  echo "*****************************"
  if [[ $NERR -gt 0 ]]; then exit -1; fi
}
