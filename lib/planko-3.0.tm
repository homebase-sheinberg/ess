# -*- mode: tcl -*-

#
# planko-3.0.tm
#   Enhanced package for generating planko boards with threading support
#
package provide planko 3.0

package require box2d
package require dlsh
package require points

namespace eval planko {
    variable params
    variable use_threading 0
    variable num_threads 6
    variable min_threading_batch 4

    # Thread-local world tracking
    variable thread_worlds {}

    proc safe_dg_fromString { data name } {
        # Check if the data group already exists and delete it
        if {[dg_exists $name]} {
            puts "Warning: Data group '$name' already exists, deleting it"
            dg_delete $name
        }

        # Create the data group from string
        set result [dg_fromString $data $name]
        return $result
    }

    proc default_params {} {
        variable params
        set params(xrange) 12.0; # x range for selecting plank locations
        set params(yrange) 12.0; # y range for selecting plank locations
        set params(planks_min_dist) 1.0; # minimum distance between planks
        set params(planks_max_x) 9.0; # maximum x position
        set params(planks_max_y) 6.0; # maximum y position
        set params(planks_offset_y) 2.0; # offset y value away from catchers
        set params(planks_min_len) 2.0; # all planks at least this long
        set params(planks_max_len) 3.2; # no planks longer than this
        set params(floor_only) 0; # floor in place of catchers
        set params(lcatcher_x) -3; # x location of left catcher
        set params(lcatcher_y) -7.5; # y location of left catcher
        set params(rcatcher_x) 3; # x location of right catcher
        set params(rcatcher_y) -7.5; # y location of right catcher
        set params(ball_start_x) 0; # x location of ball start
        set params(ball_start_y) 8.0; # y location of ball start
        set params(ball_jitter_x) 0; # x jitter for ball start
        set params(ball_jitter_y) 0; # y jitter for ball start
        set params(ball_radius) 0.5; # radius of ball
        set params(nplanks) 10; # number of planks in world
        set params(minplanks) 1; # mininum number of planks hit
        set params(ball_restitution) 0.0; # restitution of the ball
        set params(plank_restitution) 0.2; # restitution of the ball
        set params(catcher_restitution) 0.05; # restitution of the ball
        set params(step_size) [expr 1.0/200]; # step size of simulation (200Hz)
        return
    }

    # Threading configuration and management
    proc enable_threading { {threads 6} } {
        variable use_threading
        variable num_threads

        if {[catch {package require Thread}]} {
            puts "Warning: Thread package not available, falling back to serial generation"
            set use_threading 0
            return 0
        }

        set use_threading 1
        set num_threads $threads
        puts "Threading enabled with $num_threads threads"
        return 1
    }

    proc disable_threading {} {
        variable use_threading
        set use_threading 0
        puts "Threading disabled"
    }

    proc configure_threading { args } {
        array set opts {
            -threads 6
            -min_batch_size 10
            -enable auto
        }
        array set opts $args

        variable num_threads $opts(-threads)
        variable min_threading_batch $opts(-min_batch_size)

        if {$opts(-enable) eq "auto"} {
            return [enable_threading $num_threads]
        } elseif {$opts(-enable)} {
            return [enable_threading $num_threads]
        } else {
            disable_threading
            return 0
        }
    }

    proc get_threading_info {} {
        variable use_threading
        variable num_threads
        variable min_threading_batch

        return [dict create enabled $use_threading threads $num_threads min_batch $min_threading_batch]
    }

