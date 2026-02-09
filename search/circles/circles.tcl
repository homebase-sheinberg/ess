#
# PROTOCOL
#   search circles
#
# DESCRIPTION
#   Present a large circle with possible distractors
#

namespace eval search::circles {
    variable params_defaults { n_rep 50 }

    proc protocol_init { s } {
        $s set_protocol [namespace tail [namespace current]]

        $s add_param rmt_host $::ess::rmt_host stim ipaddr

        $s add_param juice_ml 0.6 variable float

        $s add_param use_buttons 1 variable int
        $s add_param left_button 24 variable int
        $s add_param right_button 25 variable int

        $s add_variable targ_x
        $s add_variable targ_y
        $s add_variable targ_r

        $s add_variable dist_x
        $s add_variable dist_y
        $s add_variable dist_r

        $s set_protocol_init_callback {
            ::ess::init

            # configure juicer
            ::ess::juicer_init

            # open connection to rmt and upload ${protocol}_stim.tcl
            my configure_stim $rmt_host

            # initialize touch processor
            ::ess::touch_init

	    # configure sound
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
                dl_local left_to_show [dl_select stimdg:stimtype [dl_gt stimdg:remaining 0]]
                set cur_id [dl_pickone $left_to_show]
                set stimtype [dl_get stimdg:stimtype $cur_id]

                # set these touching_spot knows where target is
                foreach p "targ_x targ_y targ_r" {
                    set $p [dl_get stimdg:$p $stimtype]
                }

                for { set i 0 } { $i < 8 } { incr i } { ::ess::touch_region_off $i }
                ::ess::touch_reset
                ::ess::touch_win_set 0 $targ_x $targ_y $targ_r 0

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
            ::ess::sound_play 1 70 200
        }

        $s add_method stim_on {} {
            ::ess::touch_region_on 0
            foreach t "press release" {
                if { [dservExists ess/touch_${t}] } {
                    set touch_last_${t} [dservTimestamp ess/touch_${t}]
                
                }
            }
            rmtSend "!stimon"
        }

        $s add_method stim_off {} {
            rmtSend "!stimoff"
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

        $s add_method responded {} {
            if { [::ess::touch_in_win 0] } {
                ::ess::touch_evt_put ess/touch_press [dservGet ess/touch_press]
                return 1
            } else {
                return 0
            }
        }

        ######################################################################
        #                           Visualization                            #
        ######################################################################

        $s set_viz_config {
            proc setup {} {
                package require planko

                evtSetScript 3 2 [namespace current]::reset
                evtSetScript 7 0 [namespace current]::stop
                evtSetScript 19 -1 [namespace current]::beginobs
                evtSetScript 20 -1 [namespace current]::endobs
                evtSetScript 29 -1 [namespace current]::stimtype
                evtSetScript 28 1 [namespace current]::stimon
                evtSetScript 28 0 [namespace current]::stimoff
                
                clearwin
                setbackground [dlg_rgbcolor 100 100 100]
                setwindow -20 -14 20 14
                flushwin
            }

            proc reset { t s d } { clearwin; flushwin }
            proc stop { t s d } {clearwin; flushwin }
            proc beginobs { type subtype data } {
                clearwin
                flushwin
            }
            proc stimtype { type subtype data } {
                variable trial
                set trial $data
            }
            proc stimon { type subtype data } {
                variable trial
                clearwin

                # Draw target
                foreach v "x y r color" {
                    set targ_${v} [dl_get stimdg:targ_${v} $trial]
                }
                dl_local c [dl_flist {*}$targ_color]
                set color [dlg_rgbcolor {*}[dl_tcllist [dl_int [dl_mult $c 255]]]]
                dlg_markers $targ_x $targ_y -marker fcircle -size $targ_r -scaletype x -color $color

                # Draw distractors
                set ndists [dl_get stimdg:dists_n $trial]
                for { set i 0 } { $i < $ndists } { incr i } {
                    foreach v "x y r color" {
                        set dist_${v} [dl_get stimdg:dist_${v}s:$trial $i]
                    }
                    dl_local c [dl_flist {*}$dist_color]
                    set color [dlg_rgbcolor {*}[dl_tcllist [dl_int [dl_mult $c 255]]]]
                    dlg_markers $dist_x $dist_y -marker fcircle -size $dist_r -scaletype x -color $color

                }
                flushwin
            }

            proc stimoff { type subtype data } {
                clearwin; flushwin
            }

            proc endobs { type subtype data } {
            }

            setup
        }
        return
    }
}





















