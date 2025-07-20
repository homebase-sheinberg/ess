#
# LOADERS
#   planko bounce loaders
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
                    puts "generating worlds for $br/$np"
                    set w [planko::generate_worlds $nr $p]
                    if { ![dg_exists stimdg]} { 
                        dg_copy $w stimdg
                    } else { 
                        puts "following group created ([dl_length $w:id]->[dl_length $g:id])"
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

    }
}




