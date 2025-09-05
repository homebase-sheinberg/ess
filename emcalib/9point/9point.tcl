#
# PROTOCOL
#   emcalib 9point
#
# DESCRIPTION
#   Present targets at 9 locations for calibration task
#

namespace eval emcalib::9point {
    variable params_defaults {}

    proc protocol_init { s } {
        $s set_protocol [namespace tail [namespace current]]

        $s add_param rmt_host $::ess::rmt_host stim ipaddr
        $s add_param juice_ml .5 variable float
        $s add_param fix_radius 3.0 variable float

        $s add_variable fix_targ_x
        $s add_variable fix_targ_y
        $s add_variable fix_targ_r

        $s add_variable jump_targ_x
        $s add_variable jump_targ_y
        $s add_variable jump_targ_r

        $s set_protocol_init_callback {
            ::ess::init

            # configure juice subsystem
            ::ess::juicer_init

            # open connection to rmt and upload ${protocol}_stim.tcl
            my configure_stim $rmt_host

            # initialize eye movements
            ::ess::em_init

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

        $s set_reset_callback {
            dl_set stimdg:remaining [dl_ones [dl_length stimdg:stimtype]]
            set obs_count 0
            rmtSend reset
        }

        $s set_start_callback {
            set first_time 1
        }

        $s set_quit_callback {
            rmtSend clearscreen
            ::ess::em_region_off 0
            ::ess::em_region_off 1
            ::ess::end_obs QUIT
        }

        $s set_end_callback {
            ::ess::evt_put SYSTEM_STATE STOPPED [now]

            # automatically close open files at end of run
            if { $::ess::open_datafile != "" } {
                ::ess::file_close
            }

        }

        $s set_file_open_callback {
            print "opened datafile $filename"
        }

        $s set_file_close_callback {
            print "closed datafile $filename"
        }


        ######################################################################
        #                         Utility Methods                            #
        ######################################################################

        $s add_method n_obs {} { return [dl_length stimdg:stimtype] }

        $s add_method nexttrial {} {
            if { [dl_sum stimdg:remaining] } {
                dl_local left_to_show   [dl_select stimdg:stimtype [dl_gt stimdg:remaining 0]]
                set cur_id [dl_pickone $left_to_show]
                set stimtype [dl_get stimdg:stimtype $cur_id]

                # locations and sizes of fix and jump
                foreach t "fix jump" {
                    foreach p "${t}_targ_x ${t}_targ_y ${t}_targ_r" {
                        set $p [dl_get stimdg:$p $stimtype]
                    }
                }

                ::ess::em_sampler_configure $sample_count
                ::ess::em_region_off 0
                ::ess::em_region_off 1
                ::ess::em_fixwin_set 0 $fix_targ_x $fix_targ_y $fix_radius 0
                ::ess::em_fixwin_set 1 $jump_targ_x $jump_targ_y $fix_radius 0

                rmtSend "nexttrial $stimtype"
            }
        }

        $s add_method endobs {} {
            if { $complete } {
                dl_put stimdg:remaining $cur_id 0
                incr obs_count
            }
        }

        $s add_method finished {} {
            return [expr [dl_sum stimdg:remaining]==0]
        }

        $s add_method fixon {} {
            soundPlay 1 70 200
            rmtSend "!fixon"
            ::ess::em_region_on 0
            ::ess::evt_put EMPARAMS CIRC [now]  0 $fix_targ_x $fix_targ_y $fix_targ_r
        }

        $s add_method acquired_fixspot {} {
            return [::ess::em_eye_in_region 0]
        }

        $s add_method out_of_start_win {} {
            return [expr ![::ess::em_eye_in_region 0]]
        }

        $s add_method fixjump {} {
            # leave r0 on, so as to not trigger update unrelated to r1
            rmtSend "!fixjump"
            ::ess::em_region_on 1
            ::ess::evt_put EMPARAMS CIRC [now] 1 $jump_targ_x $jump_targ_y $jump_targ_r
        }

        $s add_method acquired_fixjump {} {
            return [::ess::em_eye_in_region 1]
        }

        $s add_method sample_position {} {
            ::ess::em_sampler_start 0
        }

        $s add_method out_of_sample_win {} {
            return [expr ![::ess::em_eye_in_region 1]]
        }

        $s add_method sample_position_complete {} {
            return [::ess::em_sampler_status]
        }

        $s add_method store_calibration {} {
            ::ess::evt_put EMPARAMS CALIB [now] {*}[::ess::em_sampler_vals]
        }

        $s add_method reward {} {
            soundPlay 3 70 70
            ::ess::reward $juice_ml
            ::ess::evt_put REWARD MICROLITERS [now] [expr {int($juice_ml*1000)}]
        }

        $s add_method fixation_off {} {
            rmtSend "!fixoff"
            ::ess::em_region_off 0
            ::ess::em_region_off 1
        }

        $s add_method finale {} {
            soundPlay 6 60 400
        }
        
        $s set_viz_config {
            proc setup {} {
                evtSetScript 3   2 [namespace current]::reset
                evtSetScript 7   0 [namespace current]::stop
                evtSetScript 19 -1 [namespace current]::beginobs
                evtSetScript 20 -1 [namespace current]::endobs
                evtSetScript 25 -1 [namespace current]::fixspot
                evtSetScript 26  3 [namespace current]::calib
                evtSetScript 29 -1 [namespace current]::stimtype
            }
            
            proc reset { t s d } { viz::clear_display }
            proc stop { t s d } { viz::clear_display }                
            proc beginobs { type subtype data }	{
                setbackground [dlg_rgbcolor 20 20 20]
                setwindow -8 -8 8 8 
                flushwin
            }
            proc stimtype { type subtype data } { 
                variable trial
                set trial $data
            }
            proc calib { type subtype data } {
                variable calib_x; variable calib_y
                variable cur_x; variable cur_y
                lassign $data calib_x calib_y
                set msg [format "%.0f %.0f" $calib_x $calib_y]
                clearwin
                set white [dlg_rgbcolor 200 200 200]
                dlg_text $cur_x $cur_y [list $msg] -size 16 -just 0 -color $white
                flushwin
            }
            
            proc endobs { type subtype data }	{
                #  clearwin
                #  dlg_text 0 0 "Endobs $subtype" -size 24 -just 0
                #  dservSet graphics/stimulus [dumpwin json]
            }
            
            proc fixspot { type subtype data } {
                variable trial 
                variable cur_x; variable cur_y; variable cur_r
                clearwin
                if { $subtype == 1 } { 
                    set cur_x [dl_get stimdg:fix_targ_x $trial]
                    set cur_y [dl_get stimdg:fix_targ_y $trial]
                    set cur_r [dl_get stimdg:fix_targ_r $trial]
                } else {
                    set cur_x [dl_get stimdg:jump_targ_x $trial]
                    set cur_y [dl_get stimdg:jump_targ_y $trial]
                    set cur_r [dl_get stimdg:jump_targ_r $trial]
                }
                dlg_markers $cur_x $cur_y fcircle -size ${cur_r}x  -color [dlg_rgbcolor 200 200 0]
                flushwin
            }
            setup
        }        
        return
    }
}