    # Worker thread initialization script
    proc create_worker_script {} {
        return {
            # Setup worker thread environment
            set dlshlib [file join /usr/local/dlsh dlsh.zip]
            set base [file join [zipfs root] dlsh]
            if { ![file exists $base] && [file exists $dlshlib] } {
                zipfs mount $dlshlib $base
            }
            set ::auto_path [linsert $::auto_path [set auto_path 0] $base/lib]

            # Add module path and load required packages - match working version
            if { [info exists ::env(ESS_SYSTEM_PATH)] } {
                tcl::tm::path add $::env(ESS_SYSTEM_PATH)/ess/lib
            }
            package require box2d
            package require planko

            proc do_planko_work { n d worker_id } {
                puts "Worker $worker_id starting generation of $n worlds"

                if {[catch {
                        # Generate worlds in this thread's context
                        set g [planko::generate_worlds_serial $n $d]

                        set tid [thread::id]
                        puts "Worker $worker_id (thread $tid) completed $n worlds successfully"

                        # Serialize result for thread-safe transfer
                        dg_toString $g result_$tid

                        # Store result in thread-safe variable with session-specific key
                        upvar 1 session_id session_id
                        tsv::set planko_result "${session_id}_${tid}" [set result_$tid]
                        tsv::incr planko_result "${session_id}_count"

                        # Clean up local data
                        dg_delete $g

                    } work_error]} {
                    puts "ERROR in worker $worker_id: $work_error"
                    puts "Worker $worker_id error info: $::errorInfo"

                    # Store error result
                    upvar 1 session_id session_id
                    set tid [thread::id]
                    tsv::set planko_result "${session_id}_${tid}" "ERROR: $work_error"
                    tsv::incr planko_result "${session_id}_count"
                }

                # Notify main thread of completion
                upvar 1 main_tid main_tid
                thread::send $main_tid planko::check_completion
            }

            # Wait for work assignments
            thread::wait
        }
    }

