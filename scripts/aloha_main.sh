#!/bin/bash
#$ -S /bin/bash

#######################################################################
#
#  Program:   ALOHA (Automatic Longitudinal Hippocampal Atrophy)
#  Module:    $Id$
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


function usage()
{
  cat <<-USAGETEXT
		aloha_main: automatic longitudinal hippocampal atrophy
		usage:
		  aloha_main [options]

		required options:
		  -b image          Filename of baseline 3D gradient echo MRI (ALOHA_BL_MPRAGE, T1w)
		  -f image          Filename of followup 3D gradient echo MRI (ALOHA_FU_MPRAGE, T1w)
		  -r image          Filename of left hippocampus segmentation of baseline 3D gradient echo MRI (ALOHA_BL_MPSEG_LEFT)
		  -s image          Filename of right hippocampus segmentation of baseline 3D gradient echo MRI (ALOHA_BL_MPSEG_RIGHT)
		  -w path           Working/output directory

		optional:
                                    The following three arguments are required for subfield atrophy rates using T2w MRI 
		  -c image          Filename of baseline 2D focal fast spin echo MRI (ALOHA_BL_TSE, T2w)
		  -g image          Filename of followup 2D focal fast spin echo MRI  (ALOHA_FU_TSE, T2w)
		  -t image          Filename of left subfield segmentation of baseline 2D focal fast spin echo MRI (ALOHA_BL_TSESEG_LEFT)
		  -u image          Filename of right subfield segmentation of baseline 2D focal fast spin echo MRI (ALOHA_BL_TSESEG_RIGHT)

		  -d                Enable debugging
		  -Q                Use Sun Grid Engine (SGE) to schedule sub-tasks in each stage. By default,
		                    the whole aloha_main job runs in a single process. If you are doing a lot
		                    of segmentations and have SGE, it is better to run each segmentation 
		                    (aloha_main) in a separate SGE job, rather than use the -q flag. The -q flag
		                    is best for when you have only a few segmentations and want them to run fast.
		  -q OPTS           Pass in additional options to SGE's qsub. Also enables -Q option above.
		  -z integer        Run only one stage (see below); also accepts range (e.g. -z 1-3)
                  -H                Tell ALOHA to use external hooks for reporting progress, errors, and warnings.
                                    The environment variables ALOHA_HOOK_SCRIPT must be set to point to the appropriate
                                    script. For an example script with comments, see ashs_default_hook.sh
                                    The purpose of the hook is to allow intermediary systems (e.g. XNAT) 
                                    to monitor ALOHA performance. An optional ALOHA_HOOK_DATA variable can be set

		  -h                Print help

		stages:
		  1:                Set up data and initial alignemnt
		  2:                Global registration
		  3:                Deformable registration
		  4:                Measure change with DBM


		notes:
		  The ALOHA_TSE image slice direction should be z. In other words, the dimension
		  of ALOHA_TSE image should be 400x400x30 or something like that, not 400x30x400
	USAGETEXT
}

# Print usage by default
if [[ $# -lt 1 ]]; then
  echo "Try $0 -h for more information."
  exit 2
fi


# Clear the variables affected by the flags
unset ALOHA_MPRAGE ALOHA_TSE ALOHA_WORK STAGE_SPEC
unset ALOHA_SKIP_ANTS ALOHA_SKIP_RIGID ALOHA_TIDY ALOHA_SUBJID
unset ALOHA_USE_QSUB ALOHA_SEG_LEFT ALOHA_SEG_RIGHT 
unset ALOHA_BL_TSE ALOHA_BL_MPRAGE ALOHA_FU_TSE ALOHA_FU_MPRAGE ALOHA_BL_MPSEG_LEFT ALOHA_BL_TSESEG_LEFT ALOHA_BL_MPSEG_RIGHT ALOHA_BL_TSESEG_RIGHT ALOHA_USE_TSE

# Set the default hook script - which does almost nothing
unset ALOHA_USE_CUSTOM_HOOKS


# Read the options
while getopts "b:f:r:s:t:u:w:c:g:q:z:dhHQ" opt; do
  case $opt in

    b) ALOHA_BL_MPRAGE=$(readlink -f $OPTARG);;
    f) ALOHA_FU_MPRAGE=$(readlink -f $OPTARG);;
    r) ALOHA_BL_MPSEG_LEFT=$(readlink -f $OPTARG);;
    s) ALOHA_BL_MPSEG_RIGHT=$(readlink -f $OPTARG);;
    w) ALOHA_WORK=$(readlink -f $OPTARG);;
    c) ALOHA_BL_TSE=$(readlink -f $OPTARG);;
    g) ALOHA_FU_TSE=$(readlink -f $OPTARG);;
    z) STAGE_SPEC=$OPTARG ;;
    t) ALOHA_BL_TSESEG_LEFT=$(readlink -f $OPTARG);;
    u) ALOHA_BL_TSESEG_RIGHT=$(readlink -f $OPTARG);;
    d) set -x -e;;    
    H) ALOHA_USE_CUSTOM_HOOKS=1;;
    h) usage; exit 0;;
    q) ALOHA_USE_QSUB=1; QOPTS=$OPTARG;;
    Q) ALOHA_USE_QSUB=1;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;

  esac
