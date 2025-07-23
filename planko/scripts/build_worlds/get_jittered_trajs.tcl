#takes in a dg file with world information, runs jittered simulations for each world, outputs simulation results 

dg_create test_jitworlds
package require planko
source jitter_worlds.tcl

# Load original dgz file
set olddg [dg_load "l_simulation_060525008.dgz"]

# Create new dg for jittering
dg_create test_jitworlds

# Get number of trials
set ntrials [dl_length $olddg:world#name]

# Loop through trials and convert og dgz columns to new dg columns
for {set i 0} {$i < $ntrials} {incr i} {
    # Get object info
    set names  [dl_get $olddg:world#name $i]
    set txs    [dl_get $olddg:world#tx $i]
    set tys    [dl_get $olddg:world#ty $i]
    set nobj   [dl_length $names]

    # Copy base world data
    dl_set test_jitworlds:name:$i   $names
    dl_set test_jitworlds:tx:$i     $txs
    dl_set test_jitworlds:ty:$i     $tys
    dl_set test_jitworlds:angle:$i  [dl_repeat 0.0 $nobj]

    # Convert trajectory (linked) to x and y; interpretable by jitter_worlds
    set traj [dl_get $olddg:trajectory $i]
    set xlist {}
    set ylist {}
    foreach pt $traj {
        lassign $pt x y
        lappend xlist $x
        lappend ylist $y
    }
    dl_set test_jitworlds:ball_x:$i $xlist
    dl_set test_jitworlds:ball_y:$i $ylist

    # Copy nhit
    dl_set test_jitworlds:nhit:$i [dl_get $olddg:nhit $i]
}

# Save the new file
dg_write test_jitworlds  ; saves to "test_jitworlds.dgz"

### TEST: saving trajectories directly vs. saving HIT PLANK UNCS directly