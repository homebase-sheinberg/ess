#
# PROTOCOL
#   match_to_sample colormatch
#
# DESCRIPTION
#   Present a target color and two choices
#

namespace eval match_to_sample::colormatch {
    variable params_defaults { sample_time 2000 delay_time 0 }

    proc protocol_init { s } {
        $s set_protocol [namespace tail [namespace current]]

        $s add_param rmt_host $::ess::rmt_host stim ipaddr

        $s add_param juice_ml 0.8 variable float

        $s add_param use_buttons 1 variable int
        $s add_param left_button 24 variable int
        $s add_param right_button 25 variable int

        $s add_variable targ_x
        $s add_variable targ_y
        $s add_variable targ_r

        $s add_variable dist_x
        $s add_variable dist_y
        $s add_variable dist_r

        $s add_variable buttons_changed 0
        $s add_variable cur_id 0
        $s add_variable correct -1

        $s set_protocol_init_callback {
            ::ess::init

            if { $use_buttons } {
                foreach b "$left_button $right_button" {
                    dservAddExactMatch gpio/input/$b
                    dservTouch gpio/input/$b
                    dpointSetScript gpio/input/$b ess::do_update
                }
            }

            # open connection to rmt and upload ${protocol}_stim.tcl
            my configure_stim $rmt_host

            # initialize touch processor
            ::ess::touch_init

            # configure juicer subsystem
            ::ess::juicer_init

	    # configure sound subsystem
            ::ess::sound_init
        }

        $s set_protocol_deinit_callback {
            ::ess::touch_deinit
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

        $s add_method button_pressed {} {
            if { $use_buttons } {
                if { [dservGet gpio/input/$left_button] ||
                    [dservGet gpio/input/$right_button] } {
                    return 1
                }
            }
            return 0
        }

        $s add_method start_obs_reset {} {
            set buttons_changed 0
        }

        $s add_method n_obs {} { return [dl_length stimdg:stimtype] }

        $s add_method nexttrial {} {
            if { [dl_sum stimdg:remaining] } {
                dl_local left_to_show [dl_select stimdg:stimtype [dl_gt stimdg:remaining 0]]
                set cur_id [dl_pickone $left_to_show]
                set stimtype [dl_get stimdg:stimtype $cur_id]

                # set these touching_response knows where choices are
                set targ_x [dl_get stimdg:match_x $stimtype]
                set targ_y [dl_get stimdg:match_y $stimtype]
                set targ_r [dl_get stimdg:match_r $stimtype]
                set dist_x [dl_get stimdg:nonmatch_x $stimtype]
                set dist_y [dl_get stimdg:nonmatch_y $stimtype]
                set dist_r [dl_get stimdg:nonmatch_r $stimtype]

                ::ess::touch_region_off 0
                ::ess::touch_region_off 1
                ::ess::touch_reset

                ::ess::touch_win_set 0 $targ_x $targ_y $targ_r 0
                ::ess::touch_win_set 1 $dist_x $dist_y $dist_r 0

                rmtSend "nexttrial $stimtype"

                set correct -1
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

        $s add_method presample {} {
            ::ess::sound_play 1 70 200
        }

        $s add_method sample_on {} {
            rmtSend "!sample_on"
        }

        $s add_method sample_off {} {
            rmtSend "!sample_off"
        }

        $s add_method choices_on {} {
            rmtSend "!choices_on"
            ::ess::touch_region_on 0
            ::ess::touch_region_on 1
        }

        $s add_method choices_off {} {
            rmtSend "!choices_off"
        }

        $s add_method reward {} {
            ::ess::sound_play 3 70 70
            ::ess::reward $juice_ml
            ::ess::evt_put REWARD MICROLITERS [now] [expr {int($juice_ml*1000)}]
        }

        $s add_method noreward {} {

        }

        $s add_method finale {} {
            ::ess::sound_play 6 60 400
        }

        $s add_method response_correct {} { return $correct }

        $s add_method responded {} {
            if { $use_buttons && $buttons_changed } {
                return -1
            }

            if { [::ess::touch_in_win 0] } {
                ::ess::touch_evt_put ess/touch_press [dservGet ess/touch_press]
                set correct 1
                return 0
            } elseif { [::ess::touch_in_win 1] } {
                ::ess::touch_evt_put ess/touch_press [dservGet ess/touch_press]
                set correct 0
                return 1
            } else {
                return -1
            }
        }

        $s set_viz_config {
            proc setup {} {
                evtSetScript 3 2 [namespace current]::reset
                evtSetScript 7 0 [namespace current]::stop
                evtSetScript 19 -1 [namespace current]::beginobs
                evtSetScript 20 -1 [namespace current]::endobs
                evtSetScript 29 -1 [namespace current]::stimtype
                evtSetScript 30 1 [namespace current]::sample_on
                evtSetScript 30 0 [namespace current]::sample_off
                evtSetScript 49 1 [namespace current]::choices_on
                evtSetScript 49 0 [namespace current]::choices_off

                clearwin
                setbackground [dlg_rgbcolor 100 100 100]
                setwindow -8 -8 8 8
                flushwin
            }

            proc reset { t s d } { clearwin; flushwin }
            proc stop { t s d } { clearwin; flushwin }
            proc beginobs { type subtype data } {
                clearwin
                flushwin
            }
            proc stimtype { type subtype data } {
                variable trial
                set trial $data
                set vars "sample_x sample_y sample_r match_x match_y match_r nonmatch_x nonmatch_y nonmatch_r"
                foreach v $vars { variable $v [dl_get stimdg:$v $trial] }

                # now turn colors into indices
                set vars "sample_color match_color nonmatch_color"
                foreach v $vars {
                    set rgb [dl_tcllist [dl_int [dl_mult stimdg:$v:$trial 255]]]
                    variable $v [dlg_rgbcolor {*}$rgb]
                }

                # approximate the transparency of the nonmatch stimulus
                if { [dl_exists stimdg:nonmatch_transparency] } {
                    set nmt [dl_get stimdg:nonmatch_transparency $trial]
                    if { $nmt < 1 } {
                        # assumes background is as set above, to 100 100 100
                        lassign [dl_tcllist stimdg:nonmatch_color:$trial] r g b
                        set r [expr {int($r*255*$nmt+100*(1-$nmt))}]
                        set g [expr {int($g*255*$nmt+100*(1-$nmt))}]
                        set b [expr {int($b*255*$nmt+100*(1-$nmt))}]
                        variable nonmatch_color [dlg_rgbcolor $r $g $b]
                    }
                }
            }
            proc sample_on { type subtype data } {
                variable trial
                variable sample_x; variable sample_y; variable sample_r
                variable sample_color
                clearwin
                dlg_markers $sample_x $sample_y fsquare -size ${sample_r}x -color $sample_color
                flushwin
            }
            proc sample_off { type subtype data } {
                clearwin; flushwin
            }
            proc choices_on { type subtype data } {
                variable trial
                variable match_x; variable match_y; variable match_r
                variable nonmatch_x; variable nonmatch_y; variable nonmatch_r
                variable match_color; variable nonmatch_color
                clearwin
                dlg_markers $match_x $match_y fsquare -size ${match_r}x -color $match_color
                dlg_markers $nonmatch_x $nonmatch_y fsquare -size ${nonmatch_r}x -color $nonmatch_color
                flushwin
            }
            proc choices_off { type subtype data } {
                clearwin; flushwin
            }
            proc endobs { type subtype data } {
            }

            setup
        }
        return
    }
}

















