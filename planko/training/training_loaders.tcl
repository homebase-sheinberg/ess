#
# LOADERS
#   planko training loaders
#
# DESCRIPTION
#   loader functions for planko::training
#

namespace eval planko::training {
    package require planko
    
    proc loaders_init { s } {
	$s add_method basic_planko { nr nplanks wrong_catcher_alpha ball_preset params } {
	    set n_rep $nr
	    
	    if { [dg_exists stimdg] } { dg_delete stimdg }

	    # Extract ball_restitution and ball_color from the selected preset
	    # ball_preset is a dictionary like: { ball_restitution {0.2 0.5} ball_color {{0 1 1} {1 0.5 0}} }
	    array set preset_params $ball_preset
	    set ball_restitution $preset_params(ball_restitution)
	    set ball_color $preset_params(ball_color)

	    # Calculate total number of observations
	    # Each element in nplanks gets n_rep repetitions
	    set n_obs [expr [llength $nplanks] * $n_rep]
	    
	    set maxx [expr $screen_halfx]
	    set maxy [expr $screen_halfy]

	    # Create empty datagram to collect all worlds
	    set combined_dg ""
	    
	    # For each nplanks value
	    foreach nplank_val $nplanks {
		
		# For combo presets with multiple restitution values, generate worlds trial by trial
		# to ensure proper alternation of restitution and color
		if { [llength $ball_restitution] > 1 } {
		    # Multiple restitution values - generate worlds alternating trial by trial
		    for { set trial 0 } { $trial < $n_rep } { incr trial } {
			# Alternate between restitution/color combinations
			set rest_idx [expr $trial % [llength $ball_restitution]]
			set current_rest [lindex $ball_restitution $rest_idx]
			set current_color [lindex $ball_color $rest_idx]
			
			# Generate single world with this specific restitution
			set p "nplanks $nplank_val ball_restitution $current_rest $params"
			set g [planko::generate_worlds 1 $p]
			
			# Set ball_color for this trial
			set color_string [join $current_color " "]
			dl_set $g:ball_color [dl_slist $color_string]
			
			# Add wrong_catcher_alpha for this trial
			dl_set $g:wrong_catcher_alpha [dl_flist $wrong_catcher_alpha]
			
			# Append to combined datagram
			if { $combined_dg != "" } {
			    dg_append $combined_dg $g
			    dg_delete $g
			} else {
			    set combined_dg $g
			}
		    }
		} else {
		    # Single restitution value - generate as before
		    set ball_rest [lindex $ball_restitution 0]
		    set p "nplanks $nplank_val ball_restitution $ball_rest $params"
		    set g [planko::generate_worlds $n_rep $p]
		    
		    # Single color - store as complete RGB triplet string for each trial
		    set color_string [join $ball_color " "]
		    dl_set $g:ball_color [dl_repeat [dl_slist $color_string] $n_rep]
		    
		    # Add wrong_catcher_alpha for this group
		    dl_set $g:wrong_catcher_alpha \
			[dl_repeat [dl_flist $wrong_catcher_alpha] $n_rep]
		    
		    # Append to combined datagram
		    if { $combined_dg != "" } {
			dg_append $combined_dg $g
			dg_delete $g
		    } else {
			set combined_dg $g
		    }
		}
	    }

	    # rename id column to stimtype and add remaining column
	    if { $combined_dg != "" } {
		dg_rename $combined_dg:id stimtype 
		
		# Fix stimtype values - ensure they are sequential (0, 1, 2, ...)
		set n_trials [dl_length $combined_dg:stimtype]
		dl_set $combined_dg:stimtype [dl_fromto 0 [expr $n_trials - 1]]
		
		dl_set $combined_dg:remaining [dl_ones [dl_length $combined_dg:stimtype]]
		
		# Remove the unused ball_restitution column (we use restitution instead)
		if { [dl_exists $combined_dg:ball_restitution] } {
		    dl_delete $combined_dg:ball_restitution
		}
		
		dg_rename $combined_dg stimdg
		return $combined_dg
	    } else {
		error "No datagram was generated"
	    }
	}
    }
}

