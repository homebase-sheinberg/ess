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
	$s add_method basic_planko { nr nplanks wrong_catcher_alpha ball_restitution params } {
	    set n_rep $nr
	    
	    if { [dg_exists stimdg] } { dg_delete stimdg }

	    # Calculate total number of observations
	    # Each element in nplanks gets n_rep repetitions
	    set n_obs [expr [llength $nplanks] * $n_rep]
	    
	    set maxx [expr $screen_halfx]
	    set maxy [expr $screen_halfy]

	    # Create empty datagram to collect all worlds
	    set combined_dg ""
	    
	    # For each nplanks value
	    foreach nplank_val $nplanks {
		
		# Generate worlds for this nplanks group
		# Use first ball_restitution value as default for world generation
		set first_ball_rest [lindex $ball_restitution 0]
		set p "nplanks $nplank_val ball_restitution $first_ball_rest $params"
		set g [planko::generate_worlds $n_rep $p]
		
		# Create mixed ball_restitution values for this group
		# If ball_restitution has multiple values, cycle through them
		if { [llength $ball_restitution] > 1 } {
		    # Multiple values - create cycling pattern
		    set rest_list {}
		    for { set i 0 } { $i < $n_rep } { incr i } {
			set idx [expr $i % [llength $ball_restitution]]
			lappend rest_list [lindex $ball_restitution $idx]
		    }
		    dl_set $g:ball_restitution [dl_flist {*}$rest_list]
		} else {
		    # Single value - just repeat it
		    dl_set $g:ball_restitution [dl_repeat [dl_flist $ball_restitution] $n_rep]
		}
		
		# Add wrong_catcher_alpha for this group
		dl_set $g:wrong_catcher_alpha \
		    [dl_repeat [dl_flist $wrong_catcher_alpha] $n_rep]
		
		# Append to combined datagram
		if { $combined_dg != "" && [dl_length $combined_dg:stimtype] > 0 } {
		    dg_append $combined_dg $g
		    dg_delete $g
		} else {
		    # First group - use this datagram as the combined one
		    set combined_dg $g
		}
	    }

	    # rename id column to stimtype and add remaining column
	    dg_rename $combined_dg:id stimtype 
	    dl_set $combined_dg:remaining [dl_ones [dl_length $combined_dg:stimtype]]
	    
	    dg_rename $combined_dg stimdg
	    return $combined_dg
	}
    }
}