    # Parallel world generation
    proc generate_worlds_parallel { n d } {
        variable num_threads

        # Don't use threading for small jobs
        if {$n < $num_threads * 2} {
            return [generate_worlds_serial $n $d]
        }

        puts "Generating $n worlds using $num_threads threads"

        # Distribute work across threads - handle remainder properly
        set worlds_per_thread [expr {$n / $num_threads}]
        set remainder [expr {$n % $num_threads}]

        set threads {}
        set thread_args {}

        for {set i 0} {$i < $num_threads} {incr i} {
            set thread_n $worlds_per_thread
            if {$i < $remainder} {incr thread_n} ; # Distribute remainder
            if {$thread_n > 0} {
                lappend thread_args [list $thread_n $d $i]
            }
        }

        # Create unique session ID to avoid conflicts between calls
        set session_id "session_[clock microseconds]"

        # Initialize thread-safe storage with session-specific keys
        if {[catch {
                tsv::set planko_result "${session_id}_count" 0
                set expected_threads [llength $thread_args]
                tsv::set planko_result "${session_id}_expected" $expected_threads
            } tsv_error]} {
            puts "TSV initialization error: $tsv_error"
            # Fallback to serial if TSV fails
            return [generate_worlds_serial $n $d]
        }

        # Set global session ID for check_completion to access
        set ::planko_current_session $session_id

        # Completion check procedure for main thread
        proc check_completion {} {
            set session_id $::planko_current_session
            if {[catch {
                    set count [tsv::get planko_result "${session_id}_count"]
                    set expected [tsv::get planko_result "${session_id}_expected"]
                    if {$count >= $expected} {
                        set ::planko_parallel_done 1
                    }
                } check_error]} {
                puts "Error in check_completion: $check_error"
                set ::planko_parallel_done 1 ; # Force completion on error
            }
        }

        # Create worker threads
        puts "expected threads: $expected_threads"
        set created_threads {}

        if {[catch {
                for {set i 0} {$i < $expected_threads} {incr i} {
                    set tid [thread::create [create_worker_script]]
                    lappend created_threads $tid
                    # Initialize with session-specific key
                    tsv::set planko_result "${session_id}_${tid}" {}
                }
                set threads $created_threads
            } thread_creation_error]} {
            puts "Thread creation error: $thread_creation_error"
            # Clean up any created threads
            foreach tid $created_threads {
            catch {thread::release $tid}
            }
            # Fallback to serial
            return [generate_worlds_serial $n $d]
        }

        # Start work in each thread
        if {[catch {
                set thread_index 0
                foreach tid $threads {
                    lassign [lindex $thread_args $thread_index] thread_n thread_d worker_id
                    thread::send $tid [list set main_tid [thread::id]]
                    thread::send $tid [list set session_id $session_id]
                    thread::send -async $tid [list do_planko_work $thread_n $thread_d $worker_id]
                    incr thread_index
                }
            } work_dispatch_error]} {
            puts "Work dispatch error: $work_dispatch_error"
            # Clean up threads
            foreach tid $threads {
            catch {thread::release $tid}
            }
            return [generate_worlds_serial $n $d]
        }

        # Wait for completion with timeout
        set timeout_ms 30000 ; # 30 second timeout
        set start_time [clock milliseconds]

        while {![info exists ::planko_parallel_done]} {
            vwait ::planko_parallel_done
            set elapsed [expr {[clock milliseconds] - $start_time}]
            if {$elapsed > $timeout_ms} {
                puts "Timeout waiting for parallel completion"
                break
            }
        }

        # Collect results with error handling
        set all_worlds {}
        set successful_threads 0

        foreach tid $threads {
            if {[catch {
                    set thread_result [tsv::get planko_result "${session_id}_${tid}"]
                    if {$thread_result ne "" && ![string match "ERROR:*" $thread_result]} {
                        # Create unique name for each thread's data
                        set unique_name "temp_${session_id}_${tid}"

                        # Use safe creation
                        set g [safe_dg_fromString $thread_result $unique_name]

                        if {$all_worlds eq ""} {
                            set all_worlds $g
                        } else {
                            if {[catch {dg_append $all_worlds $g} append_error]} {
                                puts "Error appending data from thread $tid: $append_error"
                                # Try to continue with remaining threads
                            } else {
                                dg_delete $g
                            }
                        }
                        incr successful_threads
                    } else {
                        puts "Thread $tid failed or returned error: $thread_result"
                    }
                } result_error]} {
                puts "Error processing results from thread $tid: $result_error"
            }

            # Clean up this thread's data immediately
        catch {tsv::unset planko_result "${session_id}_${tid}"}
        }

        # Clean up session data
    catch {tsv::unset planko_result "${session_id}_count"}
    catch {tsv::unset planko_result "${session_id}_expected"}

        # Clean up global session variable
    catch {unset ::planko_current_session}
    catch {unset ::planko_parallel_done}

        # Cleanup threads
        foreach tid $threads {
        catch {thread::release $tid}
        }

        puts "Parallel generation summary: $successful_threads/$expected_threads threads successful"

        # Verify we got some results
        if {$all_worlds eq "" || $successful_threads == 0} {
            puts "No successful parallel results, falling back to serial generation"
            return [generate_worlds_serial $n $d]
        }

        # Renumber IDs sequentially across all threads
        if {$all_worlds ne ""} {
            set total_worlds [dl_length $all_worlds:name]
            dl_set $all_worlds:id [dl_fromto 0 $total_worlds]
            puts "Parallel generation complete: $total_worlds worlds generated"
        }

        # Ensure the final data group has a simple, accessible name
        if {$all_worlds ne "" && [dg_exists $all_worlds]} {
            # Create a simple name that doesn't use session IDs
            set simple_name "worlds_[clock microseconds]"

            # If the current name is complex, rename to something simpler
            if {[string match "*session*" $all_worlds]} {
                dg_rename $all_worlds $simple_name
                set all_worlds $simple_name
            }

            set total_worlds [dl_length $all_worlds:name]
            dl_set $all_worlds:id [dl_fromto 0 $total_worlds]
            puts "Parallel generation complete: $total_worlds worlds generated as '$all_worlds'"
        } else {
            puts "Warning: No valid worlds generated"
        }

        return $all_worlds
    }

    # Serial world generation (renamed from original generate_worlds)
    proc generate_worlds_serial { n d } {
        variable params
        default_params

        dict for { k v } $d { set params($k) $v }

        set acc accept_board
        set worlds [pack_world [generate_world $acc]]
        for { set i 1 } { $i < $n } { incr i } {
            set world [pack_world [generate_world $acc]]
            if { $world != "" } {
                dg_append $worlds $world
                dg_delete $world
            } else {
                error "unable to generate desired world type"
            }
        }

        # first column is id - set to unique ids between 0 and n
        dl_set $worlds:id [dl_fromto 0 $n]

        return $worlds
    }

