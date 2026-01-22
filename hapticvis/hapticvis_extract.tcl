#
# hapticvis_extract.tcl - Trial extraction for hapticvis system
#
# This is the system-level extractor for haptic visual shape paradigm experiments.
# Protocol-specific extractors (e.g., transfer_extract.tcl) can augment this.
#

namespace eval hapticvis {
    
    #
    # Extract trials from a hapticvis datafile
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
        # ENDTRIAL subtypes: CORRECT=0, INCORRECT=1, ABORT=2
        # No-response trials go through no_response state which puts ENDTRIAL ABORT
        #
        dl_local endobs_subtypes [$f event_subtype_values ENDOBS]
        dl_local endtrial_mask [$f select_evt ENDTRIAL]
        
        # Check that ENDTRIAL exists for each obs period
        dl_local has_endtrial [dl_anys $endtrial_mask]
        
        # Get ENDTRIAL subtypes
        dl_local endtrial_subtypes_nested [$f event_subtypes $endtrial_mask]
        
        # Get subtype IDs for CORRECT and INCORRECT
        # ABORT is typically subtype 2, CORRECT=0, INCORRECT=1
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
            puts "hapticvis::extract_trials: $n_valid valid of $n_total obs periods ($n_noresponse no-response/aborted)"
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
        #
        dl_local stimtype [$f event_param_values STIMTYPE]
        if {$stimtype ne ""} {
            dl_local stimtype_valid [dl_select $stimtype $valid]
            dl_set $trials:stimtype $stimtype_valid
        }
        
        #
        # STIMULUS events - overall stimulus timing
        #
        dl_local stim_on_times [$f event_time_values STIMULUS ON]
        if {$stim_on_times ne ""} {
            dl_set $trials:stim_on [dl_select $stim_on_times $valid]
        }
        
        dl_local stim_off_times [$f event_time_values STIMULUS OFF]
        if {$stim_off_times ne ""} {
            dl_set $trials:stim_off [dl_select $stim_off_times $valid]
        }
        
        #
        # SAMPLE events - sample stimulus timing (the shape to match)
        #
        dl_local sample_on_times [$f event_time_values SAMPLE ON]
        if {$sample_on_times ne ""} {
            dl_set $trials:sample_on [dl_select $sample_on_times $valid]
        }
        
        dl_local sample_off_times [$f event_time_values SAMPLE OFF]
        if {$sample_off_times ne ""} {
            dl_set $trials:sample_off [dl_select $sample_off_times $valid]
        }
        
        #
        # CHOICES events - choice stimuli timing
        # Note: Not all variants emit CHOICES (e.g., visual_recognition uses left/right old/new)
        #
        if {[$f has_event_type CHOICES]} {
            dl_local choices_on_times [$f event_time_values CHOICES ON]
            if {$choices_on_times ne ""} {
                dl_set $trials:choices_on [dl_select $choices_on_times $valid]
            }
            
            dl_local choices_off_times [$f event_time_values CHOICES OFF]
            if {$choices_off_times ne ""} {
                dl_set $trials:choices_off [dl_select $choices_off_times $valid]
            }
        }
        
        #
        # CUE events - cue timing (only for cued variants)
        #
        if {[$f has_event_type CUE]} {
            dl_local cue_on_times [$f event_time_values CUE ON]
            if {$cue_on_times ne ""} {
                dl_set $trials:cue_on [dl_select $cue_on_times $valid]
            }
            
            dl_local cue_off_times [$f event_time_values CUE OFF]
            if {$cue_off_times ne ""} {
                dl_set $trials:cue_off [dl_select $cue_off_times $valid]
            }
        }
        