done

# Check the root dir
if [[ ! $ALOHA_ROOT ]]; then
  echo "Please set ALOHA_ROOT to the ALOHA root directory before running $0"
  exit -2
elif [[ $ALOHA_ROOT != $(readlink -f $ALOHA_ROOT) ]]; then
  echo "ALOHA_ROOT must point to an absolute path, not a relative path, nor a symlink"
  exit -2
fi

# Set the config file
if [[ ! $ALOHA_CONFIG ]]; then
  ALOHA_CONFIG=$ALOHA_ROOT/scripts/aloha_config.sh
fi

# Load the library. This also processes the config file
source $ALOHA_ROOT/scripts/aloha_lib.sh

# Check if the required parameters were passed in
echo "T1 baseline Image : ${ALOHA_BL_MPRAGE?   "Baseline T1-weighted MRI was not specified. See $0 -h"}"
echo "T1 followup Image : ${ALOHA_FU_MPRAGE?   "Followup T1-weighted MRI was not specified. See $0 -h"}"
echo "T1 baseline mask  : ${ALOHA_BL_MPSEG_LEFT?   "Baseline T1-weighted MRI left segmentation was not specified. See $0 -h"}"
echo "T1 baseline mask  : ${ALOHA_BL_MPSEG_RIGHT?   "Baseline T1-weighted MRI right segmentation was not specified. See $0 -h"}"
echo "WorkDir  : ${ALOHA_WORK?     "Working directory was not specified. See $0 -h"}"

# Check if T2 pipeline is needed
if [[ $ALOHA_BL_TSE || $ALOHA_FU_TSE || $ALOHA_BL_TSESEG_LEFT || $ALOHA_BL_TSESEG_RIGHT ]]; then
  echo "T2 baseline Image : ${ALOHA_BL_TSE?   "Baseline T2-weighted MRI was not specified. See $0 -h"}"
  echo "T2 followup Image : ${ALOHA_FU_TSE?   "Followup T2-weighted MRI was not specified. See $0 -h"}"
  echo "T2 baseline mask left : ${ALOHA_BL_TSESEG_LEFT?   "Baseline T2-weighted MRI left segmentation was not specified. See $0 -h"}"
  echo "T2 baseline mask right : ${ALOHA_BL_TSESEG_RIGHT?   "Baseline T2-weighted MRI right segmentation was not specified. See $0 -h"}"
  ALOHA_USE_TSE=true;
fi


# TODO provide qsub as optional
# ALOHA_USE_QSUB=1
# Whether we are using QSUB
if [[ $ALOHA_USE_QSUB ]]; then
  if [[ ! $SGE_ROOT ]]; then
    echo "-Q flag used, but SGE is not present."
    exit -1;
  fi
  echo "Using SGE with root $SGE_ROOT and options $QOPTS"
else
  echo "Not using SGE"
fi

# Convert the work directory to absolute path
mkdir -p ${ALOHA_WORK?}
ALOHA_WORK=$(cd $ALOHA_WORK; pwd)
if [[ ! -d $ALOHA_WORK ]]; then 
  echo "Work directory $ALOHA_WORK does not exist";
fi

# Make sure all files exist
if [[ ! $ALOHA_BL_MPRAGE || ! -f $ALOHA_BL_MPRAGE ]]; then
	echo "Baseline T1-weighted 3D gradient echo MRI (-b) must be specified"
	exit 2;
elif [[ ! $ALOHA_FU_MPRAGE || ! -f $ALOHA_FU_MPRAGE ]]; then
	echo "Followup T1-weighted 3D gradient echo MRI (-f) must be specified"
	exit 2;
elif [[ ! $ALOHA_BL_MPSEG_LEFT || ! -f $ALOHA_BL_MPSEG_LEFT ]]; then
	echo "Baseline T1-weighted 3D gradient echo MRI left segmentation (-s) must be specified"
	exit 2;
elif [[ ! $ALOHA_BL_MPSEG_RIGHT || ! -f $ALOHA_BL_MPSEG_RIGHT ]]; then
        echo "File is $ALOHA_BL_MPSEG_RIGHT"
	echo "Baseline T1-weighted 3D gradient echo MRI right segmentation (-s) must be specified"
	exit 2;
elif [[ ! $ALOHA_WORK ]]; then
	echo "Working/output directory must be specified"
	exit 2;