    # Main world generation dispatcher
    proc generate_worlds { n d } {
        variable use_threading
        variable num_threads
        variable min_threading_batch

        # Use threading if enabled and batch is large enough
        if {$use_threading && $n >= $min_threading_batch && $n >= $num_threads} {
            return [generate_worlds_parallel $n $d]
        } else {
            return [generate_worlds_serial $n $d]
        }
    }

    # All the original planko procedures remain unchanged
    proc create_ball_dg {} {
        variable params
        set b2_staticBody 0

        set g [dg_create]

        dl_set $g:id [dl_ilist]
        dl_set $g:name [dl_slist ball]
        dl_set $g:shape [dl_slist Circle]
        dl_set $g:type $b2_staticBody
        dl_set $g:tx [dl_flist $params(ball_xpos)]
        dl_set $g:ty [dl_flist $params(ball_ypos)]
        dl_set $g:sx [dl_flist $params(ball_radius)]
        dl_set $g:sy [dl_flist $params(ball_radius)]
        dl_set $g:angle [dl_flist 0.0]
        dl_set $g:restitution [dl_flist $params(ball_restitution)]

        return $g
    }

    proc create_catcher_dg { tx ty name } {
        variable params
        set b2_staticBody 0

        set y [expr $ty-(0.5+0.5/2)]

        set g [dg_create]

        dl_set $g:id [dl_ilist]
        dl_set $g:name [dl_slist ${name}_b ${name}_r ${name}_l]
        dl_set $g:shape [dl_repeat [dl_slist Box] 3]
        dl_set $g:type [dl_repeat $b2_staticBody 3]
        dl_set $g:tx [dl_flist $tx [expr {$tx+2.5}] [expr {$tx-2.5}]]
        dl_set $g:ty [dl_flist $y $ty $ty]
        dl_set $g:sx [dl_flist 5 0.5 0.5]
        dl_set $g:sy [dl_flist 0.5 2 2]
        dl_set $g:angle [dl_zeros 3.]
        dl_set $g:restitution [dl_float [dl_repeat $params(catcher_restitution) 3]]

        return $g
    }

    proc create_floor_dg { tx ty name } {
        set b2_staticBody 0

        set w 16
        set y [expr $ty-(0.5+0.5/2)]

        set g [dg_create]

        dl_set $g:id [dl_ilist]
        dl_set $g:name [dl_slist ${name}]
        dl_set $g:shape [dl_slist Box]
        dl_set $g:type $b2_staticBody
        dl_set $g:tx [dl_flist $tx]
        dl_set $g:ty [dl_flist $y]
        dl_set $g:sx [dl_flist $w]
        dl_set $g:sy [dl_flist 0.5]
        dl_set $g:angle [dl_zeros 1.]
        dl_set $g:restitution [dl_zeros 1.]

        return $g
    }

