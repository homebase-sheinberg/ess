#
# PROTOCOL
#   planko training
#
# DESCRIPTION
#   Train planko 
#

namespace eval planko::training {
    
    variable params_defaults          { n_rep 50 }

    proc protocol_init { s } {
	$s set_protocol [namespace tail [namespace current]]
	
	$s add_param rmt_host          $::ess::rmt_host   stim ipaddr
	$s add_param juice_ml          .6      variable float
	$s add_param use_buttons        0      variable int
	$s add_param left_button       24      variable int
	$s add_param right_button      25      variable int
	
	$s add_variable touch_count        0
	$s add_variable touch_last         0
	$s add_variable touch_x            
	$s add_variable touch_y            

	$s set_protocol_init_callback {
	    ::ess::init

	    # initialize juicer
	    ::ess::juicer_init
	    
	    # open connection to rmt and upload ${protocol}_stim.tcl
	    my configure_stim $rmt_host

	    # initialize touch processor
	    ::ess::touch_init

	    # listen for planko/complete event
	    dservAddExactMatch planko/complete
	    dpointSetScript planko/complete ess::do_update
	    
	    soundReset
	    soundSetVoice 81 0    0
	    soundSetVoice 57 17   1
	    soundSetVoice 60 0    2
	    soundSetVoice 42 0    3
	    soundSetVoice 21 0    4
	    soundSetVoice 8  0    5
	    soundSetVoice 113 100 6
	    foreach i "0 1 2 3 4 5 6" { soundVolume 127 $i }
	}
	    
	$s set_protocol_deinit_callback {
	    rmtClose
	}
	
	$s set_reset_callback {
	    dl_set stimdg:remaining [dl_ones [dl_length stimdg:stimtype]]
	    set obs_count 0	    
	    rmtSend reset
	}
	
	$s set_start_callback {
	    set first_time 1
	}
	
	$s set_quit_callback {
	    ::ess::touch_region_off 0
	    ::ess::touch_region_off 1
	    rmtSend clearscreen
	    ::ess::end_obs QUIT
	}
	
	$s set_end_callback {
	    ::ess::evt_put SYSTEM_STATE STOPPED [now]
	}
	
	$s set_file_open_callback {
	    print "opened datafile $filename"
	}
	
	$s set_file_close_callback {
	    set name [file tail [file root $filename]]
	    #	    set path [string map {-rpi4- {}} [info hostname]]
	    set path {}
	    set output_name [file join /tmp $path $name.csv]
	    #	    set converted [save_data_as_csv $filename $output_name]
	    #	    print "saved data to $output_name"
	    print "closed $name"
	}
	

	######################################################################
	#                         Utility Methods                            #
	######################################################################
	
	$s add_method start_obs_reset {} {
	    set buttons_changed 0
	}
	
	$s add_method n_obs {} { return [dl_length stimdg:stimtype] }

	$s add_method nexttrial {} {
	    if { [dl_sum stimdg:remaining] } {
		dl_local left_to_show \
		    [dl_select stimdg:stimtype [dl_gt stimdg:remaining 0]]
		set cur_id [dl_pickone $left_to_show]
		set stimtype [dl_get stimdg:stimtype $cur_id]

		set side [dl_get stimdg:side $cur_id]

		foreach v "lcatcher_x lcatcher_y rcatcher_x rcatcher_y" {
		    set $v [dl_get stimdg:$v $cur_id]
		}

		::ess::touch_region_off 0
		::ess::touch_region_off 1
		::ess::touch_reset
		::ess::touch_win_set 0 $lcatcher_x $lcatcher_y 2 0
		::ess::touch_win_set 1 $rcatcher_x $rcatcher_y 2 0

		dservSet planko/complete waiting
		
		rmtSend "nexttrial $stimtype"
	    }
	}

	$s add_method endobs {} {
	    if { $correct != -1 } {
		dl_put stimdg:remaining $cur_id 0
		incr obs_count
	    }
	}
	
	$s add_method finished {} {
	    return [expr [dl_sum stimdg:remaining]==0]
	}

	$s add_method prestim {} {
	    soundPlay 1 70 200
	}
	
	$s add_method stim_on {} {
	    ::ess::touch_region_on 0
	    ::ess::touch_region_on 1
	    rmtSend "!stimon"
	}

	$s add_method stim_off {} {
	    rmtSend "!stimoff"
	}

	$s add_method feedback { resp correct } {
	    rmtSend "!show_response [expr $resp-1]"
	}

	$s add_method feedback_complete {} {
	    if { [dservGet planko/complete] != "waiting" } { return 1 } { return 0 }
	}

	$s add_method reward {} {
	    rmtSend "!show_feedback [expr $resp-1] $correct"
	    soundPlay 3 70 70
	    ::ess::reward $juice_ml
	    ::ess::evt_put REWARD MICROLITERS [now] [expr {int($juice_ml*1000)}]
	}

	$s add_method noreward {} {
	    rmtSend "!show_feedback [expr $resp-1] $correct"
	}

	$s add_method finale {} {
	    soundPlay 6 60 400
	}
	
  $s add_method responded {} {
            
            set r -1
            set made_selection 0
            set updated_position 0

            if { $use_joystick } {
                set joy_position [dservGet ess/joystick/value]
                ## 8 LEFT, 4 RIGHT; make sure to adjust numbered inputs on system settings in psychophys room
                if { $joy_position != 8 && $joy_position != 4 && $joy_position != 0 } {
                    if { [dservExists ess/joystick/position] } {
                        if { [dservGet ess/joystick/position] != 0 } {
                            dservSet ess/joystick/position 0
                            return -2
                        } else {
                            return -1
                        }
                    } else {
                        dservSet ess/joystick/position 0
                        return -2
                    }
                }
                # note which position has been activated
                if { [dservExists ess/joystick/position] } {
                    set cur_position [dservGet ess/joystick/position]
                } else {
                    set cur_position -1
                }
                if { $joy_position != $cur_position } {
                    dservSet ess/joystick/position $joy_position
                    set updated_position 1
                }

                # only if the button is pressed should we count as response
                if { [dservGet ess/joystick/button] } {
                    set made_selection 1
                } else {
                    if { $updated_position } { set r -2 } { set r -1 }
                }
            }
            if { $use_touchscreen && $r == -1 } {
                foreach w "0 1" {
                    if { [::ess::touch_in_win $w] } {
                        set r $w
                        break
                    }
                }
                if { $r != -1 } {
                    set made_selection 1
                }
            }

            if { $made_selection } {
                rmtSend "cue_off; choices_off; feedback_off all"
                # r should be 0 for cue_valid == 1, 1 for cue_valid == 0
                set correct [expr {$r == (1-$cue_valid)}]
                set r 0
            }

            return $r
  }

	return
    }
}

