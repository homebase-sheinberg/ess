#
# PROTOCOL
#   planko training
#
# DESCRIPTION
#   Train planko
#

namespace eval planko::training {

    variable params_defaults { n_rep 50 }

    proc protocol_init { s } {
        $s set_protocol [namespace tail [namespace current]]

        $s add_param rmt_host $::ess::rmt_host stim ipaddr
        $s add_param juice_ml .6 variable float
        $s add_param use_buttons 0 variable int
        $s add_param left_button 24 variable int
        $s add_param right_button 25 variable int

        $s add_variable touch_count 0
        $s add_variable touch_last 0
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

        # Fixed visualization script with proper event timing
        $s set_visualization_scripts {
            "eyeTouch:planko" {
                console.log('=== PLANKO FINAL VISUALIZATION ===');

                let processedTrials = null;
                let currentTrialElements = new Set();
                let stimulusVisible = false;

                function loadTrialData() {
                    const rawStimInfo = getStimInfo();
                    if (rawStimInfo) {
                        processedTrials = processStimData(rawStimInfo);
                        console.log('Loaded', processedTrials.length, 'trials for visualization');
                        return true;
                    }
                    return false;
                }

                function setupTrial(stimtype) {
                    console.log('=== SETTING UP TRIAL ===', stimtype);

                    if (!processedTrials && !loadTrialData()) {
                        console.log('No trial data available');
                        return;
                    }

                    if (stimtype < 0 || stimtype >= processedTrials.length) {
                        console.warn('Invalid stimtype:', stimtype);
                        return;
                    }

                    const trial = processedTrials[stimtype];
                    console.log('Setting up trial with', trial.name?.length || 0, 'elements');

                    // Clear previous elements
                    draw.clearElements();
                    currentTrialElements.clear();

                    // Create elements for this trial
                    if (trial.name && Array.isArray(trial.name)) {
                        for (let i = 0; i < trial.name.length; i++) {
                            const name = trial.name[i];
                            const shape = trial.shape ? trial.shape[i] : 'Box';
                            const x = trial.tx ? trial.tx[i] : 0;
                            const y = trial.ty ? trial.ty[i] : 0;
                            const width = trial.sx ? trial.sx[i] : 1;
                            const height = trial.sy ? trial.sy[i] : 1;
                            const rotation = trial.angle ? trial.angle[i] : 0;

                            let fillColor = '#ffffff';
                            let strokeColor = '#cccccc';

                            // Handle different element types
                            if (name === 'ball') {
                                fillColor = '#ff6600'; // Orange ball
                                strokeColor = '#cc4400';

                                // Use ball_color if available
                                if (trial.ball_color) {
                                    if (typeof trial.ball_color === 'string' && trial.ball_color.includes(' ')) {
                                        const rgb = trial.ball_color.split(' ').map(parseFloat);
                                        if (rgb.length === 3) {
                                            const r = Math.round(rgb[0] * 255);
                                            const g = Math.round(rgb[1] * 255);
                                            const b = Math.round(rgb[2] * 255);
                                            fillColor = `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
                                        }
                                    } else {
                                        fillColor = trial.ball_color;
                                    }
                                    strokeColor = fillColor;
                                }
                            } else if (name === 'catchl_b') {
                                // Left catcher - green if correct side, gray otherwise
                                fillColor = (trial.side === 0) ? '#00ff00' : '#808080';
                                strokeColor = '#ffffff';
                            } else if (name === 'catchr_b') {
                                // Right catcher - red if correct side, gray otherwise
                                fillColor = (trial.side === 1) ? '#ff0000' : '#808080';
                                strokeColor = '#ffffff';
                            } else if (name.includes('plank')) {
                                // Planks/obstacles
                                fillColor = '#ffffff'; // white
                                strokeColor = '#ffffff';
                            } else {
                                // Default elements
                                fillColor = '#cccccc';
                                strokeColor = '#999999';
                            }

                            let elementId;
                            if (shape === 'Circle') {
                                elementId = draw.addElement({
                                    type: 'circle',
                                    id: name,
                                    x: x, y: y,
                                    radius: width,
                                    fillColor: fillColor,
                                    strokeColor: strokeColor,
                                    lineWidth: 1,
                                    visible: stimulusVisible
                                });
                            } else {
                                // Default to rectangle for Box and other shapes
                                elementId = draw.addElement({
                                    type: 'rectangle',
                                    id: name,
                                    x: x, y: y,
                                    width: width, height: height,
                                    fillColor: fillColor,
                                    strokeColor: strokeColor,
                                    lineWidth: 1,
                                    rotation: -rotation, // Negative for correct rotation direction
                                    visible: stimulusVisible
                                });
                            }

                            if (elementId) {
                                currentTrialElements.add(elementId);
                            }
                        }
                    }

                    console.log(`Trial setup complete: ${currentTrialElements.size} elements created`);
                }

                // Load initial data
                loadTrialData();

                // Handle STIMTYPE events - this tells us which trial to display
                registerEventHandler(STIMTYPE_STIMID, (event) => {
                    if (event.params && event.params.length > 0) {
                        const stimtype = parseInt(event.params[0]);
                        setupTrial(stimtype);
                    }
                });

                // Handle stimulus visibility
                registerEventHandler(PATTERN_ON, (event) => {
                    console.log('Making stimulus visible');
                    stimulusVisible = true;
                    currentTrialElements.forEach(id => {
                        draw.updateElement(id, { visible: true });
                    });
                });

                registerEventHandler(PATTERN_OFF, (event) => {
                    console.log('Hiding stimulus');
                    stimulusVisible = false;
                    currentTrialElements.forEach(id => {
                        draw.updateElement(id, { visible: false });
                    });
                });

                // Handle responses - highlight the selected catcher
                registerEventHandler(RESP_LEFT, (event) => {
                    console.log('Left response detected');
                    draw.updateElement('catchl_b', { fillColor: '#ffff00', strokeColor: '#cccc00' });
                });

                registerEventHandler(RESP_RIGHT, (event) => {
                    console.log('Right response detected');
                    draw.updateElement('catchr_b', { fillColor: '#ffff00', strokeColor: '#cccc00' });
                });

                // Handle trial outcomes
                registerEventHandler(ENDTRIAL_CORRECT, (event) => {
                    console.log('Correct trial - showing feedback');
                    draw.drawText(0, 3, 'Correct!', {
                        fontSize: 16, fillColor: '#00ff00', id: 'feedback'
                    });
                    setTimeout(() => { draw.removeElement('feedback'); }, 1000);
                });

                registerEventHandler(ENDTRIAL_INCORRECT, (event) => {
                    console.log('Incorrect trial - showing feedback');
                    draw.drawText(0, 3, 'Try Again', {
                        fontSize: 16, fillColor: '#ff0000', id: 'feedback'
                    });
                    setTimeout(() => { draw.removeElement('feedback'); }, 1000);
                });

                // Clean up at end of observation
                registerEventHandler(20, (event) => { // ENDOBS
                    console.log('End of observation - clearing all elements');
                    draw.clearElements();
                    currentTrialElements.clear();
                    stimulusVisible = false;
                });

                console.log('=== PLANKO VISUALIZATION READY ===');
            }
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
                dl_local left_to_show  [dl_select stimdg:stimtype [dl_gt stimdg:remaining 0]]
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

        $s add_method stim_hide {} {
            rmtSend "!planksoff"
        }

        $s add_method stim_unhide {} {
            rmtSend "!plankson"
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
            if { [::ess::touch_in_win 0] } {
                if { $side == 0 } { set correct 1 } { set correct 0 }
                set resp 1
                return 1
            } elseif { [::ess::touch_in_win 1] } {
                if { $side == 1 } { set correct 1 } { set correct 0 }
                set resp 2
                return 1
            } else {
                return 0
            }
        }

        return
    }
}



