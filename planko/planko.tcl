#
#  NAME
#    planko.tcl
#
#  DECRIPTION
#    System for training planko
#

package require ess

namespace eval planko {
    proc create {} {
        set sys [::ess::create_system [namespace tail [namespace current]]]

        ######################################################################
        #                          System Parameters                         #
        ######################################################################

        $sys add_param interblock_time 1000 time int
        $sys add_param prestim_time 250 time int

        $sys add_param response_timeout 25000 time int
        $sys add_param max_feedback_time 8000 time int
        $sys add_param post_feedback_time 1000 time int

        $sys add_param stimup_time -1 time int

        ##
        ## Local variables for this system
        ##
        $sys add_variable n_obs 100
        $sys add_variable obs_count 0
        $sys add_variable cur_id 0

        $sys add_variable start_delay 0
        $sys add_variable stimtype 0

        $sys add_variable stim_timer 1
        $sys add_variable stim_up 0

        $sys add_variable response 0
        $sys add_variable first_time 1


        $sys add_variable side -1
        $sys add_variable resp -1
        $sys add_variable correct -1
        $sys add_variable stimon_time 0
        $sys add_variable rt 0

        $sys add_variable finale_delay 1000

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
            set resp -1
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
            if { [timerExpired] } { return stim_on }
        }

        #
        # stim_on
        #
        $sys add_action stim_on {
            my stim_on
            set stimon_time [now]
            set stim_up 1
            ::ess::evt_put PATTERN ON $stimon_time
            ::ess::evt_put STIMTYPE STIMID $stimon_time $stimtype

            timerTick $response_timeout
            if { $stimup_time != -1 } {
                timerTick $stim_timer $stimup_time
            }
        }

        $sys add_transition stim_on {
            return wait_for_response
        }

        #
        # wait_for_response
        #
        $sys add_action wait_for_response {
        }

        $sys add_transition wait_for_response {
            if [timerExpired] { return no_response }
            if { $stimup_time > 0 && $stim_up && [timerExpired $stim_timer] } {
                return stim_hide
            }

            set response [my responded]
            if { $response != 0 } { return response }

        }

        #
        # stim_hide
        #
        $sys add_action stim_hide {
            my stim_hide
            ::ess::evt_put PATTERN OFF [now]
            set stim_up 0
        }

        $sys add_transition stim_hide {
            return wait_for_response
        }

        #
        # response
        #
        $sys add_action response {
            set resp_time [now]
            ::ess::evt_put RESP $resp $resp_time
            set rt [expr {($resp_time-$stimon_time)/1000}]

            if { !$stim_up } {
                my stim_unhide
                set stim_up 1
                ::ess::evt_put PATTERN ON [now]
            }
        }

        $sys add_transition response {
            return feedback
        }

        #
        # feedback
        #
        $sys add_action feedback {
            my feedback $resp $correct
            timerTick $max_feedback_time
        }

        $sys add_transition feedback {
            if { [timerExpired] || [my feedback_complete] } {
                if { $correct } { return correct } { return incorrect }
            }
        }


        #
        # correct
        #
        $sys add_action correct {
            set correct 1
            my reward
        }

        $sys add_transition correct { return post_feedback }

        #
        # incorrect
        #
        $sys add_action incorrect {
            set correct 0
            my noreward
        }

        $sys add_transition incorrect { return post_feedback }

        #
        # post_feedback
        #
        $sys add_action post_feedback {
            timerTick $post_feedback_time
        }

        $sys add_transition post_feedback {
            if { [timerExpired] } {
                return stimoff
            }
        }


        #
        # stimoff
        #
        $sys add_action stimoff {
            my stim_off
            ::ess::evt_put PATTERN OFF [now]
        }

        $sys add_transition stimoff {
            return post_trial
        }

        #
        # no_response
        #
        $sys add_action no_response {
            my stim_off
            ::ess::evt_put PATTERN ON [now]
            ::ess::evt_put RESP NONE [now]
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
        $sys add_method stim_on {} {}
        $sys add_method stim_off {} {}
        $sys add_method stim_hide {} {}
        $sys add_method stim_unhide {} {}
        $sys add_method feedback { resp correct } { print $resp/$correct }
        $sys add_method feedback_complete {} { return 0 }
        $sys add_method reward {} {}
        $sys add_method noreward {} {}
        $sys add_method finale {} {}

        $sys add_method responded {} { return 0 }

        return $sys
    }
}
