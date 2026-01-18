#
# emcalib_extract.tcl - Trial extraction for emcalib system
#
# This is the system-level extractor for eye movement calibration experiments.
# Protocol-specific extractors (e.g., 9point_extract.tcl) can augment this.
#

namespace eval emcalib {
    
    #
    # Extract trials from an emcalib datafile
    #
    # Arguments:
    #   f    - df::File object (already opened)
    #   args - optional arguments (e.g., -raw for uncalibrated eye data)
    #
    # Returns:
    #   Rectangular dg with one row per valid trial
    #
    proc extract_trials {f args} {
        set g [$f group]
        set trials [dg_create]
        
        # Parse options
        array set opts {
            raw 0
            include_invalid 0
        }
        foreach {key val} $args {
            set opts([string trimleft $key -]) $val
        }
        
        #
        # Determine valid trials
        # Valid = ENDOBS occurred and ENDTRIAL subtype < ABORT (2)
        #
        dl_local endobs_mask [$f select_evt ENDOBS]
        dl_local endobs_subtypes [$f event_subtypes $endobs_mask]
        
        dl_local endtrial_mask [$f select_evt ENDTRIAL]
        dl_local endtrial_subtypes [$f event_subtypes $endtrial_mask]
        
        # ENDOBS COMPLETE = 1, ENDTRIAL ABORT = 2
        # Valid trials: has endobs, endobs is complete (1), endtrial < 2
        dl_local valid [dl_and \
            [dl_sums $endobs_mask] \
            [dl_eq [dl_unpack $endobs_subtypes] 1] \
            [dl_lt [dl_unpack $endtrial_subtypes] 2]]
        
        if {!$opts(include_invalid)} {
            # Filter to valid trials only
            set n_total [dl_length $valid]
            set n_valid [dl_sum $valid]
            puts "emcalib::extract_trials: $n_valid valid of $n_total obs periods"
        } else {
            dl_local valid [dl_ones [dl_length $g:e_types]]
        }
        
        #
        # Extract trial indices
        #
        dl_set $trials:obsid [dl_indices $valid]
        
        #
        # Extract event-based data for valid trials
        #
        
        # Trial outcome (ENDOBS subtype: 0=INCOMPLETE, 1=COMPLETE, 2=BREAK, etc.)
        dl_set $trials:outcome [dl_select [dl_unpack $endobs_subtypes] $valid]
        
        # Trial duration (ENDOBS time)
        dl_local endobs_times [$f event_times $endobs_mask]
        dl_set $trials:duration [dl_select [dl_unpack $endobs_times] $valid]
        
        # Fixation acquired time (FIXATE IN)
        dl_local fixate_mask [$f select_evt FIXATE IN]
        if {[dl_sum [dl_sums $fixate_mask]] > 0} {
            dl_local fixate_times [$f event_times $fixate_mask]
            dl_set $trials:fixate [dl_select [dl_unpack $fixate_times] $valid]
        }
        
        # Refixation time (FIXATE REFIXATE) - if present
        dl_local refix_mask [$f select_evt FIXATE REFIXATE]
        if {[dl_sum [dl_sums $refix_mask]] > 0} {
            dl_local refix_times [$f event_times $refix_mask]
            dl_set $trials:refixate [dl_select [dl_unpack $refix_times] $valid]
        }
        
        #
        # Extract eye position means from EMPARAMS CALIB events
        # These are computed by the sampler during the experiment
        #
        dl_local calib_mask [$f select_evt EMPARAMS CALIB]
        if {[dl_sum [dl_sums $calib_mask]] > 0} {
            dl_local calib_params [$f event_params $calib_mask]
            # Params are "{x, y}" strings - need to parse
            dl_local calib_valid [dl_select $calib_params $valid]
            
            # Extract x and y from params
            # Each param is a string like "-3.84, -5.12"
            set eye_x [dl_flist]
            set eye_y [dl_flist]
            foreach params [dl_tcllist [dl_unpack $calib_valid]] {
                # Parse the comma-separated values
                set vals [split $params ", "]
                if {[llength $vals] >= 2} {
                    dl_append $eye_x [lindex $vals 0]
                    dl_append $eye_y [lindex $vals 1]
                } else {
                    dl_append $eye_x 0.0
                    dl_append $eye_y 0.0
                }
            }
            dl_set $trials:eye_mean_x $eye_x
            dl_set $trials:eye_mean_y $eye_y
        }
        
        #
        # Extract stimulus parameters (stimdg columns)
        #
        if {[dl_exists $g:<stimdg>stimtype]} {
            # Get stimtype indices for valid trials
            dl_local stimtype [dl_select $g:<stimdg>stimtype $valid]
            dl_set $trials:stimtype $stimtype
            
            # Calibration target positions
            if {[dl_exists $g:<stimdg>jump_targ_x]} {
                dl_set $trials:calib_x [dl_choose $g:<stimdg>jump_targ_x $stimtype]
                dl_set $trials:calib_y [dl_choose $g:<stimdg>jump_targ_y $stimtype]
            }
            
            # Fixation target
            if {[dl_exists $g:<stimdg>fix_targ_x]} {
                dl_set $trials:fix_x [dl_choose $g:<stimdg>fix_targ_x $stimtype]
                dl_set $trials:fix_y [dl_choose $g:<stimdg>fix_targ_y $stimtype]
            }
        }
        
        #
        # Extract eye movement data
        #
        if {[dl_exists $g:ems]} {
            dl_set $trials:ems [dl_select $g:ems $valid]
        }
        
        # Raw eye tracking data if present
        if {[dl_exists $g:<ds>eyetracking/raw]} {
            dl_set $trials:eye_raw [dl_select $g:<ds>eyetracking/raw $valid]
        }
        
        #
        # Add metadata to group
        #
        # Store as group attributes or separate - for now just return the dg
        
        return $trials
    }
}