fi

if [[ $ALOHA_BL_TSE || $ALOHA_FU_TSE || $ALOHA_BL_TSESEG ]]; then
  if [[ ! $ALOHA_BL_TSE || ! -f $ALOHA_BL_TSE ]]; then
	echo "Baseline T2-weighted 2D fast spin echo MRI (-c) must be specified"
	exit 2;
  elif [[ ! $ALOHA_FU_TSE || ! -f $ALOHA_FU_TSE ]]; then
	echo "Followup T2-weighted 2D fast spin echo MRI (-g) must be specified"
	exit 2;
  elif [[ ! $ALOHA_BL_TSESEG_LEFT || ! -f $ALOHA_BL_TSESEG_LEFT ]]; then
	echo "Baseline T2-weighted 2D fast spin echo MRI left segmentation (-t) must be specified"
	exit 2;
  elif [[ ! $ALOHA_BL_TSESEG_RIGHT|| ! -f $ALOHA_BL_TSESEG_RIGHT ]]; then
	echo "Baseline T2-weighted 2D fast spin echo MRI right segmentation (-t) must be specified"
	exit 2;
  fi
fi

if [[ $ALOHA_BL_TSE ]]; then
  # Check that the dimensions of the T2 image are right
  DIMS=$(c3d $ALOHA_BL_TSE -info | cut -d ';' -f 1 | sed -e "s/.*\[//" -e "s/\].*//" -e "s/,//g")
  if [[ ${DIMS[2]} > ${DIMS[0]} || ${DIMS[2]} > ${DIMS[1]} ]]; then
    echo "The baseline T2-weighted image has wrong dimensions (fails dim[2] < min(dim[0], dim[1])"
    exit -1
  fi
fi

if [[ $ALOHA_FU_TSE ]]; then
  # Check that the dimensions of the T2 image are right
  DIMS=$(c3d $ALOHA_BL_TSE -info | cut -d ';' -f 1 | sed -e "s/.*\[//" -e "s/\].*//" -e "s/,//g")
  if [[ ${DIMS[2]} > ${DIMS[0]} || ${DIMS[2]} > ${DIMS[1]} ]]; then
    echo "The baseline T2-weighted image has wrong dimensions (fails dim[2] < min(dim[0], dim[1])"
    exit -1
  fi
fi

# Subject ID set to work dir last work
if [[ ! $ALOHA_SUBJID ]]; then
  ALOHA_SUBJID=$(basename $ALOHA_WORK)
fi

# Create the working directory and the dump directory
mkdir -p $ALOHA_WORK $ALOHA_WORK/dump $ALOHA_WORK/final

# Handle the hook scripts
if [[ $ALOHA_USE_CUSTOM_HOOKS ]]; then

  if [[ ! $ALOHA_HOOK_SCRIPT ]]; then
    echo "ALOHA_HOOK_SCRIPT must be set when using -H option"; exit -2
  fi

  if [[ ! -f $ALOHA_HOOK_SCRIPT ]]; then
    echo "ALOHA_HOOK_SCRIPT must point to a script file"; exit -2
  fi

  echo "Custom hooks requested with -H option"
  echo "  Hook script (\$ALOHA_HOOK_SCRIPT): $ALOHA_HOOK_SCRIPT"
  echo "  User data (\$ALOHA_HOOK_DATA): $ALOHA_HOOK_DATA"

else

  ALOHA_HOOK_SCRIPT=$ALOHA_ROOT/bin/aloha_default_hook.sh
  unset ALOHA_HOOK_DATA

fi

# Check for the existence of the hook script
if [[ ! -x $ALOHA_HOOK_SCRIPT ]]; then
  echo "ALOHA hook script does not point to an executable (ALOHA_HOOK_SCRIPT=$ALOHA_HOOK_SCRIPT)"
#  exit -2
fi

