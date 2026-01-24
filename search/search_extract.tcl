#
# search_extract.tcl - Trial extraction for search system
#
# This is the system-level extractor for visual search experiments.
# Protocol-specific extractors (e.g., circles_extract.tcl) can augment this.
#

namespace eval search {
    
    #
    # Extract trials from a search datafile
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
        # Valid = ENDOBS complete (1) and ENDTRIAL exists with subtype CORRECT or INCORRECT
        # ENDTRIAL subtypes: CORRECT, INCORRECT, ABORT (no response)
        #
        dl_local endobs_subtypes [$f event_subtype_values ENDOBS]
        dl_local endtrial_mask [$f select_evt ENDTRIAL]
        
        # Check that ENDTRIAL exists for each obs period
        dl_local has_endtrial [dl_anys $endtrial_mask]
        
        # Get ENDTRIAL subtypes
        dl_local endtrial_subtypes_nested [$f event_subtypes $endtrial_mask]
        
        # Get subtype IDs for CORRECT and INCORRECT
        set correct_id [$f subtype_id ENDTRIAL CORRECT]
        set incorrect_id [$f subtype_id ENDTRIAL INCORRECT]
        
        # Valid trials: endtrial is CORRECT or INCORRECT (not ABORT)
        dl_local endtrial_is_correct [dl_anys [dl_eq $endtrial_subtypes_nested $correct_id]]
        dl_local endtrial_is_incorrect [dl_anys [dl_eq $endtrial_subtypes_nested $incorrect_id]]
        dl_local endtrial_ok [dl_or $endtrial_is_correct $endtrial_is_incorrect]
        
        dl_local valid [dl_and \
            [dl_eq $endobs_subtypes 1] \
            $has_endtrial \
            $endtrial_ok]
        
