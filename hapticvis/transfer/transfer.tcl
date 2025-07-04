##
## PROTOCOL
##   hapticvis transfer
##
## DESCRIPTION
##   Present a shape and subject selects matching spatial location
##

namespace eval hapticvis::transfer {
    variable params_defaults { delay_time 100 }

    proc protocol_init { s } {
        $s set_protocol [namespace tail [namespace current]]

        $s add_param juice_ml 0.6 variable float
        $s add_param use_joystick 1 variable bool
        $s add_param joystick_side 0 variable int
        $s add_param use_touchscreen 1 variable bool

        $s add_param jarvis_host {} variable ipaddr

        $s add_variable rmt_host $::ess::rmt_host
        $s add_variable cur_id -1
        $s add_variable target_slot -1
        $s add_variable task {}
        $s add_variable trial_type visual
        $s add_variable shape_id -1
        $s add_variable shape_angle -1
        $s add_variable shape_hand -1
        $s add_variable correct -1
        $s add_variable n_choices 0
        $s add_variable choices {}
        $s add_variable follow_dial 0
        $s add_variable follow_pattern 0

        $s set_protocol_init_callback {
            ::ess::init

            # open connection to rmt and upload ${protocol}_stim.tcl
            my configure_stim $rmt_host

            if { $use_touchscreen } {
                # initialize touch processor
                ::ess::touch_init
            }

            ::ess::juicer_init

            # register to listen for haptic events
            ::haptic::init

            # this protocol sets stim_update on changes to grasp/dial_angle
            dservAddExactMatch grasp/dial_angle
            dpointSetScript grasp/dial_angle ::ess::hapticvis::transfer::process_dial
            dservSet grasp/dial_angle 0

            soundReset
            soundSetVoice 81 0 0
            soundSetVoice 57 17 1
            soundSetVoice 60 0 2
            soundSetVoice 42 0 3
            soundSetVoice 21 0 4
            soundSetVoice 8 0 5
            soundSetVoice 113 100 6
            foreach i "0 1 2 3 4 5 6" { soundVolume 127 $i }
        }

        $s set_protocol_deinit_callback {
            rmtClose
        }

        $s set_final_init_callback {
            # wait until variants have potentially changed joystick_side
            if { $use_joystick } {
                if { $joystick_side == 0 } {
                    dservSet joystick/lines { 1 23 2 19 4 22 8 20 }
                } else {
                    dservSet joystick/lines { 1 19 2 23 4 20 8 22 }
                }
                ::ess::joystick_init
            }
        }

        $s set_reset_callback {
            dl_set stimdg:remaining [dl_ones [dl_length stimdg:trial_type]]
            set obs_count 0
            rmtSend reset
        }

        $s set_start_callback {
            set first_time 1

            if { 0 && $jarvis_host != "" } {
                set s [socket $jarvis_host 1234]
                fconfigure $s -buffering line
                puts $s "setRunMode 2"; gets $s
                close $s
            }
        }

        $s set_quit_callback {
            if { $use_touchscreen } {
                foreach i "0 1 2 3 4 5 6 7" { ::ess::touch_region_off $i }
            }
            rmtSend clearscreen

            if { $trial_type == "haptic" } {
                my haptic_clear
            }

            if { 0 && $jarvis_host != "" } {
                set s [socket $jarvis_host 1234]
                fconfigure $s -buffering line
                puts $s "setRunMode 1"; gets $s
                close $s
            }

            ::ess::end_obs QUIT
        }

        $s set_end_callback {
            if { $use_touchscreen } {
                foreach i "0 1 2 3 4 5 6 7" { ::ess::touch_region_off $i }
            }
            ::ess::evt_put SYSTEM_STATE STOPPED [now]

            # automatically close open files at end of run
            if { $::ess::open_datafile != "" } {
                ::ess::file_close
            }
        }

        $s set_file_open_callback {
            #
            # log grasp related events
            #                             pointname obs bufsize every
            dservLoggerAddMatch $filename grasp/sensor0/vals 1 240 1
            dservLoggerAddMatch $filename grasp/sensor0/touched 1
            dservLoggerAddMatch $filename grasp/dial_angle 1 16 1
            dservLoggerAddMatch $filename grasp/available 1
            print "logging grasp events"

            #
            # open jarvis datafile if using video capture
            #
            if { $jarvis_host != "" } {
                set s [socket $jarvis_host 1234]
                fconfigure $s -buffering line
                set basename [file root [file tail $filename]]
                puts $s "setFilename $basename"; gets $s
                #		puts $s "setRunMode 3"; gets $s
                #		puts $s "setRunMode 1"; gets $s
                close $s
            }
        }

        $s set_file_close_callback {
            #	    my process_data $filename [file root $filename].json
            print "closed $filename"

            if { $jarvis_host != "" } {
                set s [socket $jarvis_host 1234]
                fconfigure $s -buffering line
                if { 0 } {
                    puts $s "setRunMode 0"; gets $s
                    puts $s "setFilename enter_filename"; gets $s
                }
                close $s
            }

        }


        ######################################################################
        #                         Utility Methods                            #
        ######################################################################

        $s add_method start_obs_reset {} {
        }

        $s add_method n_obs {} { return [dl_length stimdg:trial_type] }

        $s add_method nexttrial {} {
            if { [dl_sum stimdg:remaining] } {
                dl_local rem [dl_gt stimdg:remaining 0]
                set curgroup [dl_min [dl_select stimdg:group $rem]]
                dl_local in_curgroup [dl_select stimdg:stimtype [dl_and [dl_eq stimdg:group $curgroup] $rem]]
                set cur_id [dl_pickone $in_curgroup]
                set stimtype [dl_get stimdg:stimtype $cur_id]
                set n_choices [dl_get stimdg:n_choices $cur_id]
                set choices [my get_choices $n_choices]
                set follow_dial [dl_get stimdg:follow_dial $cur_id]
                set follow_pattern [expr {![string equal [dl_get stimdg:follow_pattern $cur_id] 0]}]

                set have_cue [dl_get stimdg:is_cued $cur_id]
                set cue_valid [dl_get stimdg:cue_valid $cur_id]


                if { $have_cue } {
                    foreach i "0 1" {
                        set choice_x [dl_get stimdg:lr_choice_centers:$cur_id:$i 0]
                        set choice_y [dl_get stimdg:lr_choice_centers:$cur_id:$i 1]
                        set choice_r [dl_get stimdg:lr_choice_scale $cur_id]
                        if { $use_touchscreen } {
                            ::ess::touch_region_off $i
                            ::ess::touch_win_set $i $choice_x $choice_y $choice_r 0
                        }
                    }
                } else {
                    for { set i 0 } { $i < $n_choices } { incr i } {
                        set slot [lindex $choices $i]
                        # set these touching_response knows where choices are
                        set choice_x [dl_get stimdg:choice_centers:$cur_id:$i 0]
                        set choice_y [dl_get stimdg:choice_centers:$cur_id:$i 1]
                        set choice_r [dl_get stimdg:choice_scale $cur_id]
                        if { $use_touchscreen } {
                            ::ess::touch_region_off $slot
                            ::ess::touch_win_set $slot $choice_x $choice_y $choice_r 0
                        }
                    }
                }

                set task [dl_get stimdg:task $cur_id]
                set target_slot [dl_get stimdg:correct_choice $cur_id]
                set trial_type [dl_get stimdg:trial_type $cur_id]
                set shape_id [dl_get stimdg:shape_id $cur_id]
                set shape_angle [dl_get stimdg:shape_rot_deg_cw $cur_id]
                set shape_hand [dl_get stimdg:hand $cur_id]

                rmtSend "nexttrial $cur_id"

                set correct -1
                return $cur_id
            }
        }
        $s add_method finished {} {
            return [expr [dl_sum stimdg:remaining]==0]
        }

        $s add_method endobs {} {
            dl_put stimdg:remaining $cur_id 0
            incr obs_count
        }

        $s add_method stim_on {} {
            soundPlay 1 70 200
            rmtSend "!stim_on"
        }

        $s add_method stim_off {} {
            rmtSend "!stim_off"
            if { $trial_type == "haptic" && $sample_up == 1 } {
                my haptic_prep
            }
            if { !$simulate_grasp && $follow_dial } { my dial_reset }
        }

        $s add_method dial_reset {} {
            if { $simulate_grasp } { return }
            package require rest
            set ip 192.168.88.84
            set port 8888

            set url http://${ip}:${port}
            set res [rest::get $url [list function reset_dial]]
        }

        $s add_method dial_follow {} {
            if { $simulate_grasp } { return }
            package require rest
            set ip 192.168.88.84
            set port 8888

            set url http://${ip}:${port}
            set res [rest::get $url [list function follow_dial_or_pattern follow true mode report_only]]
        }

        $s add_method dial_unfollow {} {
            if { $simulate_grasp } { return }
            package require rest
            set ip 192.168.88.84
            set port 8888

            set url http://${ip}:${port}
            set res [rest::get $url [list function follow_dial_or_pattern follow false]]
        }

        $s add_method haptic_show { shape_id a { hand 1 } } {
            if { $simulate_grasp } {
                dservSet ess/grasp/available 1
                return
            }
            package require rest
            set ip 192.168.88.84
            set port 8888

            set angle [expr {int($a)%360}]
            set url http://${ip}:${port}
            set zero_pt -177.4
            if {$hand == 0} {
                set arm_offset [expr $zero_pt + 25]
                set res [rest::get $url [list function pick_and_place hand 0 xoffset $arm_offset left_id $shape_id left_angle $angle return_duplicates 0 dont_present 1 use_dummy 1 dummy_ids 20302,2001 reset_dial $follow_dial dial_following $follow_dial pattern_following $follow_pattern
                ]
                ]
            } else {
                set arm_offset [expr $zero_pt - 25]
                set res [rest::get $url [list function pick_and_place hand 0 xoffset $arm_offset left_id $shape_id left_angle $angle return_duplicates 0 dont_present 1 use_dummy 1 dummy_ids 20302,2001 reset_dial $follow_dial dial_following $follow_dial pattern_following $follow_pattern
                ]
                ]
            }
        }

        $s add_method haptic_clear { } {
            if { $simulate_grasp } { return }
            package require rest
            set ip 192.168.88.84
            set port 8888

            set url http://${ip}:${port}
            set res [rest::get $url [list function put_away side 2]]
        }

        $s add_method haptic_prep { } {
            if { $simulate_grasp } { return }
            package require rest
            set ip 192.168.88.84
            set port 8888

            set url http://${ip}:${port}
            set res [rest::get $url [list function set_dxl_positions side 0 position prep_present]]
        }

        $s add_method sample_on {} {
            if { $trial_type == "visual" } {
                rmtSend "!sample_on"
                if { !$simulate_grasp && $follow_dial } { my dial_follow }
            } elseif { $trial_type == "haptic" } {
                my haptic_show $shape_id $shape_angle $shape_hand
            }
        }

        $s add_method sample_presented {} {
            if { $trial_type == "visual" } {
                if { $sample_up == 1 } { return 1 } { return 0 }
            } else {
                if { [dservGet ess/grasp/available] } {
                    return 1
                } else {
                    return 0
                }
            }
        }

        $s add_method stim_update {} {
            if { $trial_type == "visual" && $sample_up } {
                set noise_angle [dservGet grasp/dial_angle]
                rmtSend "!rotate_noise $noise_angle"
            }
        }

        $s add_method sample_off {} {
            if { $trial_type == "visual" } {
                rmtSend "!sample_off"
                if { !$simulate_grasp && $follow_dial } { my dial_unfollow }
            } elseif { $trial_type == "haptic" } {
                my haptic_prep
            }
        }

        $s add_method cue_on {} {
            rmtSend "!cue_on"
        }

        $s add_method cue_off {} {
            rmtSend "!cue_off"
        }

        $s add_method get_choices { n } {
            if { $n == 4 } {
                return "1 3 5 7"
            } elseif { $n == 6 } {
                return "1 2 3 5 6 7"
            } else {
                return "0 1 2 3 4 5 6 7"
            }
        }

        $s add_method choices_on {} {
            rmtSend "!choices_on"
            if { $use_touchscreen } {
                if { $have_cue } {
                    foreach i "0 1" { ::ess::touch_region_on $i }
                } else {
                    set cs [my get_choices $n_choices]
                    foreach i $cs { ::ess::touch_region_on $i }
                }
            }
        }

        $s add_method choices_off {} {
            rmtSend "!choices_off"
            if { $use_touchscreen } {
                if { $have_cue } {
                    foreach i "0 1" { ::ess::touch_region_off $i }
                } else {
                    set cs [my get_choices $n_choices]
                    foreach i $cs { ::ess::touch_region_off $i }
                }
            }
            rmtSend "!feedback_off all"
        }

        $s add_method reward {} {
            if { $task == "learning" } {
                soundPlay 3 70 70
                ::ess::reward $juice_ml
                ::ess::evt_put REWARD MICROLITERS [now] [expr {int($juice_ml*1000)}]
            }
        }

        $s add_method noreward {} {
            if { $task == "learning" } {
                soundPlay 4 90 300
            }
        }

        $s add_method finale {} {
            soundPlay 6 60 400
        }

        $s add_method response_correct {} {
            return $correct
        }

        $s add_method highlight_response {} {
            set p [dservGet ess/joystick/position]
            ::ess::evt_put DECIDE SELECT [now] $p
            rmtSend "highlight_response $p"
        }

        $s add_method responded {} {
            # if no response to report, return -1
            set r -1
            set made_selection 0
            set updated_position 0

            if { $use_joystick } {
                if { $n_choices == 4 } {
                    # ur=9(0) ul=5(1) dl=6(2) dr=10(3)
                    set mapdict { 0 -1 9 0 5 1 6 2 10 3 }
                } elseif { $n_choices == 6 } {
                    # u=1(1)  d=2(4) ul=5(2) ur=9(0) d-=6(3) dr=10(5)
                    set mapdict { 0 -1 1 1 2 4 5 2 9 0 6 3 10 5}
                } else {
                    # up=1(2)   down=2(6)  left=4(4)   right=8(0)
                    # ul=5(3) ur=9(1) dl=6(5) dr=10(7)
                    set mapdict { 0 -1 1 2 2 6 4 4 8 0 5 3 9 1 6 5 10 7 }
                }
                set joy_position [dservGet ess/joystick/value]

                # if this is not an allowable position reset to 0
                if { ![dict exists $mapdict $joy_position] } {
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

                # map actual position to slot
                set r [dict get $mapdict $joy_position]

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
                foreach w $choices {
                    if { [::ess::touch_in_win $w] } {
                        set r $w
                        break
                    }
                }

                if { $n_choices == 4 } {
                    # 4 skip cardinal
                    set mapdict { 0 -1 1 0 2 -1 3 1 4 -1 5 2 6 -1 7 3 }
                } elseif { $n_choices == 6 } {
                    # 6 skip right and left
                    set mapdict { 0 -1 1 0 2 1 3 2 4 -1 5 3 6 4 7 5 }
                } else {
                    # 8 is identity
                    set mapdict { 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 }
                }
                if { $task == "learning" } {
                    if { $r != -1 } {
                        set r [dict get $mapdict $r]
                        if { $r != -1 } {
                            set made_selection 1
                        }
                    }
                }
            }

            if { $made_selection } {
                if { $task == "learning" } {
                    if { $r == [expr {$target_slot-1}] } {
                        set slot [expr $target_slot-1]
                        set choice_x [dl_get stimdg:choice_centers:$cur_id:$slot 0]
                        set choice_y [dl_get stimdg:choice_centers:$cur_id:$slot 1]
                        rmtSend "feedback_on correct $choice_x $choice_y"
                        set correct 1
                    } elseif { $r >= 0 } {
                        set slot [expr $target_slot-1]
                        set target_x [dl_get stimdg:choice_centers:$cur_id:$slot 0]
                        set target_y [dl_get stimdg:choice_centers:$cur_id:$slot 1]

                        set choice_x [dl_get stimdg:choice_centers:$cur_id:$r 0]
                        set choice_y [dl_get stimdg:choice_centers:$cur_id:$r 1]
                        set correct_fb "feedback_on correct $target_x $target_y"
                        set incorrect_fb "feedback_on incorrect $choice_x $choice_y"
                        rmtSend "${correct_fb}; ${incorrect_fb}"
                        set correct 0
                    }
                } else {
                    rmtSend "choices_off; feedback_off all"
                    set correct [expr {$r == $target_slot-1}]
                    set r 0
                }
            }

            return $r
        }

        # did subject respond left or right
        $s add_method responded_lr {} {
            # if no response to report, return -1
            set r -1
            set made_selection 0
            set updated_position 0

            if { $use_joystick } {
                set joy_position [dservGet ess/joystick/value]
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

        ######################################################################
        #                         Data Processing                            #
        #                                                                    #
        # 1. Open the original ess file                                      #
        # 2. Read using dslogReadESS                                         #
        # 3. Pull out response, response time, and status from valid trials  #
        # 4. Pull out stimtype for all valid trials                          #
        # 5. Use stimtype to pull all trial attributes from stimdg           #
        # 6. Add to new dg                                                   #
        # 7. Convert to JSON and export as new file or return JSON string    #
        #                                                                    #
        ######################################################################

        $s add_method process_data { essfile { jsonfile {} } } {
            package require dlsh
            package require dslog
            set g [::dslog::readESS $essfile]

            # get relevant event ids
            lassign [::ess::evt_id ENDTRIAL ABORT] endt_id endt_abort
            lassign [::ess::evt_id ENDOBS COMPLETE] endobs_id endobs_complete
            lassign [::ess::evt_id CHOICES ON] choices_id choices_on
            lassign [::ess::evt_id SAMPLE ON] sample_id sample_on
            lassign [::ess::evt_id RESP] resp_id
            lassign [::ess::evt_id STIMTYPE] stimtype_id

            # valid trials have an endtrial subtype which is 0 or 1
            dl_local endtrial [dl_select $g:e_subtypes [dl_eq $g:e_types $endt_id]]
            dl_local endobs [dl_select $g:e_subtypes [dl_eq $g:e_types $endobs_id]]
            dl_local valid [dl_sums [dl_and [dl_eq $endobs $endobs_complete] [dl_lengths $endtrial] [dl_lt $endtrial $endt_abort]]]

            # extract event types/subtypes/times/params for valid trials
            foreach v "types subtypes times params" {
                dl_local $v [dl_select $g:e_$v $valid]
            }

            # pull out variables of interest
            dl_local correct [dl_unpack [dl_select $subtypes [dl_eq $types $endt_id]]]
            dl_local stimon_t [dl_unpack [dl_select $times [dl_and [dl_eq $types $sample_id] [dl_eq $subtypes $sample_on]]]]
            dl_local response_t [dl_unpack [dl_select $times [dl_eq $types $resp_id]]]
            dl_local response [dl_unpack [dl_select $subtypes [dl_eq $types $resp_id]]]
            dl_local stimtype [dl_unpack [dl_deepUnpack [dl_select $params [dl_eq $types $stimtype_id]]]]

            # create table to export
            set out [dg_create]
            dl_set $out:status $correct
            dl_set $out:rt [dl_sub $response_t $stimon_t]
            dl_set $out:response $response

            # find all stimdg columns and their names without <stimdg>
            set stimdg_cols [lsearch -inline -all -glob [dg_tclListnames $g] "<stimdg>*"]
            set cols [regsub -all <stimdg> $stimdg_cols {}]
            foreach c $cols {
                dl_set $out:$c [dl_choose $g:<stimdg>${c} $stimtype]
            }

            # find all ds columns and their names without <ds>
            set ds_cols [lsearch -inline -all -glob [dg_tclListnames $g] "<ds>*"]
            set cols [regsub -all <ds> $ds_cols {}]
            foreach c $cols {
                dl_set $out:$c [dl_choose $g:<ds>${c} $stimtype]
            }

            # close original ESS dg
            dg_delete $g

            # store as JSON
            set data [dg_toJSON $out]
            dg_delete $out
            if { $jsonfile != "" } {
                set f [open $jsonfile w]
                puts $f $data
                close $f
            } else {
                return $data
            }
        }

        return
    }

    proc process_dial { dpoint data } {
        $::ess::current(state_system) set_variable stim_update 1
        ::ess::do_update
    }

}