        #
        # DECIDE events - decision/selection events during response
        # These track joystick position changes before final selection
        # We store both the final decision (flat) and all decisions (nested) for change-of-mind analysis
        # Note: Not all variants emit DECIDE events
        #
        if {[$f has_event_type DECIDE]} {
            dl_local decide_mask [$f select_evt DECIDE SELECT]
            if {$decide_mask ne "" && [dl_any $decide_mask]} {
                # Get all decide times and params (nested by trial)
                dl_local decide_times [$f event_times $decide_mask]
                dl_local decide_params [$f event_params $decide_mask]
                
                # Store all decisions (nested - for change of mind analysis)
                dl_set $trials:decide_all_times [dl_select $decide_times $valid]
                dl_set $trials:decide_all_params [dl_select $decide_params $valid]
                
                # Count number of decisions per trial (for change-of-mind detection)
                dl_set $trials:n_decides [dl_select [dl_lengths $decide_times] $valid]
                
                # Extract final decision (last one per trial - flat)
                # Use dl_lastPos to get mask for last element in each nested list
                dl_local last_mask [dl_lastPos $decide_times]
                dl_local final_times [dl_unpack [dl_select $decide_times $last_mask]]
                dl_local final_params [dl_unpack [dl_select $decide_params $last_mask]]
                dl_set $trials:decide_time [dl_select $final_times $valid]
                dl_set $trials:decide_param [dl_select [dl_unpack $final_params] $valid]
            }
        }
        
        #
        # RESP event - response and timing
        # RESP subtype indicates which choice was selected (slot number)
        #
        dl_local resp_times [$f event_time_values RESP]
        if {$resp_times ne ""} {
            dl_set $trials:resp_time [dl_select $resp_times $valid]
        }
        
        dl_local resp_subtypes [$f event_subtype_values RESP]
        if {$resp_subtypes ne ""} {
            # response: which choice slot was selected
            dl_set $trials:response [dl_select $resp_subtypes $valid]
        }
        
        #
        # Compute reaction time (resp_time - sample_on) in ms
        # Note: hapticvis computes rt from sample_on, not choices_on
        #
        if {[dl_exists $trials:resp_time] && [dl_exists $trials:sample_on]} {
            dl_set $trials:rt [dl_sub $trials:resp_time $trials:sample_on]
        }
        
        #
        # ENDTRIAL event - trial result
        # CORRECT=0, INCORRECT=1, ABORT=2
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
        # Use -1 for reward_time when no reward, 0 for reward_ul
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
        # Extract touch data if present (touchscreen responses)
        #
        if {[dl_exists $g:<ds>touch/x]} {
            dl_set $trials:touch_x [dl_select $g:<ds>touch/x $valid]
            dl_set $trials:touch_y [dl_select $g:<ds>touch/y $valid]
        }
        if {[dl_exists $g:<ds>touch/time]} {
            dl_set $trials:touch_time [dl_select $g:<ds>touch/time $valid]
        }
        
        #
        # Extract haptic/grasp sensor data if present
        # These are logged via dservLoggerAddMatch in transfer protocol
        #
        if {[dl_exists $g:<ds>grasp/sensor0/vals]} {
            dl_set $trials:grasp_vals [dl_select $g:<ds>grasp/sensor0/vals $valid]
        }
        if {[dl_exists $g:<ds>grasp/sensor0/touched]} {
            dl_set $trials:grasp_touched [dl_select $g:<ds>grasp/sensor0/touched $valid]
        }
        if {[dl_exists $g:<ds>grasp/dial_angle]} {
            dl_set $trials:dial_angle [dl_select $g:<ds>grasp/dial_angle $valid]
        }
        if {[dl_exists $g:<ds>grasp/available]} {
            dl_set $trials:grasp_available [dl_select $g:<ds>grasp/available $valid]
        }
        
        #
        # Extract joystick data if present
        #
        if {[dl_exists $g:<ds>ess/joystick/value]} {
            dl_set $trials:joystick_value [dl_select $g:<ds>ess/joystick/value $valid]
        }
        if {[dl_exists $g:<ds>ess/joystick/button]} {
            dl_set $trials:joystick_button [dl_select $g:<ds>ess/joystick/button $valid]
        }
        if {[dl_exists $g:<ds>ess/joystick/position]} {
            dl_set $trials:joystick_position [dl_select $g:<ds>ess/joystick/position $valid]
        }
        
        return $trials
    }
}
