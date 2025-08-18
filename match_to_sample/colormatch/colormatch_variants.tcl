#
# VARIANTS
#   match_to_sample colormatch
#
# DESCRIPTION
#   variant dictionary
#

namespace eval match_to_sample::colormatch {
    variable variants {
        noDistractor {
            description "no distractor"
            loader_proc setup_transparent_trials
            loader_options {
                n_rep { 50 100 200 400 800}
                targ_scale 1.5
                transparency { {off 0.0} {0.05 0.05} {0.1 0.1} {0.15 0.15} {0.175 0.175} {0.2 0.2} {0.25 0.25} {0.3 0.3} {0.4 0.4} {0.5 0.5} {mixed {0.0 0.2}} {full 1.0} }
            }
        }
        easy {
            description "easy comparisons"
            loader_proc setup_trials
            loader_options {
                n_rep { 50 100 200 400 800}
                targ_scale 1.5
                color_choices easy
            }
        }
        random {
            description "random comparisons"
            loader_proc setup_trials
            loader_options {
                n_rep { 50 100 }
                targ_scale 1.5
                color_choices random
            }
        }
        redgreen {
            description "red/green MTS"
            loader_proc setup_trials
            loader_options {
                n_rep { 50 100 }
                targ_scale 1.5
                color_choices redgreen
            }
        }
    }
}





