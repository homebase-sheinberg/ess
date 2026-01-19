#
# planko_extract.tcl - Trial extraction for planko system
#
# This is the system-level extractor for planko experiments.
# Protocol-specific extractors (e.g., bounce_extract.tcl) can augment this.
#

namespace eval planko {
    
    #
    # Extract trials from a planko datafile
    #
    # Arguments:
    #   f    - df::File object (already opened)
    #   args - optional arguments
    #
    # Returns:
    #   Rectangular dg with one row per valid trial
    #
    proc extract_trials {f args} {
        set g [$f group]
        set trials [dg_create]
        
        # Parse options
        array set opts {
            include_invalid 0
        }
        foreach {key val} $args {
            set opts([string trimleft $key -]) $val
        }
        
        #
        # Determine valid trials
        # Valid = ENDOBS complete (1) and response was made (not NONE/-1)
        # In planko, a trial is valid if it has:
        #   - ENDOBS subtype == 1 (COMPLETE)
        #   - RESP event exists and subtype != NONE (i.e., a response was made)
        # Note: Unlike emcalib, planko doesn't use ENDTRIAL for validity
        #       The abort state puts ENDTRIAL INCORRECT, but normal trials
        #       just end with ENDOBS COMPLETE
        #
        dl_local endobs_subtypes [$f event_subtype_values ENDOBS]
        
        # Check for RESP events - valid trials have a response (subtype 1 or 2, not NONE)
        dl_local resp_mask [$f select_evt RESP]
        dl_local has_resp [dl_sums $resp_mask]
        
        # Get RESP subtypes to check for actual responses vs NONE
        # RESP subtypes: 1=LEFT, 2=RIGHT, NONE=no response
        dl_local resp_subtypes_nested [$f event_subtypes $resp_mask]
        
        # Valid response: subtype > 0 (LEFT=1 or RIGHT=2)
        dl_local resp_ok [dl_sums [dl_gt $resp_subtypes_nested 0]]
        
        # Valid trials: endobs==COMPLETE(1) and has valid response
        dl_local valid [dl_and \
            [dl_eq $endobs_subtypes 1] \
            $has_resp \
            $resp_ok]
        
        if {!$opts(include_invalid)} {
            set n_total [dl_length $valid]
            set n_valid [dl_sum $valid]
            puts "planko::extract_trials: $n_valid valid of $n_total obs periods"
        } else {
            dl_local valid [dl_ones [dl_length $endobs_subtypes]]
        }
        
        #
        # Extract trial indices
        #
        dl_set $trials:obsid [dl_indices $valid]
        
        #
        # Extract event-based data for valid trials
        #
        
        # Trial outcome (ENDOBS subtype: 0=INCOMPLETE, 1=COMPLETE, 2=BREAK, etc.)
        dl_set $trials:outcome [dl_select [$f event_subtype_values ENDOBS] $valid]
        
        # Trial duration (ENDOBS time)
        dl_set $trials:duration [dl_select [$f event_time_values ENDOBS] $valid]
        
        #
        # STIMTYPE event - contains stimdg index
        #
        dl_local stimtype [$f event_param_values STIMTYPE]
        if {$stimtype ne ""} {
            dl_local stimtype_valid [dl_select $stimtype $valid]
            dl_set $trials:stimtype $stimtype_valid
        }
        
        #
        # PATTERN events - stimulus timing
        #
        dl_local pattern_on_times [$f event_time_values PATTERN ON]
        if {$pattern_on_times ne ""} {
            dl_set $trials:stimon [dl_select $pattern_on_times $valid]
        }
        
        dl_local pattern_off_times [$f event_time_values PATTERN OFF]
        if {$pattern_off_times ne ""} {
            # There may be multiple OFF events per trial - take first
            dl_local pattern_off_nested [dl_select [$f event_times [$f select_evt PATTERN OFF]] $valid]
            dl_set $trials:stimoff [dl_unpack [dl_select $pattern_off_nested [dl_llist [dl_ilist 0]]]]
        }
        
        #
        # RESP event - response and timing
        #
        dl_local resp_times [$f event_time_values RESP]
        if {$resp_times ne ""} {
            dl_set $trials:resp_time [dl_select $resp_times $valid]
        }
        
        dl_local resp_subtypes [$f event_subtype_values RESP]
        if {$resp_subtypes ne ""} {
            # Response: 1=LEFT, 2=RIGHT -> convert to 0=LEFT, 1=RIGHT
            dl_set $trials:response [dl_sub [dl_select $resp_subtypes $valid] 1]
        }
        
        #
        # Compute reaction time (resp_time - stimon)
        #
        if {[dl_exists $trials:resp_time] && [dl_exists $trials:stimon]} {
            dl_set $trials:rt [dl_sub $trials:resp_time $trials:stimon]
        }
        
        #
        # FEEDBACK event - contains response and correctness
        # FEEDBACK ON params: resp correct
        #
        dl_local feedback_mask [$f select_evt FEEDBACK ON]
        if {$feedback_mask ne "" && [dl_sum [dl_sums $feedback_mask]] > 0} {
            dl_local feedback_params_valid [dl_select [$f event_params $feedback_mask] $valid]
            dl_local feedback_params [dl_unpack [dl_deepUnpack $feedback_params_valid]]
            
            # Params are: resp, correct pairs
            if {[dl_length $feedback_params] > 0} {
                dl_local reformatted [dl_transpose [dl_reshape $feedback_params - 2]]
                dl_set $trials:feedback_resp $reformatted:0
                dl_set $trials:correct $reformatted:1
            }
        }
        
        # If no FEEDBACK event, compute status from response vs side
        if {![dl_exists $trials:correct] && [dl_exists $trials:response]} {
            if {[dl_exists $g:<stimdg>side] && [dl_exists $trials:stimtype]} {
                dl_set $trials:side [dl_choose $g:<stimdg>side $trials:stimtype]
                dl_set $trials:correct [dl_eq $trials:response $trials:side]
            }
        }
        
        #
        # REWARD event - if present
        #
        dl_local reward_times [$f event_time_values REWARD]
        if {$reward_times ne ""} {
            dl_set $trials:reward_time [dl_select $reward_times $valid]
        }
        
        dl_local reward_params [$f event_param_values REWARD]
        if {$reward_params ne ""} {
            dl_set $trials:reward_ul [dl_select $reward_params $valid]
        }
        
        #
        # Extract stimulus parameters from stimdg
        #
        if {[dl_exists $trials:stimtype]} {
            set stimtype_valid $trials:stimtype
            
            # Copy all stimdg columns, indexed by stimtype
            set all_cols [dg_tclListnames $g]
            set stimdg_cols [lsearch -inline -all -glob $all_cols "<stimdg>*"]
            
            foreach col $stimdg_cols {
                # Extract column name without <stimdg> prefix
                set short_name [string range $col 8 end]
                
                # Skip 'remaining' which is a runtime tracking variable
                if {$short_name eq "remaining"} continue
                
                dl_set $trials:$short_name [dl_choose $g:$col $stimtype_valid]
            }
        }
        
        #
        # Extract eye movement data if present
        #
        if {[dl_exists $g:ems]} {
            dl_set $trials:ems [dl_select $g:ems $valid]
        }
        
        # Collect raw eye tracking data streams into a dict for em:: processing
        set em_streams [dict create]
        foreach {ds_path dict_key} {
            em/pupil pupil
            em/p1 p1
            em/p4 p4
            em/pupil_r pupil_r
            em/time time
            em/blink blink
            em/frame_id frame_id
        } {
            if {[dl_exists $g:<ds>$ds_path]} {
                dict set em_streams $dict_key [dl_select $g:<ds>$ds_path $valid]
            }
        }
        
        # Process eye movement data using em:: utilities
        if {[dict size $em_streams] > 0} {
            em::process_raw_streams $trials $em_streams
        }
        
        # Processed eye position if available
        if {[dl_exists $g:<ds>eyetracking/raw]} {
            dl_set $trials:eye_raw [dl_select $g:<ds>eyetracking/raw $valid]
        }
        
        #
        # Extract touch data if present
        #
        if {[dl_exists $g:<ds>touch/x]} {
            dl_set $trials:touch_x [dl_select $g:<ds>touch/x $valid]
            dl_set $trials:touch_y [dl_select $g:<ds>touch/y $valid]
        }
        if {[dl_exists $g:<ds>touch/time]} {
            dl_set $trials:touch_time [dl_select $g:<ds>touch/time $valid]
        }
        
        return $trials
    }
}
