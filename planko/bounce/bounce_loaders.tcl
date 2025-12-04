#
# LOADERS
#   planko bounce loaders (different restitutions)
#
# DESCRIPTION
#   loader functions for planko::bounce
#

namespace eval planko::bounce {
    package require planko

    proc loaders_init { s } {
        $s add_method basic_planko { nr nplanks params } {
            set n_rep $nr

            if { [dg_exists stimdg] } { dg_delete stimdg }

            set n_obs [expr [llength $nplanks]*$n_rep]

            # this is a set of params to pass into generate_worlds
            set p "nplanks $nplanks $params"
            set g [planko::generate_worlds $n_obs $p]

            # rename id column to stimtytpe
            dl_set $g:id [dl_fromto 0 $n_obs]
            dl_set $g:stimtype $g:id
            dl_set $g:remaining [dl_ones $n_obs]

            set ball_color [dl_slist "0.0 1.0 1.0"]
            dl_set $g:ball_color [dl_repeat $ball_color $n_obs]

            dg_rename $g stimdg
            return $g
        }

        $s add_method setup_bounce { nr nplanks board_params ball_params } {
            if { [dg_exists stimdg] } { dg_delete stimdg }
            set g stimdg

            set plank_restitutions [dict get $ball_params plank_restitution]

            set nn [llength $nplanks]; # number of "nplank" conditions
            set nbr [llength $plank_restitutions]; # number bounciness conditions
            set n_obs [expr {$nn*$nbr*$nr}]

            foreach br $plank_restitutions {
                set p "plank_restitution $br $board_params"
                foreach np $nplanks {
                    lappend p nplanks $np
                    set w [planko::generate_worlds $nr $p]
                    if { ![dg_exists stimdg]} {
                        dg_copy $w stimdg
                    } else {
                        dg_append stimdg $w
                    }
                    dg_delete $w
                }
            }

            # add ball color(s) to stimdg
            dl_local colors [dl_slist {*}[dict get $ball_params ball_color]]
            dl_set $g:ball_color [dl_repeat $colors [expr {$n_obs/$nbr}]]

            # rename id column to stimtytpe
            dl_set $g:id [dl_fromto 0 $n_obs]
            dl_set $g:stimtype $g:id
            dl_set $g:remaining [dl_ones $n_obs]

            return $g
        }

        # find worlds that work with multiple ball types
        $s add_method setup_multiworld { nr nplanks board_params ball_params } {
            if { [dg_exists stimdg] } { dg_delete stimdg }
            set g stimdg

            # unlike setup_bounce, we want the _same_ board to work with each setting
            set plank_restitutions [dict get $ball_params plank_restitution]

            # this remains the same as above, but the same world will appear nbr times
            set nn [llength $nplanks]; # number of "nplank" conditions
            set nbr [llength $plank_restitutions]; # number bounciness conditions
            set n_obs [expr {$nn*$nbr*$nr}]

            # by passing "multi_settings" we indicate that more than one parameter
            # setting should be tested on the same world and all should be "acceptable"
            #
            # for this variant, we want the same world to work for two levels of ball bounciness
            #  (note that plank_restitution controls bounciness in these worlds)
            set msettings [lmap v $plank_restitutions {list plank_restitution $v}]

            foreach np $nplanks {
                set p "multi_settings [list $msettings] $board_params"
                lappend p nplanks $np
                set w [planko::generate_worlds $nr $p]
                if { ![dg_exists stimdg]} {
                    dg_copy $w stimdg
                } else {
                    dg_append stimdg $w
                }
                dg_delete $w
            }

	    # full simulation
	    dl_set $g:perception_only [dl_zeros $n_obs]
	    
            # add ball color(s) to stimdg
            # each world is repeated so this is correct
            dl_local colors [dl_slist {*}[dict get $ball_params ball_color]]
            dl_set $g:ball_color [dl_replicate $colors [expr {$n_obs/$nbr}]]

            # rename id column to stimtytpe
            dl_set $g:id [dl_fromto 0 $n_obs]
            dl_set $g:world_id [dl_repeat [dl_fromto 0 [expr {$n_obs/$nbr}]] $nbr]
            dl_set $g:stimtype $g:id
            dl_set $g:remaining [dl_ones $n_obs]

            return $g
        }

	$s add_method setup_perception { nr nplanks show_planks board_params ball_params } {
	    set g [my setup_multiworld $nr $nplanks $board_params $ball_params]
	    # perception only
	    set n [dl_length $g:id]
	    dl_set $g:perception_only [dl_ones $n]

	    # adjust plank visibility (should move to planko packa
	    dl_set $g:show_planks [dl_repeat $show_planks $n]
	    dl_local is_plank [dl_regmatch $g:name plank*]
	    dl_set $g:visible [dl_replace $g:visible $is_plank $show_planks]

	    # set fix_color to reddish
	    dl_set $g:fix_color [dl_repeat [dl_slist "0.8 0.2 0.1"] $n]
	}

	$s add_method setup_biased_perception { nr nplanks keep_left keep_right show_planks board_params ball_params } {
	    set g [my setup_multiworld $nr $nplanks $board_params $ball_params]
	    # perception only
	    set n [dl_length $g:id]
	    dl_set $g:perception_only [dl_ones $n]

	    # adjust plank visibility (should move to planko packa
	    dl_set $g:show_planks [dl_repeat $show_planks $n]
	    dl_local is_plank [dl_regmatch $g:name plank*]
	    dl_set $g:visible [dl_replace $g:visible $is_plank $show_planks]

	    # set fix_color to reddish
	    dl_set $g:fix_color [dl_repeat [dl_slist "0.8 0.2 0.1"] $n]

	    # now mark some trials as done to practice one side or other
	    dl_local skip_left [dl_and [dl_eq stimdg:side 0] [dl_lt [dl_urand $n] $keep_left]]
	    dl_local skip_right [dl_and [dl_eq stimdg:side 1] [dl_lt [dl_urand $n] $keep_right]]
	    dl_local skip [dl_or $skip_left $skip_right]
	    dl_set stimdg:remaining $skip
	}
    }
}