# :<<'NOORIENT'
# Add code to make images into canonical orientations
c3d $ALOHA_BL_MPRAGE -swapdim RPI -o  $ALOHA_WORK/mprage_bl.nii.gz
ALOHA_BL_MPRAGE=$ALOHA_WORK/mprage_bl.nii.gz
c3d $ALOHA_FU_MPRAGE -swapdim RPI -o  $ALOHA_WORK/mprage_fu.nii.gz
ALOHA_FU_MPRAGE=$ALOHA_WORK/mprage_fu.nii.gz
c3d $ALOHA_BL_MPSEG_LEFT -swapdim RPI -o $ALOHA_WORK/mprage_blseg_left.nii.gz
ALOHA_BL_MPSEG_LEFT=$ALOHA_WORK/mprage_blseg_left.nii.gz
c3d $ALOHA_BL_MPSEG_RIGHT -swapdim RPI -o $ALOHA_WORK/mprage_blseg_right.nii.gz
ALOHA_BL_MPSEG_RIGHT=$ALOHA_WORK/mprage_blseg_right.nii.gz
if [[ $ALOHA_BL_TSE || $ALOHA_FU_TSE || $ALOHA_BL_TSESEG_LEFT || $ALOHA_BL_TSESEG_RIGHT ]]; then
  c3d $ALOHA_BL_TSE -swapdim RIA -o  $ALOHA_WORK/tse_bl.nii.gz
  ALOHA_BL_TSE=$ALOHA_WORK/tse_bl.nii.gz
  c3d $ALOHA_FU_TSE -swapdim RIA -o  $ALOHA_WORK/tse_fu.nii.gz
  ALOHA_FU_TSE=$ALOHA_WORK/tse_fu.nii.gz
  c3d $ALOHA_BL_TSESEG_LEFT -swapdim RIA -o $ALOHA_WORK/tse_blseg_left.nii.gz
  ALOHA_BL_TSESEG_LEFT=$ALOHA_WORK/tse_blseg_left.nii.gz
  c3d $ALOHA_BL_TSESEG_RIGHT -swapdim RIA -o $ALOHA_WORK/tse_blseg_right.nii.gz
  ALOHA_BL_TSESEG_RIGHT=$ALOHA_WORK/tse_blseg_right.nii.gz
fi
# NOORIENT

# Run the stages of the script
export LD_LIBRARY_PATH=$ALOHA_ROOT/ext/Linux/lib:$LD_LIBRARY_PATH
export ALOHA_ROOT ALOHA_WORK ALOHA_SKIP_ANTS ALOHA_SKIP_RIGID ALOHA_SUBJID ALOHA_CONFIG ALOHA_ATLAS
export ALOHA_HEURISTICS ALOHA_TIDY ALOHA_MPRAGE ALOHA_TSE ALOHA_REFSEG_LEFT ALOHA_REFSEG_RIGHT QOPTS
export ALOHA_BL_TSE ALOHA_BL_MPRAGE ALOHA_FU_TSE ALOHA_FU_MPRAGE ALOHA_BL_MPSEG_LEFT ALOHA_BL_TSESEG_LEFT ALOHA_BL_MPSEG_RIGHT ALOHA_BL_TSESEG_RIGHT ALOHA_USE_TSE

# Set the start and end stages
if [[ $STAGE_SPEC ]]; then
  STAGE_START=$(echo $STAGE_SPEC | awk -F '-' '$0 ~ /^[0-9]+-*[0-9]*$/ {print $1}')
  STAGE_END=$(echo $STAGE_SPEC | awk -F '-' '$0 ~ /^[0-9]+-*[0-9]*$/ {print $NF}')
else
  STAGE_START=1
  STAGE_END=4
fi

if [[ ! $STAGE_END || ! $STAGE_START ]]; then
  echo "Wrong stage specification -s $STAGE_SPEC"
  exit -1;
fi

# List of sides for the array qsub commands below
SIDES="left right"

# TEMP
# STAGE_START=3
# STAGE_END=3
for ((STAGE=$STAGE_START; STAGE<=$STAGE_END; STAGE++)); do

  case $STAGE in 

    1) 
    # Initialize registration
    echo "Running stage 1: Initial alignment and bookkeeping"
    qsubmit_sync "aloha_stg1" $ALOHA_ROOT/scripts/aloha_init.sh ;;

    2) 
    # Global alignment
    echo "Running stage 2: Global alignment"
    qsubmit_single_array "aloha_stg2"  "$SIDES" $ALOHA_ROOT/scripts/aloha_global.sh ;;

    3) 
    # Deformable registration
    echo "Running stage 3: Deformable registration"
    qsubmit_single_array "aloha_stg3" "$SIDES" $ALOHA_ROOT/scripts/aloha_deformable.sh ;;

    4)
    # Measurement
    echo "Running stage 4: Measuring longitudinal change"
    qsubmit_single_array "aloha_stg4" "$SIDES"  $ALOHA_ROOT/scripts/aloha_measure.sh ;;

    5)
    # Bootstrap voting
    echo "Running stage 5: Bootstrap label fusion" 
    qsubmit_single_array "aloha_stg5" "$SIDES" $ALOHA_ROOT/bin/aloha_voting_qsub.sh 1 ;;

    6)
    # Final QA
    echo "Running stage 6: Final QA"
    qsubmit_sync "aloha_stg6" $ALOHA_ROOT/bin/aloha_finalqa_qsub.sh ;;
  
    7) 
    # Statistics & Volumes
    echo "Running stage 7: Statistics and Volumes"
    qsubmit_sync "aloha_stg7" $ALOHA_ROOT/bin/aloha_extractstats_qsub.sh ;;

  esac  

done