    proc create_plank_dg {} {
        variable params
        set b2_staticBody 0

        set n $params(nplanks)
        set xrange $params(xrange)
        set xrange_2 [expr {$xrange/2}]
        set yrange $params(yrange)
        set yrange_2 [expr {$yrange/2}]

        set g [dg_create]

        # These params control spacing of plank centers (they must be floats)
        set min_dist $params(planks_min_dist)
        set max_x $params(planks_max_x)
        set max_y $params(planks_max_y)
        set offset_y $params(planks_offset_y)
        dl_local ecc 4.0
        dl_local anchor [dl_llist [dl_flist $params(ball_xpos) $params(ball_ypos)]]

        # Randomly pick points for centers with above constraints
        dl_local plank_pos [::points::pickpointsAwayFrom $n [dl_llist [dl_pack [dl_flist]]] $min_dist $max_x $max_y $ecc $anchor]

        # pull out the tx and ty from the packed dists_pos list
        dl_local tx [dl_first [dl_unpack [dl_choose $plank_pos [dl_llist [dl_llist 0]]]]]
        dl_local ty [dl_first [dl_unpack [dl_choose $plank_pos [dl_llist [dl_llist 1]]]]]
        dl_local ty [dl_add $offset_y $ty]

        dl_set $g:id [dl_ilist]
        dl_set $g:name [dl_paste [dl_repeat [dl_slist plank] $n] [dl_fromto 0 $n]]
        dl_set $g:shape [dl_repeat [dl_slist Box] $n]
        dl_set $g:type [dl_repeat $b2_staticBody $n]
        dl_set $g:tx $tx
        dl_set $g:ty $ty

        set range [expr $params(planks_max_len)-$params(planks_min_len)]
        dl_local plank_lengths [dl_add $params(planks_min_len) [dl_mult $range [dl_urand $n]]]
        dl_set $g:sx $plank_lengths
        dl_set $g:sy [dl_repeat .5 $n]
        dl_set $g:angle [dl_mult 2 $::pi [dl_urand $n]]
        dl_set $g:restitution [dl_float [dl_repeat $params(plank_restitution) $n]]

        return $g
    }

    proc make_world {} {
        variable params
        set planks [create_plank_dg]

        set ball [create_ball_dg]

        if { !$params(floor_only) } {
            set left_catcher [create_catcher_dg $params(lcatcher_x) $params(lcatcher_y) catchl]
            set right_catcher [create_catcher_dg $params(rcatcher_x) $params(rcatcher_y) catchr]
            set parts "$ball $left_catcher $right_catcher"
        } else {
            set floor [create_floor_dg 0 $params(rcatcher_y) floor]
            set parts "$ball $floor"
        }
        foreach p $parts {
            dg_append $planks $p
            dg_delete $p
        }
        return $planks
    }

    proc build_world { dg } {
        # Create the world
        set world [box2d::createWorld]

        set n [dl_length $dg:name]

        # load in objects
        for { set i 0 } { $i < $n } { incr i } {
            foreach v "name shape type tx ty sx sy angle restitution" {
                set $v [dl_get $dg:$v $i]
            }

            if { $shape == "Box" } {
                set body [box2d::createBox $world $name $type $tx $ty $sx $sy $angle]
            } elseif { $shape == "Circle" } {
                set body [box2d::createCircle $world $name $type $tx $ty $sx]
            }
            box2d::setRestitution $world $body $restitution

            # will return ball handle
            if { $name == "ball" } {
                set ball $body
            }
        }

        # create a dynamic circle
        return "$world $ball"
    }

    proc test_simulation { world ball { simtime 6 } } {
        set g [dg_create]
        dl_set $g:t [dl_flist]
        dl_set $g:x [dl_flist]
        dl_set $g:y [dl_flist]
        dl_set $g:contact_bodies [dl_slist]
        dl_set $g:contact_t [dl_flist]

        variable params
        box2d::setBodyType $world $ball 2
        set step $params(step_size)
        set nsteps [expr {int(ceil($simtime/$step))}]
        set contacts {}
        for { set t 0 } { $t < $simtime } { set t [expr $t+$step] } {
            box2d::step $world $step
            if { [set c [box2d::getContactBeginEventCount $world]] } {
                set events [box2d::getContactBeginEvents $world]
                for { set i 0 } { $i < $c } { incr i } {
                    dl_append $g:contact_t $t
                    dl_append $g:contact_bodies [lindex $events $i]
                }
            }
            lassign [box2d::getBodyInfo $world $ball] tx ty a
            dl_append $g:t $t
            dl_append $g:x $tx
            dl_append $g:y $ty
        }
        return $g
    }

    proc isPlank { pair } { return [string match plank* [lindex $pair 0]] }

    proc isCatcherBottom { pair } {
        return [string match catch*_b [lindex $pair 0]]
    }

