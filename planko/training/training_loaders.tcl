namespace eval planko::training {
    package require planko

    proc loaders_init { s } {
        $s add_method basic_planko { nr nplanks nhit wrong_catcher_alpha params } {
            set n_rep $nr

            if { [dg_exists stimdg] } {
                dg_delete stimdg
            }

            set n_obs [expr {[llength $nplanks] * $n_rep}]
            set maxx [expr {$screen_halfx}]
            set maxy [expr {$screen_halfy}]

            # --- Build combined params dict ---
            # Start with top-level options
            set p [dict create nplanks $nplanks nhit $nhit]

            # Expand entries from the params list (e.g., jittered block)
            dict for {k v} [lindex $params 0] {
                dict set p $k $v
            }

            # Generate the worlds using the combined param dict
            set g [planko::generate_worlds $n_obs $p]

            # Apply wrong_catcher_alpha
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