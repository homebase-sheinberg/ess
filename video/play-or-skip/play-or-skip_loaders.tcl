#
# LOADERS
#   video play-or-skip
#
# DESCRIPTION
#   loader for video preference task
#

namespace eval video::play-or-skip {
    proc loaders_init { s } {
        $s add_method basic_load { nr } {
            if { [dg_exists stimdg] } { dg_delete stimdg }
            set g [dg_create stimdg]
            dg_rename $g stimdg

            set n_obs [expr $nr]

            set maxx [expr $screen_halfx]
            set maxy [expr $screen_halfy]
            set y [expr {-0.9*$maxy}]

            dl_set $g:stimtype [dl_fromto 0 $n_obs]

            dl_local playinfo [dl_slist "-2.0 $y 1.2"]
            dl_local skipinfo [dl_slist "2.0 $y 1.2"]
            dl_local nextinfo [dl_slist "0 0 4"]
            dl_set $g:next_button [dl_replicate $nextinfo $n_obs]
            dl_set $g:play_button [dl_replicate $playinfo $n_obs]
            dl_set $g:skip_button [dl_replicate $skipinfo $n_obs]
            dl_set $g:video [dl_replicate [dl_slist none] $n_obs]

            dl_set $g:remaining [dl_ones $n_obs]

            return $g
        }
    }
}