    proc uniqueList {list} {
        set new {}
        foreach item $list {
            if {$item ni $new} {
                lappend new $item
            }
        }
        return $new
    }

    proc accept_board { g } {
        variable params

        set x [dl_last $g:x]
        set y [dl_last $g:y]
        set contact_times [dl_tcllist $g:contact_t]
        set contacts [dl_tcllist $g:contact_bodies]

        set first_catcher ""
        set land_time ""

        set idx 0
        foreach c $contacts {
            if {[isCatcherBottom $c]} {
                set first_catcher [lindex [lindex $c 0] 0]
                set land_time [lindex $contact_times $idx]
                break
            }
            incr idx
        }

        if {$first_catcher eq ""} {
            return [dict create result -1 nhit 0 land_time {}]
        }

        if {$first_catcher eq "catchl_b"} {
            set result 0
        } elseif {$first_catcher eq "catchr_b"} {
            set result 1
        } else {
            return [dict create result -1 nhit 0 land_time {}]
        }

        set planks [lmap c $contacts {
            expr {[isPlank $c] ? [lindex [lindex $c 0] 0] : [continue]}
        }]
        set planks [uniqueList $planks]
        set nhit [llength $planks]

        if {$nhit < $params(minplanks)} {
            return [dict create result -1 nhit $nhit land_time {}]
        }

        return [dict create result $result nhit $nhit land_time $land_time]
    }

    proc generate_world { accept_proc } {
        variable params
        set done 0
        while { !$done } {
            # allow jitter for ball start before making world
            set params(ball_xpos) [expr { $params(ball_start_x) +
                rand()*$params(ball_jitter_x) -
                0.5*$params(ball_jitter_x) } ]
            set params(ball_ypos) [expr { $params(ball_start_y) +
                rand()*$params(ball_jitter_y) -
                0.5*$params(ball_jitter_y) } ]

            set new_world [make_world]

            lassign [build_world $new_world] world ball

            set sim_dg [test_simulation $world $ball]
            set outcome [$accept_proc $sim_dg]
            set result [dict get $outcome result]
            set nhit [dict get $outcome nhit]
            set land_time [dict get $outcome land_time]

            if { $result != -1 } {
                dl_set $new_world:side [dl_ilist $result]
                dl_set $new_world:nhit [dl_ilist $nhit]
                dl_set $new_world:land_time [dl_flist $land_time]
                dl_set $new_world:nplanks [dl_ilist $params(nplanks)]
                dl_set $new_world:ball_start_x [dl_flist $params(ball_xpos)]
                dl_set $new_world:ball_start_y [dl_flist $params(ball_ypos)]
                dl_set $new_world:ball_radius [dl_flist $params(ball_radius)]
                dl_set $new_world:ball_restitution [dl_flist $params(ball_restitution)]
                dl_set $new_world:plank_restitution [dl_flist $params(plank_restitution)]
                dl_set $new_world:lcatcher_x [dl_flist $params(lcatcher_x)]
                dl_set $new_world:lcatcher_y [dl_flist $params(lcatcher_y)]
                dl_set $new_world:rcatcher_x [dl_flist $params(rcatcher_x)]
                dl_set $new_world:rcatcher_y [dl_flist $params(rcatcher_y)]
                dl_set $new_world:ball_t $sim_dg:t
                dl_set $new_world:ball_x $sim_dg:x
                dl_set $new_world:ball_y $sim_dg:y
                dl_set $new_world:contact_t $sim_dg:contact_t
                dl_set $new_world:contact_bodies $sim_dg:contact_bodies
                dg_delete $sim_dg

                box2d::destroy $world
                return $new_world
            } else {
                dg_delete $sim_dg
                dg_delete $new_world
                box2d::destroy $world
            }
        }
    }

    proc pack_world { g } {
        # these are columns that are lists for each world
        set cols "name shape type tx ty sx sy angle restitution ball_t ball_x ball_y contact_t contact_bodies"

        # put the lists into a list of lists so we can append worlds together
        foreach c $cols {
            dl_set $g:$c [dl_llist $g:$c]
        }
        return $g
    }

