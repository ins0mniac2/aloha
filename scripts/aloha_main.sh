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
		  -h                Print help

******************** TODO below this ****************
		  -s integer        Run only one stage (see below); also accepts range (e.g. -s 1-3)
		  -N                No overriding of ANTS/FLIRT results. If a result from an earlier run
		                    exists, don't run ANTS/FLIRT again
		  -T                Tidy mode. Cleans up files once they are unneeded. The -N option will
		                    have no effect in tidy mode, because ANTS/FLIRT results will be erased.
		  -I string         Subject ID (for stats output). Defaults to last word of working dir.
		  -V                Display version information and exit
		  -C file           Configuration file. If not passed, uses $ALOHA_ROOT/bin/aloha_config.sh
		  -Q                Use Sun Grid Engine (SGE) to schedule sub-tasks in each stage. By default,
		                    the whole aloha_main job runs in a single process. If you are doing a lot
		                    of segmentations and have SGE, it is better to run each segmentation 
		                    (aloha_main) in a separate SGE job, rather than use the -q flag. The -q flag
		                    is best for when you have only a few segmentations and want them to run fast.
		  -q OPTS           Pass in additional options to SGE's qsub. Also enables -Q option above.
		  -r files          Compare segmentation results with a reference segmentation. The parameter
		                    files should consist of two nifti files in quotation marks:

		                      -r "ref_seg_left.nii.gz ref_seg_right.nii.gz"
                        
		                    The results will include overlap calculations between different
		                    stages of the segmentation and the reference segmentation. Note that the
		                    comparison takes into account the heuristic rules specified in the altas, so
		                    it is not as simple as computing dice overlaps between the reference seg
		                    and the ALOHA segs.

		stages:
		  1:                fit to population template
		  2:                multi-atlas registration
		  3:                consensus segmentation using voting
		  4:                bootstrap registration
		  5:                bootstrap segmentation using voting
		  6:                segmentation Q/A
		  7:                volumes and statistics

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

# Read the options
while getopts "b:f:r:s:t:u:w:c:g:dh" opt; do
  case $opt in

    b) ALOHA_BL_MPRAGE=$(readlink -f $OPTARG);;
    f) ALOHA_FU_MPRAGE=$(readlink -f $OPTARG);;
    r) ALOHA_BL_MPSEG_LEFT=$(readlink -f $OPTARG);;
    s) ALOHA_BL_MPSEG_RIGHT=$(readlink -f $OPTARG);;
    w) ALOHA_WORK=$(readlink -f $OPTARG);;
    c) ALOHA_BL_TSE=$(readlink -f $OPTARG);;
    g) ALOHA_FU_TSE=$(readlink -f $OPTARG);;
    t) ALOHA_BL_TSESEG_LEFT=$(readlink -f $OPTARG);;
    u) ALOHA_BL_TSESEG_RIGHT=$(readlink -f $OPTARG);;
    d) set -x -e;;
    h) usage; exit 0;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;

  esac
done

# Check the root dir
if [[ ! $ALOHA_ROOT ]]; then
  echo "Please set ALOHA_ROOT to the ALOHA root directory before running $0"
  exit -2
elif [[ $ALOHA_ROOT != $(readlink -f $ALOHA_ROOT) ]]; then
  echo "ALOHA_ROOT must point to an absolute path, not a relative path"
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

# Run the stages of the script
export ALOHA_ROOT ALOHA_WORK ALOHA_SKIP_ANTS ALOHA_SKIP_RIGID ALOHA_SUBJID ALOHA_CONFIG ALOHA_ATLAS
export ALOHA_HEURISTICS ALOHA_TIDY ALOHA_MPRAGE ALOHA_TSE ALOHA_REFSEG_LEFT ALOHA_REFSEG_RIGHT QOPTS
export ALOHA_BL_TSE ALOHA_BL_MPRAGE ALOHA_FU_TSE ALOHA_FU_MPRAGE ALOHA_BL_MPSEG_LEFT ALOHA_BL_TSESEG_LEFT ALOHA_BL_MPSEG_RIGHT ALOHA_BL_TSESEG_RIGHT ALOHA_USE_TSE

# Set the start and end stages
if [[ $STAGE_SPEC ]]; then
  STAGE_START=$(echo $STAGE_SPEC | awk -F '-' '$0 ~ /^[0-9]+-*[0-9]*$/ {print $1}')
  STAGE_END=$(echo $STAGE_SPEC | awk -F '-' '$0 ~ /^[0-9]+-*[0-9]*$/ {print $NF}')
else
  STAGE_START=2
  STAGE_END=15
fi

if [[ ! $STAGE_END || ! $STAGE_START ]]; then
  echo "Wrong stage specification -s $STAGE_SPEC"
  exit -1;
fi

# List of sides for the array qsub commands below
SIDES="left right"

# TEMP
STAGE_END=2
for ((STAGE=$STAGE_START; STAGE<=$STAGE_END; STAGE++)); do

  case $STAGE in 

    1) 
    # Initialize registration
    echo "Running stage 1: Initial alignment and bookkeeeping"
    qsubmit_sync "aloha_stg1" $ALOHA_ROOT/scripts/aloha_init.sh ;;

    2) 
    # Global alignment
    echo "Running stage 2: Global alignment"
    qsubmit_single_array "aloha_stg2"  "$SIDES" $ALOHA_ROOT/scripts/aloha_global.sh ;;

    3) 
    # Voting
    echo "Running stage 3: Label Fusion"
    qsubmit_single_array "aloha_stg3" "$SIDES" $ALOHA_ROOT/bin/aloha_voting_qsub.sh 0 ;;

    4)
    # Bootstrapping
    echo "Running stage 4: Bootstrap segmentation"
    qsubmit_double_array "aloha_stg4" "$SIDES" "$TRIDS" $ALOHA_ROOT/bin/aloha_bootstrap_qsub.sh ;;

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