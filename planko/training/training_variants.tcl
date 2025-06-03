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
          description "jitter X ball start, vary hitplanks"
          loader_proc basic_planko
          loader_options {
              nr { 10 20 30 40 50 60 70 80 90 100 }
              nplanks { 10 }
              wrong_catcher_alpha { 1.0 }
              stim_dur { 500 750 1000 1500 2000 } 
      
              params {
                  { jitter_hit2 { ball_jitter_x 6 ball_start_y 6 ball_jitter_y 0 hitplanks 2 } }
                  { jitter_hit3 { ball_jitter_x 6 ball_start_y 6 ball_jitter_y 0 hitplanks 3 } }
                  { jitter_hit4 { ball_jitter_x 6 ball_start_y 6 ball_jitter_y 0 hitplanks 4 } }
              }
          }
      }
    }

    proc variants_init { s } {
        $s add_method single_init {} {
            rmtSend "setBackground 10 10 10"
        }

        $s add_method single_deinit {} {}

        $s add_method basic_planko { nr nplanks wrong_catcher_alpha params {stim_dur ""} } {
          set n_rep $nr
          if { [dg_exists stimdg] } { dg_delete stimdg }
      
          set n_obs [expr [llength $nplanks] * $n_rep]
      
          # ✅ Only pass world-generation-related params to planko
          set p "nplanks $nplanks $params"
          set g [planko::generate_worlds $n_obs $p]
      
          dl_set $g:wrong_catcher_alpha \
              [dl_repeat [dl_flist $wrong_catcher_alpha] $n_obs]
      
          dg_rename $g:id stimtype
          dl_set $g:remaining [dl_ones $n_obs]
      
          dg_rename $g stimdg
      
          # ✅ Set stim_dur system parameter only if specified
          if { $stim_dur ne "" } {
              $s set stim_dur $stim_dur
          }
      
          return $g
        }

        
    }
}