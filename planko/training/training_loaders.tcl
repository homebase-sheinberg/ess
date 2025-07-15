#
# VARIANTS
#   planko training
#
# DESCRIPTION
#   loader functions for planko variants
#

namespace eval planko::training {
    package require planko
    
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
            

            dl_set $g:wrong_catcher_alpha \
                [dl_repeat [dl_flist $wrong_catcher_alpha] $n_obs]

            # rename id column to stimtype
            dg_rename $g:id stimtype
            dl_set $g:remaining [dl_ones $n_obs]

            dg_rename $g stimdg
            return $g
        }
        
        
        $s add_method random_minplanks_loader { nr nplanks wrong_catcher_alpha params } {
    set n_rep $nr

    if { [dg_exists stimdg] } {
        dg_delete stimdg
    }

    set n_obs [expr {[llength $nplanks] * $n_rep}]
    set maxx [expr {$screen_halfx}]
    set maxy [expr {$screen_halfy}]

    # Build randomized minplanks list (values 1 to 4)
    set randlist [dl_ilist]
    for {set i 0} {$i < $n_obs} {incr i} {
        dl_append $randlist [expr {1 + int(rand() * 4)}]
    }

    # Append randomized minplanks list to params
    append params " minplanks $randlist"

    # Generate the worlds
    set p "nplanks $nplanks $params"
    set g [planko::generate_worlds $n_obs $p]

    # Attach wrong_catcher_alpha to each trial
    dl_set $g:wrong_catcher_alpha \
        [dl_repeat [dl_flist $wrong_catcher_alpha] $n_obs]

    # Rename and finalize
    dg_rename $g:id stimtype
    dl_set $g:remaining [dl_ones $n_obs]
    dg_rename $g stimdg
    return $g
}


    }
}
