#
# VARIANTS
#   planko bounce
#
# DESCRIPTION
#   variant dictionary for planko::bounce
#

namespace eval planko::bounce {

    set ball_presets {
        { cold {
                plank_restitution {0.2}
                ball_color {{0.0 1.0 1.0}}
            }
        }
        { cool {
                plank_restitution {0.4}
                ball_color {{0.6 1.0 0.3}}
            }
        }
        { warm {
                plank_restitution {0.6}
                ball_color {{0.86 0.77 0.19}}
            }
        }
        { hot {
                plank_restitution {0.8}
                ball_color {{1.0 0.67 0.12}}
            }
        }
        { cold_cool {
                plank_restitution {0.2 0.4}
                ball_color {{0.0 1.0 1.0} {0.6 1.0 0.25}}
            }
        }
        { cold_warm {
                plank_restitution {0.2 0.6}
                ball_color {{0.0 1.0 1.0} {0.86 0.77 0.19}}
            }
        }
        { cold_hot {
                plank_restitution {0.2 0.8}
                ball_color {{0.0 1.0 1.0} {1.0 0.67 0.12}}
            }
        }
    }

    variable variants {
        standard {
            description "standard board"
            loader_proc basic_planko
            loader_options {
                nr { 4 20 60 120 }
                nplanks { 8 }
                params {
                    { jittered {
                            ball_jitter_x 10
                            ball_start_y 8
                            minplanks 2
                            planks_min_dist 1.4
                            planks_max_x 12.0
                            lcatcher_x -3.25
                            rcatcher_x 3.25
                        }
                    }
                }
            }
            init {
                planko::enable_threading 4
                rmtSend "setBackground 0 0 10"
            }
            deinit {
                planko::disable_threading
            }
            params { use_buttons 1 left_button 20 right_button 22 save_ems 1 }
        }
        multiball {
            description "boards with different balls"
            loader_proc setup_bounce
            loader_options {
                nr { 4 10 25 30 }
                nplanks { {4 4} {8 8} {4+8 {4 8}} }
                board_params {
                    { jittered {
                            ball_jitter_x 10
                            ball_start_y 8
                            minplanks 2
                            planks_min_dist 1.4
                            planks_max_x 12.0
                            lcatcher_x -3.25
                            rcatcher_x 3.25
                        }
                    }
                }
                ball_params { $ball_presets }
            }
            init {
                planko::enable_threading 4
                rmtSend "setBackground 0 0 10"
            }
            deinit {
                planko::disable_threading
            }
            params { use_buttons 1 left_button 20 right_button 22 save_ems 1 }
        }
        multiworld {
            description "worlds that work with different balls"
            loader_proc setup_multiworld
            loader_options {
                nr { 4 6 8 10 20 25 30 60 100 }
                nplanks { {2 2} {4 4} {8 8} {4+8 {4 8}} }
                board_params {
                    { jittered {
                            ball_jitter_x 10
                            ball_start_y 8
                            minplanks 2
                            planks_min_dist 1.4
                            planks_max_x 12.0
                            lcatcher_x -3.25
                            rcatcher_x 3.25
                        }
                    }
                }
                ball_params { $ball_presets }
            }
            init {
                planko::enable_threading 4
                rmtSend "setBackground 0 0 10"
            }
            deinit {
                planko::disable_threading
            }
            params { use_buttons 1 left_button 20 right_button 22 save_ems 1 }
        }
    }

    set variants [subst $variants]
}