    # Utility procedures for debugging and testing
    proc benchmark_generation { n d {iterations 3} } {
        puts "Benchmarking world generation: $n worlds, $iterations iterations"

        set serial_times {}
        set parallel_times {}

        # Test serial generation
        disable_threading
        for {set i 0} {$i < $iterations} {incr i} {
            puts "Running serial iteration [expr {$i+1}]..."
            set start [clock milliseconds]
            set worlds [generate_worlds $n $d]
            set elapsed [expr {[clock milliseconds] - $start}]
            lappend serial_times $elapsed
            if {$worlds ne ""} {
                dg_delete $worlds
            }
            puts "Serial iteration [expr {$i+1}]: ${elapsed}ms"
        }

        # Test parallel generation if threading is available
        if {[enable_threading]} {
            for {set i 0} {$i < $iterations} {incr i} {
                puts "Running parallel iteration [expr {$i+1}]..."
                set start [clock milliseconds]
                set worlds [generate_worlds $n $d]
                set elapsed [expr {[clock milliseconds] - $start}]
                lappend parallel_times $elapsed
                if {$worlds ne ""} {
                    dg_delete $worlds
                }
                puts "Parallel iteration [expr {$i+1}]: ${elapsed}ms"
            }

            # Calculate and display results
            set avg_serial [expr {[tcl::mathop::+ {*}$serial_times] / double([llength $serial_times])}]
            set avg_parallel [expr {[tcl::mathop::+ {*}$parallel_times] / double([llength $parallel_times])}]
            set speedup [expr {$avg_serial / $avg_parallel}]

            puts "\n=== BENCHMARK RESULTS ==="
            puts "Average serial time: [format %.1f $avg_serial]ms"
            puts "Average parallel time: [format %.1f $avg_parallel]ms"
            puts "Speedup: [format %.2f $speedup]x"
            puts "Threading info: [get_threading_info]"
        } else {
            puts "\nThreading not available for comparison"
            set avg_serial [expr {[tcl::mathop::+ {*}$serial_times] / double([llength $serial_times])}]
            puts "Average serial time: [format %.1f $avg_serial]ms"
        }
    }

    # Test procedure to validate threading works correctly
    proc test_threading { {n 20} } {
        puts "Testing threading functionality..."

        set test_params {nplanks 8 minplanks 2}

        # Generate worlds with serial mode
        disable_threading
        puts "Generating $n worlds in serial mode..."
        set start [clock milliseconds]
        set serial_worlds [generate_worlds $n $test_params]
        set serial_time [expr {[clock milliseconds] - $start}]
        set serial_count [dl_length $serial_worlds:name]

        # Generate worlds with parallel mode
        if {[enable_threading 4]} {
            puts "Generating $n worlds in parallel mode..."
            set start [clock milliseconds]
            set parallel_worlds [generate_worlds $n $test_params]
            set parallel_time [expr {[clock milliseconds] - $start}]
            set parallel_count [dl_length $parallel_worlds:name]

            puts "\n=== THREADING TEST RESULTS ==="
            puts "Serial: $serial_count worlds in ${serial_time}ms"
            puts "Parallel: $parallel_count worlds in ${parallel_time}ms"

            if {$serial_count == $parallel_count} {
                puts "✓ World count matches"
            } else {
                puts "✗ World count mismatch!"
            }

            if {$parallel_time < $serial_time} {
                set speedup [expr {double($serial_time) / $parallel_time}]
                puts "✓ Parallel faster by [format %.2f $speedup]x"
            } else {
                puts "! Parallel not faster (normal for small batches)"
            }

            # Clean up
            dg_delete $serial_worlds
            dg_delete $parallel_worlds

        } else {
            puts "Threading not available"
            dg_delete $serial_worlds
        }
    }

    #########################################################################
    # Accept Function Registry and Management
    #########################################################################

    variable accept_functions {}
    variable world_validation_cache {}

