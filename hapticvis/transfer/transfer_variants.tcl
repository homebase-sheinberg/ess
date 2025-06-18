#
# VARIANT
#   hapticvis transfer
#
# DESCRIPTION
#   variants for hapticvis transfer task
#

# This is the right one to edit Ayan
# Currently only supports 4, 6, 8 choices properly
#   The "correct_choice" is numbered 1-n_choices
#    but the centers differ depending on the number of choices so
#
package require haptic

namespace eval hapticvis::transfer {

    # state system parameters for visual 
    set visual_params {
	interblock_time 500
	pre_stim_time 100
	sample_duration 3000
	choice_delay 0
	sample_delay 500
	choice_duration 30000
	stim_duration 30000
	post_response_time 500
    }

    # state system parameters for haptic 
    set haptic_params {
	interblock_time 500
	pre_stim_time 100
	sample_delay 0
	sample_duration 5000
	choice_duration 30000
	choice_delay 0
	stim_duration 30000
	post_response_time 500
    }

    # state system parameters for visual cued
    set visual_cued_params {
	interblock_time 500
	pre_stim_time 100
	cue_delay 500
	cue_duration 6000
	sample_delay 1500
	sample_duration 5000
	choice_duration 30000
	choice_delay 0
	stim_duration 30000
	post_response_time 500
    }
    
    set subject_ids [dl_tcllist [dl_fromto 0 30]]
    set subject_sets [dl_tcllist [dl_fromto 0 5]]

    variable variants {
        visual_learn {
            description "learn visual objects"
            loader_proc setup_visual
            loader_options {
              subject_id { $subject_ids }
              subject_set { $subject_sets }
              n_per_set { 6 4 }
              shape_scale { 3 4 5 6 }
              noise_type { circles none }
              n_rep { 6 2 4 8 10 20 }
              rotations {
                  {three {60 180 300}} {single {180}} 
                }
            }
	    params [list $visual_params]
        }
        haptic_learn {
            description "learn haptic objects"
            loader_proc setup_haptic
            loader_options {
              subject_id { $subject_ids }
              subject_set { $subject_sets }
              n_per_set { 6 4 }
              n_rep { 6 2 4 8 10 20 }
		rotations {
                  {three {60 180 300}} {single {180}} 
                }
            }
	    params [list $haptic_params]
        }
        visual_cued {
            description "respond to cued visual objects"
            loader_proc setup_visual_cued
            loader_options {
		subject_id { $subject_ids }
		subject_set { $subject_sets }
		n_per_set { 4 }
		shape_scale { 3 4 5 6 }
		noise_type { none }
		n_rep { 6 2 4 8 10 20 }
		rotations {
		    {three {60 180 300}} {single {180}} 
		}
            }
	    params [list $visual_cued_params]
        }
        visual_to_haptic {
            description "learn visual transfer to haptic"
            loader_proc setup_visual_transfer
            loader_options {
              subject_id { $subject_ids }
              subject_set { $subject_sets }
              n_per_set { 6 }
              n_rep { 3 6 2 4 8 10 20 }
              rotations {
                  {three {60 180 300}} {single {180}} 
                }
            }
	    params [list $haptic_params]
        }
        haptic_to_visual {
            description "learn haptic transfer to visual"
            loader_proc setup_haptic_transfer
            loader_options {
              subject_id { $subject_ids }
              subject_set { $subject_sets }
              n_per_set { 6 }
              shape_scale { 3 4 5 6 }
              noise_type { circles none }
              n_rep { 3 6 2 4 8 10 20 }
              rotations {
                  {three {60 180 300}} {single {180}} 
                }
            }
	    params [list $visual_params]
        }
    }

    # substitute variables in variant description above
    set variants [subst $variants]
}
