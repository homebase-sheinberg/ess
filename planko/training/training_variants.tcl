#
# VARIANTS
#   planko training
#
# DESCRIPTION
#   variant dictionary
#

namespace eval planko::training {
    package require planko
    
    variable params_defaults { n_rep 50 }

    variable variants {
        single {
            description "one plank"
            loader_proc basic_planko
            loader_options {
                nr { 100 200 300 }
                nplanks { 1 }
                wrong_catcher_alpha 1
                params { { defaults {} } }
            }
        }
        jitter {
            description "jitter ball start"
            loader_proc basic_planko
            loader_options {
                nr { 50 100 200 }
                nplanks { 1 }
                wrong_catcher_alpha { 1 0.5 }
                params { { jittered { ball_jitter_x 8 ball_start_y 5 ball_jitter_y 1 } } }
            }
        }
        zero_one {
            description "hit zero or one plank"
            loader_proc basic_planko
            loader_options {
                nr { 50 100 200 400 800 }
                nplanks { 1 }
                wrong_catcher_alpha { 1.0 0.98 0.95 0.9 0.8 0.7 }
                params { { jittered { ball_jitter_x 10 ball_start_y 0 ball_jitter_y 3 minplanks 0 } } }
            }
        }
        two_plus {
            description "show 2+ planks, hit 1+ plank"
            loader_proc basic_planko
            loader_options {
                nr { 50 100 200 400 800 }
                nplanks { 2 3 4 }
                wrong_catcher_alpha { 1.0 0.98 0.95 0.9 0.8 0.7 }
                params {
                    { jittered { ball_jitter_x 10 ball_start_y 0 ball_jitter_y 3 minplanks 1 } }
                    { higher   { ball_jitter_x 10 ball_start_y 5 ball_jitter_y 3 minplanks 1 } }
                    { two_plank { ball_jitter_x 10 ball_start_y 5 ball_jitter_y 3 minplanks 2 } }
                }
            }
        }
        super_monkey {
            description "alternate ball start X with hitplanks 2–4"
            loader_proc super_loader
            loader_options {
                nr { 10 20 30 40 50 60 70 80 90 100 }
                nplanks { 10 }
                wrong_catcher_alpha { 1.0 }
                params {
                    { default_hit2     { hitplanks 2 } }
                    { default_hit3     { hitplanks 3 } }
                    { default_hit4     { hitplanks 4 } }

                    { twozero_hit2     { ball_start_x {-2.0 0.0 0.0 2.0} hitplanks 2 } }
                    { twozero_hit3     { ball_start_x {-2.0 0.0 0.0 2.0} hitplanks 3 } }
                    { twozero_hit4     { ball_start_x {-2.0 0.0 0.0 2.0} hitplanks 4 } }

                    { threeSeven_hit2  { ball_start_x {-3.0 -2.0 -1.0 0.0 1.0 2.0 3.0} hitplanks 2 } }
                    { threeSeven_hit3  { ball_start_x {-3.0 -2.0 -1.0 0.0 1.0 2.0 3.0} hitplanks 3 } }
                    { threeSeven_hit4  { ball_start_x {-3.0 -2.0 -1.0 0.0 1.0 2.0 3.0} hitplanks 4 } }
                }
            }
        }
    }

    proc variants_init { s } {
        $s add_method single_init {} {
            rmtSend "setBackground 10 10 10"
        }

        $s add_method single_deinit {} {}

        $s add_method basic_planko { nr nplanks wrong_catcher_alpha params } {
            set n_rep $nr
            if { [dg_exists stimdg] } { dg_delete stimdg }

            set n_obs [expr [llength $nplanks] * $n_rep]

            set p "nplanks $nplanks $params"
            set g [planko::generate_worlds $n_obs $p]

            dl_set $g:wrong_catcher_alpha \
                [dl_repeat [dl_flist $wrong_catcher_alpha] $n_obs]

            dg_rename $g:id stimtype
            dl_set $g:remaining [dl_ones $n_obs]

            dg_rename $g simdg
            return $g
        }

        $s add_method super_loader { nr nplanks wrong_catcher_alpha params } {
            set n_obs [expr [llength $nplanks] * $nr]

            # Flatten any list-valued params across trials
            foreach key {ball_start_x ball_start_y hitplanks} {
                if {[dict exists $params $key]} {
                    set val [dict get $params $key]
                    if {[llength $val] > 1} {
                        if {$key eq "hitplanks"} {
                            dict set params $key [dl_repeat [dl_ilist $val] $n_obs]
                        } else {
                            dict set params $key [dl_repeat [dl_flist $val] $n_obs]
                        }
                    } else {
                        dict set params $key [dl_repeat [dl_flist $val] $n_obs]
                    }
                }
            }

            set g [dg_create]
            for {set i 0} {$i < $n_obs} {incr i} {
                set trial_params [dict create]
                foreach key {ball_start_x ball_start_y hitplanks} {
                    if {[dict exists $params $key]} {
                        dict set trial_params $key [dl_get [dict get $params $key] $i]
                    }
                }
                dict set trial_params nplanks $nplanks

                set p ""
                  dict for {k v} $trial_params {
                  append p "$k \"$v\" "
                }

                set trial [planko::generate_worlds 1 $p]
                dl_set $trial:wrong_catcher_alpha [dl_flist $wrong_catcher_alpha]

                if {$i == 0} {
                    set g $trial
                } else {
                    dg_append $g $trial
                    dg_delete $trial
                }
            }

            dg_rename $g simdg
            return $g
        }
    }
}