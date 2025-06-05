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

            # --- Unpack params and add nhit into the inner dictionary ---
            set param_entry [lindex $params 0]
            set param_key   [lindex $param_entry 0]
            set param_dict  [lindex $param_entry 1]

            dict set param_dict nhit $nhit

            set updated_params [list $param_key $param_dict]

            # Build the final dictionary for generate_worlds
            set p [dict create nplanks $nplanks $updated_params]

            # Generate worlds
            set g [planko::generate_worlds $n_obs $p]

            # Set metadata
            dl_set $g:wrong_catcher_alpha \
                [dl_repeat [dl_flist $wrong_catcher_alpha] $n_obs]

            dg_rename $g:id stimtype
            dl_set $g:remaining [dl_ones $n_obs]
            dg_rename $g stimdg

            return $g
        }
    }
}