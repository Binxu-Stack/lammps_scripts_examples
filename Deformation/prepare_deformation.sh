#!/bin/bash

## script to prepare deformation scripts 
## Both AQS and 50 K shear jobs are created

## usage:
## ./prepare_deformation.sh restart_file
## create one 1-AQS directory to put AQS jobs
## and one 2-deform directory to put deformation jobs
## 
## 50 K deformation: iso_configuration average strategy is used.

# use the following parameters
#restart_file="800K_10_50K_relaxed.restart"
restart_file=$1

maximum_strain="0.50"
AQS_force_tolerance="4e-4"    # should be testes for different system
deformation_rate="1e10 1e9 1e8 1e7"
iso_configuration_number=10   # deformation times for iso configuration


# AQS scripts

AQS_dir="1-AQS"

[ -d $AQS_dir ] || mkdir $AQS_dir  # if dir doesn't exist, create

# go to AQS_dir
cp $restart_file $AQS_dir

cd $AQS_dir

# create lammps scripts
cat <<EOF > in.AQS
## Script description

## system Zr50Cu40Al10

## Athermal quasistatic shear


# time unit: s
variable temp0                  equal 800  		# T_f
variable sample_index 		equal 20 		# Sample index
variable tstep  		equal "1e-3"
variable deformrate  		equal 4e7
variable drate 			equal "v_deformrate  * 1e-12"
variable maxstrain   		equal  ${maximum_strain}
variable runstep 		equal  "v_maxstrain / v_drate / v_tstep"
variable strain_step 		equal "1e-5"
variable nstep 			equal "round(v_maxstrain/v_strain_step)"
variable dxy 			equal "v_strain_step * ly"
variable n  			loop \${nstep}
variable natoms 		equal 8000
variable pea 			equal "pe / v_natoms"
variable stress 		equal "-pxy"



# ensamble
variable Pdamp equal "v_tstep * 1000"  # suggusted value for Nose-Hoover thermostate
variable Tdamp equal "v_tstep * 100"   # suggusted value for Nose-Hoover thermostate
#variable temp1 equal 1900
variable pressure equal 0


# boundary and units
boundary         p p p
units            metal
dimension 	 3
atom_style       atomic

# geometry


read_restart ${restart_file}
#
# ========== Define Interatomic Potential =============================
# Some suggestions: you may put the potential file in the environmental
# variable localtion \$LAMMPS_POTENTIALS (set it in ~/.bashrc)
#----------------------------------------------------------------------
pair_style  eam/alloy
pair_coeff  * * ZrCuAl.lammps.eam Zr Cu Al
# =====================================================================

# ========== Define the pairwise neighbor list methods ================
# In most situations, the style bin is the fastest methods. All of styles
# should give the same answers. "nsq" style may be faster for unsolvated small 
# molecules in a non-periodic box. "multi" style is useful for system
# with a wide range of cutoff distance.
# ---------------------------------------------------------------------
neighbor 2.0 bin
neigh_modify delay 0 every 4 check yes
# =====================================================================

#
reset_timestep   0
timestep         \${tstep}

change_box all triclinic

variable strain equal "xy / ly"

#                     1   2       3     4      5   6   7   8   9   10 11  12  13
thermo_style custom step temp fnorm etotal vol  pe pxx pyy pzz pxy pyz pxz v_strain
thermo 100

# deformation
fix BOXRELAX all box/relax vmax 0.001
minimize 0 ${AQS_force_tolerance} 100000 100000
unfix BOXRELAX

print  "! 0 \${strain} \${stress} \${pea}"

label shearloop
change_box all xy delta \${dxy} remap units box

min_style cg
minimize 0 ${AQS_force_tolerance} 100000 100000
print  "! \${n} \${strain} \${stress} \${pea}"
next n

jump SELF shearloop

write_restart final.restart

label END
EOF

# submit jobs here
# submit -y -n 32 lmp -in in.AQS

# go back to parent dir
cd ..

# prepare deformation jobs
deform_dir="2-deform"
[ -d $deform_dir ] || mkdir $deform_dir  # if dir doesn't exist, create

cd $deform_dir

index=1
for rate in $deformation_rate; do
  dir=${index}-${rate}
  [ -d $dir ] || mkdir $dir
  cp ../$restart_file $dir
  cd $dir
cat <<EOF > in.deformation
## Script description

## system Zr50Cu40Al10


# time unit: s

variable iso_index 		loop 10

label iso_loop

clear
log log.lammps.\${iso_index}
variable seed 			equal "v_iso_index+100"
variable temp0                  equal 800   # T_f
variable tstep  		equal "2e-3"
variable sample_index 		equal 10
variable deformrate  		equal ${rate}
variable drate 			equal "v_deformrate  * 1e-12"
variable maxstrain   		equal ${maximum_strain} 
variable runstep 		equal  "v_maxstrain / v_drate / v_tstep"
variable deform_T 		equal  50



# ensamble
variable Pdamp equal "v_tstep * 1000"  # suggusted value for Nose-Hoover thermostate
variable Tdamp equal "v_tstep * 100"   # suggusted value for Nose-Hoover thermostate
#variable temp1 equal 1900
variable pressure equal 0


# boundary and units
boundary         p p p
units            metal
dimension 	 3
atom_style       atomic

# geometry


#read_data        data.pos
read_restart ${restart_file}
#
# ========== Define Interatomic Potential =============================
# Some suggestions: you may put the potential file in the environmental
# variable localtion \$LAMMPS_POTENTIALS (set it in ~/.bashrc)
#----------------------------------------------------------------------
pair_style  eam/alloy
pair_coeff  * * ZrCuAl.lammps.eam Zr Cu Al
# =====================================================================

# ========== Define the pairwise neighbor list methods ================
# In most situations, the style bin is the fastest methods. All of styles
# should give the same answers. "nsq" style may be faster for unsolvated small 
# molecules in a non-periodic box. "multi" style is useful for system
# with a wide range of cutoff distance.
# ---------------------------------------------------------------------
neighbor 2.0 bin
neigh_modify delay 0 every 4 check yes
# =====================================================================

reset_timestep   0
timestep         \${tstep}
change_box all triclinic

variable strain equal "xy / ly"

#                     1   2       3     4      5   6   7   8   9   10 11  12  13
thermo_style custom step temp enthalpy etotal vol  pe pxx pyy pzz pxy pyz pxz v_strain
thermo 100
#
velocity all  create \${deform_T} \${seed} mom yes rot yes loop local units box

fix NVT all nvt temp \${deform_T} \${deform_T} \${Tdamp}
# run 100 ps
run 50000
unfix NVT



fix NVT all nvt/sllod temp \${deform_T} \${deform_T} \${Tdamp}
fix DEFORM   all  deform 1 xy erate \${drate} remap v units box
#dump 1 all atom 10000 dump.lammpstrj

run \${runstep}

next iso_index
jump SELF iso_loop

label END
EOF
# submit jobs here
# submit -y -n 32 lmp -in in.deformation

  cd ..
  index=$((index+1))
done
cd ..

