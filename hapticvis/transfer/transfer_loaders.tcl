#
# LOADERS
#   hapticvis transfer
#
# DESCRIPTION
#   loader methods for hapticvis transfer
#

#
# Currently only supports 4, 6, 8 choices properly
#   The "correct_choice" is numbered 1-n_choices
#    but the centers differ depending on the number of choices so
#

# Ayan's version

package require haptic

namespace eval hapticvis::transfer {
    proc loaders_init { s } {

        $s add_method add_subject_blocks { subject_id block_id dbfile shapedb } {
            set row [dl_find [trialdb:subject $subject_id]]
            if { $row >= 0 } { return }
        }

        $s add_method setup_visual { subject_id subject_set n_per_set shape_scale noise_type n_rep rotations joystick_side subject_handedness} {
            my setup_trials identity $subject_id $subject_set $n_per_set visual $shape_scale $noise_type $n_rep $rotations $joystick_side $subject_handedness
        }

        $s add_method setup_haptic { subject_id subject_set n_per_set n_rep rotations joystick_side subject_handedness} {
            set shape_scale 1
            set noise_type none
            my setup_trials identity $subject_id $subject_set $n_per_set haptic $shape_scale $noise_type $n_rep $rotations $joystick_side $subject_handedness
        }

        $s add_method setup_visual_cued { subject_id subject_set n_per_set shape_scale noise_type n_rep rotations joystick_side subject_handedness } {
            my setup_trials identity $subject_id $subject_set $n_per_set visual $shape_scale $noise_type $n_rep $rotations $joystick_side $subject_handedness

            # now create a column for cue centers
            # for half the trials, the cue center matches the target
            # for the other half, the cue center is from another loc
            set n [dl_length stimdg:stimtype]
            dl_set stimdg:is_cued [dl_ones $n]
            dl_local target_loc [dl_sub stimdg:correct_choice 1]
            dl_local target_choice_center [dl_choose stimdg:choice_centers [dl_pack $target_loc]]
            dl_local choice_loc_ids [dl_fromto 0 [dl_repeat $n_choices $n]]
            dl_local dist_locs [dl_select $choice_loc_ids [dl_noteq $choice_loc_ids $target_loc]]
            # pull out all non-target choice locations
            dl_local dist_choice_centers [dl_choose stimdg:choice_centers $dist_locs]

            # choose random index to select dist center randomly
            dl_local dist_id [dl_irand $n [expr $n_choices-1]]
            dl_local dist_choice_center [dl_choose $dist_choice_centers [dl_pack $dist_id]]

            # for half presentations show actual location for other half not
            set valid_per_target [expr {($n_rep/2)*[llength $rotations]}]
            dl_local use_dist [dl_replicate [dl_repeat "0 1" $valid_per_target] $n_per_set]
            dl_local cue_center [dl_replace $target_choice_center $use_dist $dist_choice_center]
            dl_set stimdg:cue_valid [dl_not $use_dist]
            dl_set stimdg:cued_choices $cue_center

            # now add left right choice options
            set lr_ecc 6.0
            set lr_scale 1.75
            dl_set stimdg:lr_choice_centers [dl_replicate [dl_llist [dl_llist [dl_flist -$lr_ecc 0] [dl_flist $lr_ecc 0]]] $n]
            dl_set stimdg:lr_choice_scale [dl_repeat $lr_scale $n]
        }

        $s add_method setup_visual_transfer { subject_id subject_set n_per_set n_rep rotations } {
            set shape_scale 1
            set noise_type none
            my setup_trials identity $subject_id $subject_set $n_per_set haptic $shape_scale $noise_type $n_rep $rotations 1
        }

        $s add_method setup_haptic_transfer { subject_id subject_set n_per_set shape_scale noise_type n_rep rotations } {
            my setup_trials identity $subject_id $subject_set $n_per_set visual $shape_scale $noise_type $n_rep $rotations 1
        }

        $s add_method setup_trials { db_prefix subject_id subject_set n_per_set trial_type shape_scale noise_type n_rep rotations joystick_side subject_handedness { use_dists 0 } } {
            # find database
            set db {}
            set p ${::ess::system_path}/$::ess::current(project)/hapticvis/db
            variable shapedb_file [file join $p shape_db]

            if { $db_prefix == "identity" } {
                # the number of sets depends on set size (4->8, 8->2, 6->3)
                set n_sets [dict get {4 4 8 2 6 3} $n_per_set]
                #                variable trialdb_file  [file join $p trial_db_${n_per_set}_${n_sets}]
                variable trialdb_file [file join $p hand_transfer_db_${n_per_set}_${n_sets}]
            } else {
                # the number of sets depends on set size (4->4, 8->2, 6->3)
                set n_sets [dict get {4 8 8 2 6 3} $n_per_set]
                variable trialdb_file [file join $p contour_db_${n_per_set}_${n_sets}]
            }


            # build our stimdg
            if { [dg_exists stimdg] } { dg_delete stimdg }
            set g [dg_create stimdg]
            dg_rename $g stimdg

            # shape coords are in shape_db file
            if {![file exists $shapedb_file]} { error "db file not found" }
            if { [dg_exists shape_db] } { dg_delete shape_db }
            dg_rename [dg_read $shapedb_file] shape_db

            # trial info in trialdb_file
            # trial_db contains columns: subject target_ids dist_ids
            if { [dg_exists trial_db] } { dg_delete trial_db }
            dg_rename [dg_read $trialdb_file] trial_db

            set row [dl_find trial_db:subject $subject_id]
            if { $row < 0 } { error "subject not in database \"$trialdb_file\"" }
            set targets trial_db:target_ids:$row:$subject_set

            if { $db_prefix == "identity" } {
                set dists trial_db:dist_ids:$row:$subject_set

                if { ![dl_exists $targets] } {
                    error "subject set does not exist"
                }
                if { $use_dists && ![dl_exists $dists] } {
                    error "subject set does not include dists"
                }
            } else {
                if { ![dl_exists $targets] } {
                    error "subject set does not exist"
                }
            }

            if { $use_dists } { set task transfer } { set task learning }

            dl_set stimdg:stimtype [dl_ilist]
            dl_set stimdg:group [dl_ilist]
            dl_set stimdg:task [dl_slist]
            dl_set stimdg:trial_type [dl_slist]
            dl_set stimdg:subject_id [dl_ilist]
            dl_set stimdg:subject_set [dl_ilist]
            dl_set stimdg:shape_set [dl_ilist]
            dl_set stimdg:shape_set_size [dl_ilist]
            dl_set stimdg:shape_id [dl_ilist]
            dl_set stimdg:shape_coord_x [dl_ilist]
            dl_set stimdg:shape_coord_y [dl_ilist]
            dl_set stimdg:shape_center_x [dl_flist]
            dl_set stimdg:shape_center_y [dl_flist]
            dl_set stimdg:shape_rot_deg_cw [dl_flist]
            dl_set stimdg:shape_scale [dl_flist]
            dl_set stimdg:shape_filled [dl_ilist]
            dl_set stimdg:shape_learned [dl_ilist]
            dl_set stimdg:noise_elements [dl_llist]
            dl_set stimdg:correct_choice [dl_ilist]
            dl_set stimdg:correct_location [dl_slist]
            dl_set stimdg:n_choices [dl_ilist]
            dl_set stimdg:choice_centers [dl_llist]
            dl_set stimdg:choice_scale [dl_flist]
            dl_set stimdg:lr_choice_centers [dl_llist]
            dl_set stimdg:lr_choice_scale [dl_flist]
            dl_set stimdg:is_cued [dl_ilist]
            dl_set stimdg:cue_valid [dl_ilist]
            dl_set stimdg:cued_choices [dl_llist]
            dl_set stimdg:feedback_type [dl_slist]
            dl_set stimdg:follow_dial [dl_ilist]
            dl_set stimdg:follow_pattern [dl_slist]
            dl_set stimdg:constrained [dl_ilist]
            dl_set stimdg:constraint_locked [dl_ilist]
            dl_set stimdg:joystick_side [dl_ilist]
            dl_set stimdg:joystick_on [dl_slist]
            dl_set stimdg:hand [dl_ilist]
            dl_set stimdg:subject_handedness [dl_ilist]
            dl_set stimdg:midline_offset [dl_ilist]


            # go into table and find info about sets/subject
            if { $use_dists } {
                set shape_ids "[dl_tcllist $targets] [dl_tcllist $dists]"
            } else {
                set shape_ids [dl_tcllist $targets]
            }

            # get coords for each shape
            dl_local shape_inds [haptic::get_shape_indices shape_db:id $shape_ids]
            dl_local coord_x [dl_choose shape_db:x $shape_inds]
            dl_local coord_y [dl_choose shape_db:y $shape_inds]

            # total number of trials
            set n_rotations [llength $rotations]
            if { $use_dists } {
                set n_targ_trials [expr {[dl_length $targets]*$n_rep*$n_rotations}]
                set n_dist_trials [expr {[dl_length $dists]*$n_rep*$n_rotations}]
            } else {
                set n_targ_trials [expr {[dl_length $targets]*$n_rep*$n_rotations}]
                set n_dist_trials 0
            }
            set n_shapes [dl_length $shape_ids]
            set n_targets [dl_length $targets]
            if { $use_dists } {
                set n_dists [dl_length $dists]
            } else {
                set n_dists 0
            }

            # close the shape_db and trial_db
            dg_delete shape_db
            dg_delete trial_db

            set n_obs [expr {$n_rep * $n_rotations * $n_shapes}]

            set is_cued 0
            set cue_valid -1
            set shape_filled 1
            set n_choices $n_targets
            set choice_ecc 5
            set choice_scale 1.5

            set shape_reps [expr {$n_rep*$n_rotations}]
            dl_local shape_id [dl_repeat [dl_ilist {*}$shape_ids] $shape_reps]

            if { $use_dists } {
                dl_local learned [dl_repeat "1 0" "$n_targ_trials $n_dist_trials"]
            } else {
                dl_local learned [dl_ones $n_obs]
            }

            if { $use_dists } {
                dl_local correct_choice [dl_combine [dl_repeat [dl_add 1 [dl_fromto 0 $n_choices]] $shape_reps] [dl_zeros [expr {$n_dists*$shape_reps}]]]
            } else {
                dl_local correct_choice [dl_repeat [dl_add 1 [dl_fromto 0 $n_choices]] $shape_reps]
            }

            if { $n_choices == 4 } {
                dl_local slots [dl_ilist 1 3 5 7]
                dl_local choice_locs [dl_slist UR UL DL DR]
            } elseif { $n_choices == 6 } {
                dl_local slots [dl_ilist 1 2 3 5 6 7]
                dl_local choice_locs [dl_slist UR U UL DL D DR]
            } else {
                dl_local slots [dl_ilist 0 1 2 3 4 5 6 7]
                dl_local choice_locs [dl_slist R UR U UL L DL D DR]
            }

            dl_local correct_locations [dl_combine [dl_repeat $choice_locs $shape_reps] [dl_repeat [dl_slist NONE] [expr {$n_dists*$shape_reps}]]]


            if { $use_dists } {
                # create a shuffled list of indices
                # moving through each unique stim/rotation before repeating
                dl_local r [dl_replicate [dl_reshape [dl_fromto 0 $shape_reps] $n_rep $n_rotations] $n_shapes]
                dl_local shuffle_ids [dl_randfill [dl_replicate [dl_llist 3] [expr {$n_shapes*$n_rep}]]]
                dl_local group_id [dl_collapse [dl_collapse [dl_choose $r $shuffle_ids]]]
            } else {
                dl_local group_id [dl_zeros $n_obs]
            }

            dl_local choice_angles [dl_mult [expr (2*$::pi)/8.] $slots]

            dl_local choice_center_x [dl_mult [dl_cos $choice_angles] $choice_ecc]
            dl_local choice_center_y [dl_mult [dl_sin $choice_angles] $choice_ecc]
            dl_local choice_centers [dl_llist [dl_transpose [dl_llist $choice_center_x $choice_center_y]]]

            if { $noise_type == "none"} {
                dl_local noise_elements [dl_replicate [dl_llist [dl_llist]] $n_obs]
            } elseif { $noise_type == "circles"} {
                set nelements 15
                set njprop 0.05; # jitter proportion
                set minradius 0.1;
                set total_elements [expr {${n_obs}*$nelements}]
                dl_local xs [dl_sub [dl_urand $total_elements] 0.5]
                dl_local ys [dl_sub [dl_urand $total_elements] 0.5]
                dl_local rs [dl_add $minradius [dl_mult [dl_urand $total_elements] $njprop]]
                dl_local noise_elements [dl_reshape [dl_transpose [dl_llist $xs $ys $rs]] $n_obs $nelements]
            }

            dl_set stimdg:stimtype [dl_fromto 0 $n_obs]
            dl_set stimdg:group $group_id
            dl_set stimdg:task [dl_repeat [dl_slist $task] $n_obs]
            dl_set stimdg:trial_type [dl_repeat [dl_slist $trial_type] $n_obs]
            dl_set stimdg:subject_id [dl_repeat $subject_id $n_obs]
            dl_set stimdg:subject_set [dl_repeat $subject_set $n_obs]

            dl_set stimdg:shape_set [dl_repeat [dl_ilist -1] $n_obs]
            dl_set stimdg:shape_set_size [dl_repeat $n_targets $n_obs]
            dl_set stimdg:shape_id $shape_id
            dl_set stimdg:shape_coord_x [dl_repeat $coord_x $shape_reps]
            dl_set stimdg:shape_coord_y [dl_repeat $coord_y $shape_reps]
            dl_set stimdg:shape_center_x [dl_zeros $n_obs.]
            dl_set stimdg:shape_center_y [dl_zeros $n_obs.]
            dl_set stimdg:shape_rot_deg_cw [dl_replicate [dl_flist {*}$rotations] [expr $n_rep*$n_shapes]]
            dl_set stimdg:shape_scale [dl_repeat $shape_scale $n_obs]
            dl_set stimdg:shape_filled [dl_repeat $shape_filled $n_obs]
            dl_set stimdg:shape_learned $learned
            dl_set stimdg:noise_elements $noise_elements
            dl_set stimdg:correct_choice $correct_choice
            dl_set stimdg:correct_location $correct_locations
            dl_set stimdg:n_choices [dl_repeat $n_choices $n_obs]
            dl_set stimdg:choice_centers [dl_repeat $choice_centers $n_obs]
            dl_set stimdg:choice_scale [dl_repeat $choice_scale $n_obs]
            dl_set stimdg:lr_choice_centers [dl_repeat [dl_llist [dl_llist]] $n_obs]
            dl_set stimdg:lr_choice_scale [dl_zeros $n_obs.]
            dl_set stimdg:is_cued [dl_repeat $is_cued $n_obs]
            dl_set stimdg:cue_valid [dl_repeat [dl_ilist $cue_valid] $n_obs]
            dl_set stimdg:cued_choices [dl_repeat [dl_llist [dl_llist]] $n_obs]
            dl_set stimdg:feedback_type [dl_repeat [dl_slist color] $n_obs]

            if { $noise_type == "none" } {
                dl_set stimdg:follow_dial [dl_zeros $n_obs]
            } else {
                dl_set stimdg:follow_dial [dl_ones $n_obs]
            }
            dl_set stimdg:follow_pattern [dl_replicate [dl_slist 0] $n_obs]
            dl_set stimdg:constrained [dl_zeros $n_obs]
            dl_set stimdg:constraint_locked [dl_zeros $n_obs]

            dl_set stimdg:joystick_side [dl_repeat $joystick_side $n_obs]
            dl_set stimdg:joystick_on [dl_choose [dl_slist left right] stimdg:joystick_side]
            dl_set stimdg:hand [dl_not stimdg:joystick_side]

            dl_set stimdg:subject_handedness [dl_repeat $subject_handedness $n_obs]

            if { $joystick_side == 0} {
                dl_set stimdg:midline_offset [dl_repeat -25 $n_obs]
            } else {
                dl_set stimdg:midline_offset [dl_repeat 25 $n_obs]
            }

            dl_set stimdg:remaining [dl_ones $n_obs]
            return $g
        }
    }
}
