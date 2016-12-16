#!/bin/bash

#######################################################################
#
#  Program:   ALOHA (Automatic Longitudinal Hippocampal Atrophy)
#  Module:    $Id: aloha_main.sh 101 2014-04-14 17:02:49Z yushkevich $
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


# -------------------------------------
# ALOHA configuration and parameter file
# -------------------------------------
#
# This file contains default settings for ALOHA. Users can make a copy of this
# file and change parameters to better suit their data. To use this file, make
# a copy of the $ALOHA_ROOT/scripts/aloha_config.sh, edit the copy, and pass the
# copy to the aloha_main script using the -C flag. TODO

# ---------------------------------
# ALOHA_TSE resolution-related parameters
# ---------------------------------
#
# The default parameters are configured for ALOHA_TSE images with 0.4 x 0.4 x 2.0
# voxel resolution, with a field of view that extends past the skull in the
# oblique coronal plane. If your data is different, you may want to change 
# these parameters

# The resampling factor to make data isotropic. The data does not have to be
# exactly isotropic. I suggest keeping all numbers multiples of 100. 
ALOHA_TSE_ISO_FACTOR="100x100x500%"

# The cropping applied to the ALOHA_TSE volume before rigid registration to the T1
# volume. If the field of view in the ALOHA_TSE images is limited, you may want to
# change this. Default crops 20% of the image in the oblique coronal plane
ALOHA_TSE_ISO_REGION_CROP="20x20x0% 60x60x100%"

# ----------------------------------
# ALOHA_TSE-ALOHA_MPRAGE registration parameters
# ----------------------------------

# The search parameters for FLIRT. You may want to play with these if the
# rigid alignment of T1 and T2 is failing. You can always override the results
# for any given image manually by performing the registration yourself and
# calling ALOHA with the -N flag (to not rerun existing registrations)
ALOHA_FLIRT_MULTIMODAL_OPTS="-searchrx -5 5 -searchry -5 5 -searchrz -5 5 -coarsesearch 3 -finesearch 1"

# ------------------------------------------------
# ALOHA_REG general longitudinal registration parameters
# ------------------------------------------------
#
# These parameters affect deformable registration of baseline and followup images 
ALOHA_REG_REGTYPE="chunk" # Use chunk or full to define whether whole brain image is used
ALOHA_REG_GLOBALREGPROG="ANTS" # Whether to use ANTs or flirt or global registration
ALOHA_REG_DEFREGPROG="ants" # Other deformable registration programs are not implemented yet
ALOHA_REG_DEFTYPE_MPRAGE=3 # Whether 2D or 3D registration is used. Change it only for TSE, although not recommended
ALOHA_REG_DEFTYPE_TSE=2
ALOHA_REG_INITTYPE="chunk" # How the initial alignment is done DO NOT CHANGE
ALOHA_REG_USEMASK=1 # DO NOT CHANGE
ALOHA_REG_USEDEFMASK=false # DO NOT CHANGE
ALOHA_REG_MASKRAD=3 # DO NOT CHANGE
ALOHA_REG_RESAMPLE="0" # DO NOT CHANGE
ALOHA_REG_RFIT=0 # DO NOT CHANGE
ALOHA_REG_ASTEPSIZE=0.25 # DO NOT CHANGE
ALOHA_REG_REGUL1=2.0 # DO NOT CHANGE
ALOHA_REG_REGUL2=0.5 # DO NOT CHANGE
ALOHA_REG_RIGIDMODE=HW # DO NOT CHANGE
ALOHA_REG_MODALITY=$9 # DO NOT CHANGE
ALOHA_REG_ALTMODESEG=false # DO NOT CHANGE
ALOHA_REG_DOMPSUB=0 # DO NOT CHANGE
ALOHA_REG_SEGALT=orig # DO NOT CHANGE
ALOHA_REG_ANTSVER=v4 # DO NOT CHANGE
# Mask radius for dilating mask and trimming for T1
ALOHA_REG_MPMASKRAD=10
ALOHA_REG_MPTRIM=24
ALOHA_REG_TSEMASKRAD=10
ALOHA_REG_TSETRIM=24

# ------------------------------------------------
# ALOHA_MEASURE longitudinal measurement parameters
# ------------------------------------------------
#
ALOHA_MEASURE_ATRMODE="BL" # Whether to make measurements in baseline space (BL) or halfway space (HW)
ALOHA_MEASURE_USEBNDMASK=false
ALOHA_MEASURE_USEPLABELMAP=true # DO NOT CHANGE
ALOHA_MEASURE_USETHICK=false # DO NOT CHANGE
ALOHA_MEASURE_USENATIVE=true # DO NOT CHANGE
ALOHA_MEASURE_USEMESH=true # DO NOT CHANGE
ALOHA_MEASURE_USEMASKOL=false # DO NOT CHANGE
ALOHA_MEASURE_CLEANALL=true # DO NOT CHANGE




# ------------------------------------------------
# ALOHA_MPRAGE longitudinal registration parameters
# ------------------------------------------------
#
# These parameters affect deformable registration of baseline and followup images 

# The number of iterations for ANTS when registering ALOHA_BL_MPRAGE and ALOHA_FU_MPRAGE
# This is one of the main parameters affecting the runtime of the program.
ALOHA_MPRAGE_ANTS_ITER="1200x1200x100"
ALOHA_TSE_ANTS_ITER="50x50x100"

# The amount of dilation applied to the average hippocampus mask in order to
# create a registration mask.
ALOHA_MPRAGE_ROI_DILATION="10x10x10vox"

# The size of the margin applied to the above registration mask when creating
# the ROI-specific template. This option only affects aloha_train. You can
# specify this in vox or mm units.
ALOHA_MPRAGEE_ROI_MARGIN="4x4x4vox"

# -----------------------------
# Histogram matching parameters
# -----------------------------
#

# The number of control points for histogram matching. See c3d -histmatch
# command. This is used for atlas building and application. In some cases 
# (for example 7T data with large intensity range) histogram matching seems
# to fail. You can set ALOHA_HISTMATCH_CONTROLS to 0 turn off matching.
ALOHA_HISTMATCH_CONTROLS=5


# -----------------------------------------------
# Pairwise multi-modality registration parameters
# -----------------------------------------------

# The number of ANTS iterations for running pairwise registration
ALOHA_PAIRWISE_ANTS_ITER="60x60x20"

# The step size for ANTS
ALOHA_PAIRWISE_ANTS_STEPSIZE="0.25"

# The relative weight given to the T1 image in the pairwise registration
# Setting this to 0 makes the registration only use the ALOHA_TSE images, which
# may be the best option. This has not been tested extensively. Should be 
# a floating point number between 0 and 1
ALOHA_PAIRWISE_ANTS_T1_WEIGHT=0

# The amount of smoothing applied to label images before warping them,
# can either be in millimeters (mm) or voxels (vox)
ALOHA_LABEL_SMOOTHING="0.24mm"

