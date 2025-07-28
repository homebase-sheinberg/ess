#
# VARIANTS
#   match_to_sample shapematch
#
# DESCRIPTION
#   variant dictionary
#

namespace eval match_to_sample::shapematch {
    variable variants {
		single_pair     {
			description "match with single pair of shapes"
			loader_proc setup_trials
			loader_options {
				n_rep { 50 100 200 400 800}
				targ_scale 3
				shape_choices single_pair
				show_feedback {0 1}
				options_side {fixed random}
				shape_params {}			
			}
		}
		single_pair_arbitrary {
			description "match with single pair of arbitrarily associated shapes"
			loader_proc setup_trials
			loader_options {
				n_rep { 50 100 200 400 800}
				targ_scale 3
				shape_choices single_pair_arbitrary
				show_feedback {0 1}
				options_side {fixed random}
				shape_params {}
			}
		}
    }
}

