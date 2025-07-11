#
# VARIANTS
#   planko training
#
# DESCRIPTION
#   loader functions for planko variants
#

namespace eval planko::training {
    package require planko
    package require jitter_worlds_STORAGE

    
    proc loaders_init { s } {
        $s add_method basic_planko { nr nplanks wrong_catcher_alpha params } {
            set n_rep $nr

            if { [dg_exists stimdg] } {
                dg_delete stimdg
            }

            set n_obs [expr {[llength $nplanks] * $n_rep}]
            set maxx [expr {$screen_halfx}]
            set maxy [expr {$screen_halfy}]

            # this is a set of params to pass into generate_worlds
            set p "nplanks $nplanks $params"
            set g [planko::generate_worlds $n_obs $p]
            


            # Run jitter simulations
            set njitter 10
            set jittered [world_jitter $g $njitter 0 [dl_length $g:id]]

            # Embed jittered data with 'j_' prefixes
            dl_set $g:j_jx               $jittered:jx
            dl_set $g:j_jy               $jittered:jy
            dl_set $g:j_angle            $jittered:angle
            dl_set $g:j_jt               $jittered:t
            dl_set $g:j_jx_ball          $jittered:x
            dl_set $g:j_jy_ball          $jittered:y
            dl_set $g:j_distance         $jittered:distance
            dl_set $g:j_distance_matrix  $jittered:distance_matrix
    
            dl_set $g:wrong_catcher_alpha \
                [dl_repeat [dl_flist $wrong_catcher_alpha] $n_obs]

            # rename id column to stimtype
            dg_rename $g:id stimtype
            dl_set $g:remaining [dl_ones $n_obs]

            dg_rename $g stimdg
            return $g
        }
    }
}
