#
#  SYSTEM
#    video
#
#  DECRIPTION
#    System for video watching tasks
#

package require ess

namespace eval video {
    proc create {} {
        set sys [::ess::create_system [namespace tail [namespace current]]]

        ######################################################################
        #                          System Parameters                         #
        ######################################################################

        $sys add_param interblock_time 1000 time int
        $sys add_param prestim_time 250 time int
        $sys add_param response_timeout 5000 time int
        $sys add_param use_response_timeout 0 variable bool

        ##
        ## Local variables for this system
        ##
        $sys add_variable n_obs 100
        $sys add_variable obs_count 0
        $sys add_variable cur_id 0

        $sys add_variable start_delay 0
        $sys add_variable stimtype 0

        $sys add_variable response 0
        $sys add_variable first_time 1

        $sys add_variable correct -1
        $sys add_variable stimon_time
        $sys add_variable rt

        $sys add_variable finale_delay 500

        ######################################################################
        #                            System States                           #
        ######################################################################

        $sys set_start start

        #
        # start
        #
        $sys add_state start {} { return start_delay }

        #
        # start_delay
        #
        $sys add_action start_delay {
            ::ess::evt_put SYSTEM_STATE RUNNING [now]
            timerTick $start_delay

        }
        $sys add_transition start_delay {
            if { [timerExpired] } { return inter_obs }
        }

        #
        # inter_obs
        #
        $sys add_action inter_obs {

            set n_obs [my n_obs]

            if { !$first_time } {
                set delay $interblock_time
            } else {
                set first_time 0
                set delay 0
            }
            set rt -1
            set correct -1
            timerTick $delay
            my nexttrial
        }

        $sys add_transition inter_obs {
            if [my finished] { return pre_finale }
            if { [timerExpired] } { return start_obs }
        }

        #
        # start_obs
        #
        $sys add_action start_obs {
            ::ess::begin_obs $obs_count $n_obs
        }
        $sys add_transition start_obs {
            return pre_stim
        }

        #
        # pre_stim
        #
        $sys add_action pre_stim {
            timerTick $prestim_time
            my prestim
        }
        $sys add_transition pre_stim {
            if { [timerExpired] } { return next_video }
        }

        #
        # next_video
        #
        $sys add_action next_video {
            my show_next_video
        }
        $sys add_transition next_video {
            if { [my select_next_video] } { return stim_on }
        }

        #
        # stim_on
        #
        $sys add_action stim_on {
            my stim_on
            set stimon_time [now]
            ::ess::evt_put STIMTYPE STIMID $stimon_time $stimtype
            ::ess::evt_put PATTERN ON $stimon_time
        }

        $sys add_transition stim_on {
            return wait_for_response
        }

        #
        # wait_for_response
        #
        $sys add_action wait_for_response {
            if { $use_response_timeout } {
                timerTick $response_timeout
            }
        }

        $sys add_transition wait_for_response {
            if { $use_response_timeout } {
                if [timerExpired] { return no_response }
            }
            set response [my responded]
            if { $response != 0 } { return response }
        }

        #
        # response
        #
        $sys add_action response {
            set resp_time [now]
            ::ess::evt_put RESP $response $resp_time
	    ::ess::evt_put ENDTRIAL CORRECT [now]
            set rt [expr {($resp_time-$stimon_time)/1000}]
        }

        $sys add_transition response {
            if { $response == 1 } {
                return play
            } else {
                return post_trial
            }
        }

        #
        # play
        #
        $sys add_action play {
            my play
            ::ess::evt_put PATTERN 2 [now]
        }

        $sys add_transition play {
            if { [my play_complete] } { return post_trial }
        }


        #
        # no_response
        #
        $sys add_action no_response {
            my stim_off
	    set curt [now]
            ::ess::evt_put PATTERN OFF $curt
            ::ess::evt_put RESP NONE $curt
	    ::ess::evt_put ENDTRIAL ABORT $curt
            set correct -1
        }

        $sys add_transition no_response {
            return post_trial
        }


        #
        # post_trial
        #
        $sys add_action post_trial {
            ::ess::save_trial_info $correct $rt $stimtype
        }

        $sys add_transition post_trial {
            return finish
        }

        #
        # finish
        #
        $sys add_action finish {
            my endobs
            ::ess::end_obs COMPLETE
        }

        $sys add_transition finish { return inter_obs }

        #
        # pre_finale
        #
        $sys add_action pre_finale {
            timerTick $finale_delay
        }

        $sys add_transition pre_finale {
            if { [timerExpired] } {
                return finale
            }
        }

        $sys add_action finale { my finale }
        $sys add_transition finale { return end }

        #
        # end
        #
        $sys set_end {}



        ######################################################################
        #                         System Callbacks                           #
        ######################################################################

        $sys set_init_callback {
            ::ess::init
        }

        $sys set_deinit_callback {}

        $sys set_reset_callback {
            set n_obs [my n_obs]
            set obs_count 0
        }

        $sys set_start_callback {
            set first_time 1
        }

        $sys set_quit_callback {
            ::ess::end_obs QUIT
        }

        $sys set_end_callback {}

        $sys set_file_open_callback {}

        $sys set_file_close_callback {}

        $sys set_subject_callback {}

        ######################################################################
        #                          System Methods                            #
        ######################################################################

        $sys add_method n_obs { } { return 10 }
        $sys add_method nexttrial { } {
            set cur_id $obs_count
            set stimtype $obs_count
        }

        $sys add_method finished { } {
            if { $obs_count == $n_obs } { return 1 } { return 0 }
        }

        $sys add_method endobs {} { incr obs_count }
        $sys add_method prestim {} {}
        $sys add_method show_next_video {} {}
        $sys add_method select_next_video {} {}
        $sys add_method stim_on {} {}
        $sys add_method play {} {}
        $sys add_method play_complete {} { return 1 }
        $sys add_method stim_off {} {}
        $sys add_method reward {} {}
        $sys add_method finale {} {}

        $sys add_method responded {} { return 0 }


        return $sys
    }
}
