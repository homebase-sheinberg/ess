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
		
		# For combo presets with multiple restitution values, we need to generate separate worlds
		# for each restitution to ensure trajectory consistency
		if { [llength $ball_restitution] > 1 } {
		    # Multiple restitution values - generate separate worlds for each
		    set worlds_per_restitution [expr $n_rep / [llength $ball_restitution]]
		    set remaining_worlds [expr $n_rep % [llength $ball_restitution]]
		    
		    for { set rest_idx 0 } { $rest_idx < [llength $ball_restitution] } { incr rest_idx } {
			set current_rest [lindex $ball_restitution $rest_idx]
			set current_color [lindex $ball_color $rest_idx]
			
			# Calculate how many worlds for this restitution value
			set n_worlds $worlds_per_restitution
			if { $rest_idx < $remaining_worlds } { incr n_worlds }
			
			if { $n_worlds > 0 } {
			    # Generate worlds with this specific restitution
			    set p "nplanks $nplank_val ball_restitution $current_rest $params"
			    set g [planko::generate_worlds $n_worlds $p]
			    
			    # Set ball_color for these trials (all the same color for this restitution group)
			    set color_string [join $current_color " "]
			    dl_set $g:ball_color [dl_repeat [dl_slist $color_string] $n_worlds]
			    
			    # Add wrong_catcher_alpha for this group
			    dl_set $g:wrong_catcher_alpha \
				[dl_repeat [dl_flist $wrong_catcher_alpha] $n_worlds]
			    
			    # Append to combined datagram
			    if { $combined_dg != "" } {
				dg_append $combined_dg $g
				dg_delete $g
			    } else {
				set combined_dg $g
			    }
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

