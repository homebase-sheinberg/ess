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
        # Note: event_subtype_values is safe here because ENDOBS exists for every
        # obs period by definition
        dl_local endobs_subtypes [$f event_subtype_values ENDOBS]
        dl_local endtrial_mask [$f select_evt ENDTRIAL]
        
        # Check that ENDTRIAL exists for each obs period
        dl_local has_endtrial [dl_anys $endtrial_mask]
        
        # Get ENDTRIAL subtypes (nested, one per obs period)
        dl_local endtrial_subtypes_nested [$f event_subtypes $endtrial_mask]
        
        # Get subtype IDs for CORRECT and INCORRECT
        # ABORT is typically subtype 2, CORRECT=0, INCORRECT=1
        set correct_id [$f subtype_id ENDTRIAL CORRECT]
        set incorrect_id [$f subtype_id ENDTRIAL INCORRECT]
        
        # Valid trials: endtrial is CORRECT or INCORRECT (not ABORT)
        dl_local endtrial_is_correct [dl_anys [dl_eq $endtrial_subtypes_nested $correct_id]]
        dl_local endtrial_is_incorrect [dl_anys [dl_eq $endtrial_subtypes_nested $incorrect_id]]
        dl_local endtrial_ok [dl_or $endtrial_is_correct $endtrial_is_incorrect]
        
        dl_local valid [dl_and  [dl_eq $endobs_subtypes 1]  $has_endtrial  $endtrial_ok]
        
        if {!$opts(include_invalid)} {
            set n_total [dl_length $valid]
            set n_valid [dl_sum $valid]
            set n_noresponse [expr {$n_total - $n_valid}]
            puts "hapticvis::extract_trials: $n_valid valid of $n_total obs periods ($n_noresponse no-response/aborted)"
        } else {
            dl_local valid [dl_ones [dl_length $endobs_subtypes]]
        }
        
        set n_trials [dl_sum $valid]
        
        # Compute valid indices once for use throughout
        dl_local valid_indices [dl_indices $valid]
        
        #
        # Extract trial indices
        #
        dl_set $trials:obsid $valid_indices
        
        #
        # Add standard metadata columns (trialid, date, time, filename, system, protocol, variant, subject)
        #
        df::add_metadata_columns $trials $f $n_trials
        
        #
        # Extract event-based data for valid trials
        #
        
        # Trial outcome (ENDOBS subtype: 0=INCOMPLETE, 1=COMPLETE, 2=BREAK, etc.)
        # ENDOBS exists for every obs period, but use sparse for consistency
        dl_set $trials:outcome [$f event_subtype_sparse $valid_indices ENDOBS {} -1]
        
        # Trial duration (ENDOBS time in ms)
        dl_set $trials:duration [$f event_time_sparse $valid_indices ENDOBS {} -1]
        
        #
        # STIMTYPE event - contains stimdg index
        # STIMTYPE is emitted early in each trial, but may be missing on
        # interrupted obs periods. Use sparse method to maintain index alignment.
        #
        dl_local stimtype_valid [$f event_param_sparse $valid_indices STIMTYPE {} -1]
        dl_set $trials:stimtype $stimtype_valid
        
        #
        # STIMULUS events - overall stimulus timing
        # STIMULUS ON should exist for all valid trials (emitted in stim_on state)
        # STIMULUS OFF should exist (emitted in stim_off state for valid trials)
        # Use sparse methods for safety
        #
        dl_set $trials:stim_on [$f event_time_sparse $valid_indices STIMULUS ON -1]
        dl_set $trials:stim_off [$f event_time_sparse $valid_indices STIMULUS OFF -1]
        
        #
        # SAMPLE events - sample stimulus timing (the shape to match)
        # SAMPLE ON/OFF may not fire if trial aborts before sample_delay expires
        # or if subject responds before sample_duration expires (OFF)
        # Use sparse methods to handle missing events
        #
        dl_set $trials:sample_on [$f event_time_sparse $valid_indices SAMPLE ON -1]
        dl_set $trials:sample_off [$f event_time_sparse $valid_indices SAMPLE OFF -1]
        
        #
        # CHOICES events - choice stimuli timing
        # CHOICES ON may not fire if subject responds before choice_delay
        # CHOICES OFF typically doesn't fire - subject responds before choice_duration expires
        # Use sparse methods to handle missing events
        #
        if {[$f has_event_type CHOICES]} {
            dl_set $trials:choices_on [$f event_time_sparse $valid_indices CHOICES ON -1]
            dl_set $trials:choices_off [$f event_time_sparse $valid_indices CHOICES OFF -1]
        }
        
        #
        # CUE events - cue timing (only for cued variants)
        # CUE ON may not fire if subject responds before cue_delay
        # CUE OFF rarely fires - subject typically responds before cue_duration expires
        # Use sparse methods to handle missing events
        #
        if {[$f has_event_type CUE]} {
            dl_set $trials:cue_on [$f event_time_sparse $valid_indices CUE ON -1]
            dl_set $trials:cue_off [$f event_time_sparse $valid_indices CUE OFF -1]
        }
        
        #
        # DECIDE events - decision/selection events during response
        # These track joystick position changes before final selection
        # We store both the final decision (flat) and all decisions (nested) for change-of-mind analysis
        # Note: Not all variants emit DECIDE events
        #
        # This section handles nested data - we select valid trials first, then process
        #
        if {[$f has_event_type DECIDE]} {
            dl_local decide_mask [$f select_evt DECIDE SELECT]
            if {$decide_mask ne "" && [dl_any $decide_mask]} {
                # Get all decide times and params (nested by trial)
                dl_local decide_times [$f event_times $decide_mask]
                dl_local decide_params [$f event_params $decide_mask]
                
                # Count decisions per obs period BEFORE filling empties
                # Then select valid trials
                dl_set $trials:n_decides [dl_choose [dl_lengths $decide_times] $valid_indices]
                
                # Fill empty sublists (trials with no DECIDE) before selecting valid
                dl_local has_decide [dl_anys $decide_mask]
                dl_local no_decide [dl_not $has_decide]
                dl_local decide_times [dl_replace $decide_times $no_decide [dl_llist [dl_ilist -1]]]
                dl_local decide_params [dl_replace $decide_params $no_decide [dl_llist [dl_llist [dl_ilist -1]]]]
                
                # Select valid trials, keeping nested structure
                dl_local decide_times_valid [dl_choose $decide_times $valid_indices]
                dl_local decide_params_valid [dl_choose $decide_params $valid_indices]
                
                # Store all decisions (nested - for change of mind analysis)
                dl_set $trials:decide_all_times $decide_times_valid
                dl_set $trials:decide_all_params $decide_params_valid
                
                # Extract final decision (last one per trial - flat)
                # dl_lastPos works on filled sublists (single fill element for empty trials)
                dl_local last_mask [dl_lastPos $decide_times_valid]
                dl_local final_times [dl_unpack [dl_select $decide_times_valid $last_mask]]
                dl_local final_params [dl_unpack [dl_select $decide_params_valid $last_mask]]
                dl_set $trials:decide_time $final_times
                dl_set $trials:decide_param [dl_unpack $final_params]
            }
        }
        
        #
        # RESP event - response and timing
        # RESP subtype indicates which choice was selected (slot number)
        # Should exist for all valid (CORRECT/INCORRECT) trials, but use sparse for safety
        #
        dl_set $trials:resp_time [$f event_time_sparse $valid_indices RESP {} -1]
        dl_set $trials:response [$f event_subtype_sparse $valid_indices RESP {} -1]
        
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
        # ENDTRIAL is guaranteed for valid trials, but obs periods with missing
        # ENDTRIAL (e.g., from stop/start) cause event_subtype_values to return
        # a shorter list, breaking index alignment. Use sparse method for safety.
        #
        dl_set $trials:correct [dl_eq [$f event_subtype_sparse $valid_indices ENDTRIAL {} -1] $correct_id]
        
        # Add status as alias for correct (historical convention)
        if {[dl_exists $trials:correct]} {
            dl_set $trials:status $trials:correct
        }
        
        #
        # REWARD event - sparse (only on correct trials)
        # Use -1 for reward_time when no reward, 0 for reward_ul
        # Handle missing rewards by inserting placeholder values before selection
        #
        dl_local reward_mask [$f select_evt REWARD MICROLITERS]
        if {$reward_mask ne "" && [dl_any $reward_mask]} {
            dl_local has_reward [dl_anys $reward_mask]
            dl_local no_reward [dl_not $has_reward]
            
            # Reward time: -1 for no reward
            dl_local reward_times [$f event_times $reward_mask]
            dl_local reward_times [dl_unpack [dl_replace $reward_times $no_reward [dl_llist [dl_ilist -1]]]]
            dl_set $trials:reward_time [dl_choose $reward_times $valid_indices]
            
            # Reward amount: 0 for no reward (params are depth 2)
            dl_local reward_params [$f event_params $reward_mask]
            dl_local reward_params [dl_unpack [dl_unpack [dl_replace $reward_params $no_reward [dl_llist [dl_llist [dl_ilist 0]]]]]]
            dl_set $trials:reward_ul [dl_choose $reward_params $valid_indices]
            
            # Rewarded flag
            dl_set $trials:rewarded [dl_choose $has_reward $valid_indices]
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
        # These are per-obs-period data, use dl_choose with valid_indices
        #
        if {[dl_exists $g:ems]} {
            dl_set $trials:ems [dl_choose $g:ems $valid_indices]
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
                dict set em_streams $dict_key [dl_choose $g:<ds>$ds_path $valid_indices]
            }
        }
        
        # Process eye movement data using em:: utilities if available
        if {[dict size $em_streams] > 0 && [namespace exists ::em]} {
            em::process_raw_streams $trials $em_streams
        }
        
        # Processed eye position if available
        if {[dl_exists $g:<ds>eyetracking/raw]} {
            dl_set $trials:eye_raw [dl_choose $g:<ds>eyetracking/raw $valid_indices]
        }
        
        #
        # Extract touch data if present (touchscreen responses)
        # Per-obs-period data
        #
        if {[dl_exists $g:<ds>touch/x]} {
            dl_set $trials:touch_x [dl_choose $g:<ds>touch/x $valid_indices]
            dl_set $trials:touch_y [dl_choose $g:<ds>touch/y $valid_indices]
        }
        if {[dl_exists $g:<ds>touch/time]} {
            dl_set $trials:touch_time [dl_choose $g:<ds>touch/time $valid_indices]
        }
        
        #
        # Extract haptic/grasp sensor data if present
        # These are logged via dservLoggerAddMatch in transfer protocol
        # Per-obs-period data
        #
        if {[dl_exists $g:<ds>grasp/sensor0/vals]} {
            dl_set $trials:grasp_vals [dl_choose $g:<ds>grasp/sensor0/vals $valid_indices]
        }
        if {[dl_exists $g:<ds>grasp/sensor0/touched]} {
            dl_set $trials:grasp_touched [dl_choose $g:<ds>grasp/sensor0/touched $valid_indices]
        }
        if {[dl_exists $g:<ds>grasp/dial_angle]} {
            dl_set $trials:dial_angle [dl_choose $g:<ds>grasp/dial_angle $valid_indices]
        }
        if {[dl_exists $g:<ds>grasp/available]} {
            dl_set $trials:grasp_available [dl_choose $g:<ds>grasp/available $valid_indices]
        }
        
        #
        # Extract joystick data if present
        # Per-obs-period data
        #
        if {[dl_exists $g:<ds>ess/joystick/value]} {
            dl_set $trials:joystick_value [dl_choose $g:<ds>ess/joystick/value $valid_indices]
        }
        if {[dl_exists $g:<ds>ess/joystick/button]} {
            dl_set $trials:joystick_button [dl_choose $g:<ds>ess/joystick/button $valid_indices]
        }
        if {[dl_exists $g:<ds>ess/joystick/position]} {
            dl_set $trials:joystick_position [dl_choose $g:<ds>ess/joystick/position $valid_indices]
        }
        
        return $trials
    }
}
