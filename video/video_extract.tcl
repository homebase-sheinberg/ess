#
# video_extract.tcl - Trial extraction for video system
#
# This is the system-level extractor for video watching experiments.
# Protocol-specific extractors (e.g., play-or-skip_extract.tcl) can augment this.
#
# The video system presents video thumbnails and allows subjects to:
#   - PLAY (response=1): watch the full video
#   - SKIP (response=2): skip to next trial
#   - NONE (response=0): no response (timeout, if enabled)
#

namespace eval video {
    
    #
    # Extract trials from a video datafile
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
        # Valid = ENDOBS complete (1) and ENDTRIAL exists with subtype CORRECT
        # In video system:
        #   - ENDTRIAL CORRECT = valid response (PLAY or SKIP)
        #   - ENDTRIAL ABORT = no response (timeout)
        #   - RESP subtype: 1=PLAY, 2=SKIP, NONE=no response
        #
        # Note: event_subtype_values is safe here because ENDOBS exists for every
        # obs period by definition
        dl_local endobs_subtypes [$f event_subtype_values ENDOBS]
        dl_local endtrial_mask [$f select_evt ENDTRIAL]
        
        # Check that ENDTRIAL exists for each obs period
        dl_local has_endtrial [dl_anys $endtrial_mask]
        
        # Get ENDTRIAL subtypes (nested, one per obs period)
        dl_local endtrial_subtypes_nested [$f event_subtypes $endtrial_mask]
        
        # Get subtype ID for CORRECT
        set correct_id [$f subtype_id ENDTRIAL CORRECT]
        
        # Valid trials: endtrial is CORRECT (not ABORT)
        dl_local endtrial_ok [dl_anys [dl_eq $endtrial_subtypes_nested $correct_id]]
        
        # Valid trials: endobs==COMPLETE(1) and has endtrial and endtrial==CORRECT
        dl_local valid [dl_and \
            [dl_eq $endobs_subtypes 1] \
            $has_endtrial \
            $endtrial_ok]
        
        if {!$opts(include_invalid)} {
            set n_total [dl_length $valid]
            set n_valid [dl_sum $valid]
            set n_noresponse [expr {$n_total - $n_valid}]
            puts "video::extract_trials: $n_valid valid of $n_total obs periods ($n_noresponse no-response/timeout)"
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
        # ENDOBS is guaranteed to exist for every obs period
        dl_set $trials:outcome [dl_choose [$f event_subtype_values ENDOBS] $valid_indices]
        
        # Trial duration (ENDOBS time)
        # ENDOBS is guaranteed to exist for every obs period
        dl_set $trials:duration [dl_choose [$f event_time_values ENDOBS] $valid_indices]
        
        #
        # STIMTYPE event - contains stimdg index
        # STIMTYPE is emitted in stim_on, should exist for all trials that reach that state
        #
        dl_local stimtype [$f event_param_values STIMTYPE STIMID]
        if {$stimtype ne ""} {
            dl_local stimtype_valid [dl_choose $stimtype $valid_indices]
            dl_set $trials:stimtype $stimtype_valid
        }
        
        #
        # PATTERN events - stimulus timing
        # PATTERN ON = stimulus on (thumbnail shown)
        # PATTERN 2 = play started (full video)
        # Use safe methods - events may not exist if trial aborts early
        #
        dl_local pattern_on_times [$f event_times_valid $valid PATTERN ON]
        if {$pattern_on_times ne ""} {
            dl_set $trials:stim_on $pattern_on_times
        }
        
        # PATTERN subtype 2 = play started (only on PLAY responses)
        # This is sparse - only exists when subject chose to play
        dl_local play_mask [$f select_evt PATTERN 2]
        if {$play_mask ne "" && [dl_any $play_mask]} {
            dl_local has_play [dl_anys $play_mask]
            dl_local no_play [dl_not $has_play]
            
            # Play start time: -1 for no play (skip trials)
            dl_local play_times [$f event_times $play_mask]
            dl_local play_times [dl_unpack [dl_replace $play_times $no_play [dl_llist [dl_ilist -1]]]]
            dl_set $trials:play_start [dl_choose $play_times $valid_indices]
            
            # Flag for whether video was played
            dl_set $trials:played [dl_choose $has_play $valid_indices]
        }
        
        #
        # RESP event - response and timing
        # RESP subtype: 1=PLAY, 2=SKIP
        # For valid trials (by definition), RESP exists with subtype > 0
        # Use safe methods for consistency
        #
        dl_local resp_times [$f event_times_valid $valid RESP]
        if {$resp_times ne ""} {
            dl_set $trials:resp_time $resp_times
        }
        
        dl_local resp_subtypes [$f event_subtypes_valid $valid RESP]
        if {$resp_subtypes ne ""} {
            # response: 1=PLAY, 2=SKIP
            dl_set $trials:response $resp_subtypes
            
            # Create boolean flags for convenience
            dl_set $trials:chose_play [dl_eq $resp_subtypes 1]
            dl_set $trials:chose_skip [dl_eq $resp_subtypes 2]
        }
        
        #
        # Compute reaction time (resp_time - stim_on)
        #
        if {[dl_exists $trials:resp_time] && [dl_exists $trials:stim_on]} {
            dl_set $trials:rt [dl_sub $trials:resp_time $trials:stim_on]
        }
        
        #
        # REWARD event - sparse (only on some trials, depends on protocol)
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
        # Extract touch data if present
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
        # Extract touch press/release events logged via ess::touch_evt_put
        # Per-obs-period data
        #
        if {[dl_exists $g:<ds>ess/touch_press]} {
            dl_set $trials:touch_press [dl_choose $g:<ds>ess/touch_press $valid_indices]
        }
        if {[dl_exists $g:<ds>ess/touch_release]} {
            dl_set $trials:touch_release [dl_choose $g:<ds>ess/touch_release $valid_indices]
        }
        
        return $trials
    }
}
