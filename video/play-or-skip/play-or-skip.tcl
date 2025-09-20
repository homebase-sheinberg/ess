#
# PROTOCOL
#   video play-or-skip
#
# DESCRIPTION
#   Offer videos to be watched or skipped
#

namespace eval video::play-or-skip {
    variable params_defaults { n_rep 50 }

    proc protocol_init { s } {
        $s set_protocol [namespace tail [namespace current]]

        $s add_param rmt_host $::ess::rmt_host stim ipaddr

        $s add_param juice_ml 0.6 variable float

        $s add_variable play_x
        $s add_variable play_y
        $s add_variable play_r

        $s add_variable skip_x
        $s add_variable skip_y
        $s add_variable skip_r

        $s set_protocol_init_callback {
            ::ess::init
            
            # configure juicer
            ::ess::juicer_init
            
            # open connection to rmt and upload ${protocol}_stim.tcl
            my configure_stim $rmt_host
            
            # initialize touch processor
            ::ess::touch_init
            
            # listen for end of playback
            dservAddExactMatch video/complete
            dpointSetScript video/complete ess::do_update
            
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
            foreach t "0 1" { ::ess::touch_region_off $t }
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
        }

        $s add_method n_obs {} { return [dl_length stimdg:stimtype] }

        $s add_method nexttrial {} {
            if { [dl_sum stimdg:remaining] } {
                dl_local left_to_show [dl_select stimdg:stimtype [dl_gt stimdg:remaining 0]]
                set cur_id [dl_pickone $left_to_show]
                set stimtype [dl_get stimdg:stimtype $cur_id]
                
                # virtual button info for play and skip
                lassign [dl_get stimdg:play_button $stimtype] play_x play_y play_r
                lassign [dl_get stimdg:skip_button $stimtype] skip_x skip_y skip_r

                for { set i 0 } { $i < 8 } { incr i } { ::ess::touch_region_off $i }
                ::ess::touch_reset
                ::ess::touch_win_set 0 $play_x $play_y $play_r 0
                ::ess::touch_win_set 1 $skip_x $skip_y $skip_r 0

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
            foreach t "0 1" { ::ess::touch_region_on $t }
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
            soundPlay 3 70 70
            ::ess::reward $juice_ml
            ::ess::evt_put REWARD MICROLITERS [now] [expr {int($juice_ml*1000)}]
        }
        
        $s add_method noreward {} {
            
        }
        
        $s add_method finale {} {
            soundPlay 6 60 400
        }
        
        $s add_method play {} {
            dservSet video/complete 0
            rmtSend "!play"
        }
        $s add_method play_complete {} { return [dservGet video/complete] }
        
        $s add_method responded {} {
            if { [::ess::touch_in_win 0] } {
                return 1;	# play
            } elseif { [::ess::touch_in_win 1] } {
                return 2;	# skip
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

		# video window
		# play_button
		# skip_button
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
