    # Register an accept function with metadata
    proc register_accept_function {name description params body {dependencies {}}} {
        variable accept_functions

        set func_info [dict create  name $name  description $description  params $params  body $body  dependencies $dependencies  created [clock seconds]]

        dict set accept_functions $name $func_info

        # Create the actual procedure in the planko namespace
        proc $name $params $body

        puts "Registered accept function: $name"
        return $name
    }

    # Get list of available accept functions
    proc get_accept_functions {} {
        variable accept_functions
        return [dict keys $accept_functions]
    }

    # Get accept function info
    proc get_accept_function_info {name} {
        variable accept_functions
        if {[dict exists $accept_functions $name]} {
            return [dict get $accept_functions $name]
        }
        return {}
    }

    #########################################################################
    # World + Parameter Combination System
    #########################################################################

    # Extract a single world from a packed collection by ID
    proc get_world {dg id} {
        set w [dg_create]
        foreach l [dg_tclListnames $dg] {
            dl_set $w:$l $dg:$l:$id
        }
        return $w
    }

    #########################################################################
    # Helper Functions
    #########################################################################

    # Helper to create a key from parameter combination dict
    proc dict_to_key {param_dict} {
        set key_parts {}
        dict for {param_name param_val} $param_dict {
            lappend key_parts "${param_name}=${param_val}"
        }
        return [join $key_parts "_"]
    }

    # Enhanced JSON conversion using yajl
    proc dict_to_json {d} {
        package require yajl
        set obj [yajl create #auto]
        $obj map_open

        dict for {k v} $d {
            $obj string $k

            # Handle different value types
            if {[string is integer $v]} {
                $obj number $v
            } elseif {[string is double $v]} {
                $obj number $v
            } elseif {[string is boolean $v]} {
                $obj bool $v
            } else {
                $obj string $v
            }
        }

        $obj map_close
        set result [$obj get]
        $obj delete
        return $result
    }

    #########################################################################
    # Register Default Accept Functions
    #########################################################################

    # Initialize default accept functions when module loads
    proc init_default_accept_functions {} {
        # Register the original accept_board function
        register_accept_function "accept_board"  "Original planko accept function - ball must land in catcher and hit minimum planks"  {g} {
            variable params

            set x [dl_last $g:x]
            set y [dl_last $g:y]
            set contact_times [dl_tcllist $g:contact_t]
            set contacts [dl_tcllist $g:contact_bodies]

            set first_catcher ""
            set land_time ""

            set idx 0
            foreach c $contacts {
                if {[isCatcherBottom $c]} {
                    set first_catcher [lindex [lindex $c 0] 0]
                    set land_time [lindex $contact_times $idx]
                    break
                }
                incr idx
            }

            if {$first_catcher eq ""} {
                return [dict create result -1 nhit 0 land_time {} reason "no_catcher_contact"]
            }

            if {$first_catcher eq "catchl_b"} {
                set result 0
            } elseif {$first_catcher eq "catchr_b"} {
                set result 1
            } else {
                return [dict create result -1 nhit 0 land_time {} reason "invalid_catcher"]
            }

            set planks [lmap c $contacts {
                expr {[isPlank $c] ? [lindex [lindex $c 0] 0] : [continue]}
            }]
            set planks [uniqueList $planks]
            set nhit [llength $planks]

            if {$nhit < $params(minplanks)} {
                return [dict create result -1 nhit $nhit land_time {} reason "insufficient_plank_hits"]
            }

            return [dict create result $result nhit $nhit land_time $land_time reason "accepted"]
        }
    }

    # Call initialization when module loads
    init_default_accept_functions

    # Update the namespace export to include new functions
    namespace export default_params create_ball_dg create_catcher_dg create_floor_dg
    namespace export create_plank_dg make_world build_world test_simulation
    namespace export accept_board generate_world pack_world generate_worlds
    namespace export enable_threading disable_threading configure_threading
    namespace export get_threading_info benchmark_generation test_threading
    namespace export register_accept_function get_accept_functions
    namespace export test_world_parameter_combinations generate_worlds_with_parameter_sweeps
}
