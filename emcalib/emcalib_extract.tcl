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
        # Valid = ENDOBS complete (1) and ENDTRIAL exists and subtype < ABORT (2)
        # Handle case where last trial may be incomplete (missing events)
        #
        # Note: event_subtype_values is safe here because ENDOBS exists for every
        # obs period by definition (it's what ends the obs period)
        dl_local endobs_subtypes [$f event_subtype_values ENDOBS]
        dl_local endtrial_mask [$f select_evt ENDTRIAL]
        
        # Check that ENDTRIAL exists for each obs period
        dl_local has_endtrial [dl_anys $endtrial_mask]
        
        # Get ENDTRIAL subtypes (nested, one per obs period)
        dl_local endtrial_subtypes_nested [$f event_subtypes $endtrial_mask]
        
        # Valid trials: endobs==1, has endtrial, endtrial < 2
        dl_local endtrial_ok [dl_anys [dl_lt $endtrial_subtypes_nested 2]]
        
        dl_local valid [dl_and \
            [dl_eq $endobs_subtypes 1] \
            $has_endtrial \
            $endtrial_ok]
        
        if {!$opts(include_invalid)} {
            set n_total [dl_length $valid]
            set n_valid [dl_sum $valid]
            puts "emcalib::extract_trials: $n_valid valid of $n_total obs periods"
        } else {
            dl_local valid [dl_ones [dl_length $endobs_subtypes]]
        }
        
        set n_trials [dl_sum $valid]
        
        #
        # Extract trial indices
        #
        dl_set $trials:obsid [dl_indices $valid]
        
        #
        # Add standard metadata columns (trialid, date, time, filename, system, protocol, variant, subject)
        #
        df::add_metadata_columns $trials $f $n_trials
        
        #
        # Extract event-based data for valid trials
        #
        
        # Trial outcome (ENDOBS subtype: 0=INCOMPLETE, 1=COMPLETE, 2=BREAK, etc.)
        # ENDOBS is guaranteed to exist for every obs period, so direct select is safe
        dl_local valid_indices [dl_indices $valid]
        dl_set $trials:outcome [dl_choose [$f event_subtype_values ENDOBS] $valid_indices]
        
        # Trial duration (ENDOBS time)
        # ENDOBS is guaranteed to exist for every obs period, so direct select is safe
        dl_set $trials:duration [dl_choose [$f event_time_values ENDOBS] $valid_indices]
        
        # Fixation acquired time (FIXATE IN)
        # Use safe method - event may not exist in all obs periods
        dl_local fixate_times [$f event_times_valid $valid FIXATE IN]
        if {$fixate_times ne ""} {
            dl_set $trials:fixate $fixate_times
        }
        
        # Refixation time (FIXATE REFIXATE) - if present
        # Use safe method - event may not exist in all obs periods
        dl_local refix_times [$f event_times_valid $valid FIXATE REFIXATE]
        if {$refix_times ne ""} {
            dl_set $trials:refixate $refix_times
        }
        
        #
        # Extract eye position means from EMPARAMS CALIB events
        # These are computed by the sampler during the experiment
        # Params come as "x, y" pairs that need to be separated
        #
        dl_local calib_mask [$f select_evt EMPARAMS CALIB]
        if {$calib_mask ne "" && [dl_any $calib_mask]} {
            # Select for valid trials first using dl_choose, then unpack
            dl_local calib_params_nested [$f event_params $calib_mask]
            dl_local calib_params_valid [dl_choose $calib_params_nested $valid_indices]
            dl_local calib_params [dl_unpack [dl_deepUnpack $calib_params_valid]]
            
            # Params are flattened x,y pairs - reshape and transpose to separate
            dl_local reformatted [dl_transpose [dl_reshape $calib_params - 2]]
            dl_set $trials:eye_mean_x $reformatted:0
            dl_set $trials:eye_mean_y $reformatted:1
        }
        
        #
        # Extract stimulus parameters via STIMTYPE event
        # The STIMTYPE event param contains the index into stimdg
        # STIMTYPE is emitted in start_obs, so it should exist for all obs periods
        #
        dl_local stimtype [$f event_param_values STIMTYPE]
        if {$stimtype ne ""} {
            dl_local stimtype_valid [dl_choose $stimtype $valid_indices]
            dl_set $trials:stimtype $stimtype_valid
            
            set g [$f group]
            
            # Calibration target positions
            if {[dl_exists $g:<stimdg>jump_targ_x]} {
                dl_set $trials:calib_x [dl_choose $g:<stimdg>jump_targ_x $stimtype_valid]
                dl_set $trials:calib_y [dl_choose $g:<stimdg>jump_targ_y $stimtype_valid]
            }
            
            # Fixation target
            if {[dl_exists $g:<stimdg>fix_targ_x]} {
                dl_set $trials:fix_x [dl_choose $g:<stimdg>fix_targ_x $stimtype_valid]
                dl_set $trials:fix_y [dl_choose $g:<stimdg>fix_targ_y $stimtype_valid]
            }
        }
        
        #
        # Extract eye movement data
        #
        if {[dl_exists $g:ems]} {
            dl_set $trials:ems [dl_choose $g:ems $valid_indices]
        }
        
        # Raw eye tracking data if present
        if {[dl_exists $g:<ds>eyetracking/raw]} {
            dl_set $trials:eye_raw [dl_choose $g:<ds>eyetracking/raw $valid_indices]
        }
        
        #
        # Add metadata to group
        #
        # Store as group attributes or separate - for now just return the dg
        
        return $trials
    }
}
