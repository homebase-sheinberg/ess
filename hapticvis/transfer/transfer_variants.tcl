#
# VARIANTS
#   hapticvis identify
#
# DESCRIPTION
#   variant dictionary for visual and haptic identity learning
#

#
# Currently only supports 4, 6, 8 choices properly
#   The "correct_choice" is numbered 1-n_choices
#    but the centers differ depending on the number of choices so
#
package require haptic

namespace eval hapticvis::identify {

    # system parameters used by visual variants
    set visual_params {
        interblock_time 500
        pre_stim_time 100
        sample_duration 1500
        choice_delay 0
        sample_delay 500
        choice_duration 30000
        stim_duration 30000
        post_response_time 500
    }

    # system parameters used by haptic variants
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

    set subject_ids [dl_tcllist [dl_fromto 0 36]]
    set subject_sets [dl_tcllist [dl_fromto 0 5]]

    variable variants {
        visual {
            description "learn visual objects"
            loader_proc setup_visual
            loader_options {
                subject_id { $subject_ids }
                subject_set { $subject_sets }
                n_per_set { 6 }
                shape_scale { 3 4 5 6 }
                noise_type { none circles }
                n_rep { 2 4 6 8 10 20 }
                rotations {
                    {three {60 180 300}} {single {180}}
                }
            }
            params [list $visual_params]
        }
        haptic {
            description "learn haptic objects"
            loader_proc setup_haptic
            loader_options {
                subject_id { $subject_ids }
                subject_set { $subject_sets }
                n_per_set { 6 }
                n_rep { 2 4 6 8 10 20 }
                rotations {
                    {three {60 180 300}} {single {180}}
                }
            }
            params [list $haptic_params]
        }
        haptic_follow_dial {
            description "learn haptic using dial"
            loader_proc setup_haptic_follow_dial
            loader_options {
                subject_id { $subject_ids }
                subject_set { $subject_sets }
                n_per_set { 4 }
                n_rep { 10 8 }
                rotations {
                    {three {60 180 300}} {single {180}}
                }
            }
            params [list $haptic_params]
        }
        haptic_follow_pattern {
            description "learn haptic with passive following"
            loader_proc setup_haptic_follow_pattern
            loader_options {
                subject_id { $subject_ids }
                subject_set { $subject_sets }
                n_per_set { 4 }
                n_rep { 10 8 }
                rotations {
                    {three {60 180 300}} {single {180}}
                }
            }
            params [list $haptic_params]
        }
        haptic_constrained_locked {
            description "learn haptic with constraint (locked)"
            loader_proc setup_haptic_constrained_locked
            loader_options {
                subject_id { $subject_ids }
                subject_set { $subject_sets }
                n_per_set { 4 }
                n_rep { 10 8 }
                rotations {
                    {three {60 180 300}} {single {180} }
                }
            }
            params [list $haptic_params]
        }
        haptic_constrained_unlocked {
            description "learn haptic with constraint (unlocked)"
            loader_proc setup_haptic_constrained_unlocked
            loader_options {
                subject_id { $subject_ids }
                subject_set { $subject_sets }
                n_per_set { 4 }
                n_rep { 10 8 }
                rotations {
                    {three {60 180 300}} {single {180}}
                }
            }
            params [list $haptic_params]
        }
    }

    # substitute variables in variant description above
    set variants [subst $variants]
}