        if {!$opts(include_invalid)} {
            set n_total [dl_length $valid]
            set n_valid [dl_sum $valid]
            set n_noresponse [expr {$n_total - $n_valid}]
            puts "search::extract_trials: $n_valid valid of $n_total obs periods ($n_noresponse no-response/aborted)"
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
        dl_set $trials:outcome [dl_select [$f event_subtype_values ENDOBS] $valid]
        
        # Trial duration (ENDOBS time in ms)
        dl_set $trials:duration [dl_select [$f event_time_values ENDOBS] $valid]
        
        #
        # STIMTYPE event - contains stimdg index
        # evt_put STIMTYPE STIMID $stimon_time $stimtype
        #
        dl_local stimtype [$f event_param_values STIMTYPE STIMID]
        if {$stimtype ne ""} {
            dl_local stimtype_valid [dl_select $stimtype $valid]
            dl_set $trials:stimtype $stimtype_valid
        }
        
        #
        # PATTERN events - stimulus presentation timing
        # evt_put PATTERN ON/OFF $time
        #
        dl_local pattern_on_times [$f event_time_values PATTERN ON]
        if {$pattern_on_times ne ""} {
            dl_set $trials:stim_on [dl_select $pattern_on_times $valid]
        }
        
        dl_local pattern_off_times [$f event_time_values PATTERN OFF]
        if {$pattern_off_times ne ""} {
            dl_set $trials:stim_off [dl_select $pattern_off_times $valid]
        }
        
        #
        # RESP event - response timing
        # evt_put RESP 1 $resp_time (on response)
        # evt_put RESP NONE $time (on no response)
        #
        dl_local resp_times [$f event_time_values RESP 1]
        if {$resp_times ne ""} {
            dl_set $trials:resp_time [dl_select $resp_times $valid]
        }
        
        # Check for no-response trials
        if {[$f has_event_type RESP]} {
            dl_local resp_none_mask [$f select_evt RESP NONE]
            if {$resp_none_mask ne "" && [dl_any $resp_none_mask]} {
                dl_local has_response [dl_not [dl_anys $resp_none_mask]]
                dl_set $trials:responded [dl_select $has_response $valid]
            }
        }
        
        #
        # Compute reaction time (resp_time - stim_on) in ms
        #
        if {[dl_exists $trials:resp_time] && [dl_exists $trials:stim_on]} {
            dl_set $trials:rt [dl_div [dl_sub $trials:resp_time $trials:stim_on] 1000.0]
        }
        
        #
        # ENDTRIAL event - trial result
        # CORRECT, INCORRECT, ABORT
        #
        dl_local endtrial_subtypes [$f event_subtype_values ENDTRIAL]
        if {$endtrial_subtypes ne ""} {
            dl_local endtrial_valid [dl_select $endtrial_subtypes $valid]
            # correct: 1 if CORRECT, 0 if INCORRECT
            dl_set $trials:correct [dl_eq $endtrial_valid $correct_id]
        }
        
        # Add status as alias for correct (historical convention)
        if {[dl_exists $trials:correct]} {
            dl_set $trials:status $trials:correct
        }
        
        #
        # REWARD event - sparse (only on correct trials)
        # evt_put REWARD MICROLITERS [now] [expr {int($juice_ml*1000)}]
        #
        dl_local reward_mask [$f select_evt REWARD MICROLITERS]
        if {$reward_mask ne "" && [dl_any $reward_mask]} {
            dl_local has_reward [dl_anys $reward_mask]
            dl_local no_reward [dl_not $has_reward]
            
            # Reward time: -1 for no reward
            dl_local reward_times [$f event_times $reward_mask]
            dl_local reward_times [dl_unpack [dl_replace $reward_times $no_reward [dl_llist [dl_ilist -1]]]]
            dl_set $trials:reward_time [dl_select $reward_times $valid]
            
            # Reward amount: 0 for no reward (params are depth 2)
            dl_local reward_params [$f event_params $reward_mask]
            dl_local reward_params [dl_unpack [dl_unpack [dl_replace $reward_params $no_reward [dl_llist [dl_llist [dl_ilist 0]]]]]]
            dl_set $trials:reward_ul [dl_select $reward_params $valid]
            
            # Rewarded flag
            dl_set $trials:rewarded [dl_select $has_reward $valid]
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
        
        # Process eye movement data using em:: utilities if available
        if {[dict size $em_streams] > 0 && [namespace exists ::em]} {
            em::process_raw_streams $trials $em_streams
        }
        
        # Processed eye position if available
        if {[dl_exists $g:<ds>eyetracking/raw]} {
            dl_set $trials:eye_raw [dl_select $g:<ds>eyetracking/raw $valid]
        }
        
        #
        # Extract touch data if present
        # All touches during trial
        #
        if {[dl_exists $g:<ds>touch/x]} {
            dl_set $trials:touch_x [dl_select $g:<ds>touch/x $valid]
            dl_set $trials:touch_y [dl_select $g:<ds>touch/y $valid]
        }
        if {[dl_exists $g:<ds>touch/time]} {
            dl_set $trials:touch_time [dl_select $g:<ds>touch/time $valid]
        }
        
        #
        # Extract touch press/release events logged via ess::touch_evt_put
        #
        if {[dl_exists $g:<ds>ess/touch_press]} {
            dl_local touch_press [dl_select $g:<ds>ess/touch_press $valid]
            dl_set $trials:touch_press $touch_press
            
            # Extract final touch (last touch in each trial)
            # touch_press is {x y} format
            dl_local has_touch [dl_gt [dl_lengths $touch_press] 0]
            if {[dl_any $has_touch]} {
                # Get the last touch for each trial using dl_lindex -1
                dl_set $trials:final_touch_x [dl_lindex $touch_press 0]
                dl_set $trials:final_touch_y [dl_lindex $touch_press 1]
            }
        }
        
        if {[dl_exists $g:<ds>ess/touch_release]} {
            dl_set $trials:touch_release [dl_select $g:<ds>ess/touch_release $valid]
        }
        
        return $trials
    }
}
