# -*- mode: tcl -*-

#
# planko-3.0.tm
#   Enhanced package for generating planko boards with threading support
#

puts "loading planko package"

package provide planko 3.0

package require box2d
package require dlsh
package require points

namespace eval planko {
    variable params
    variable compute_host ""    
    variable use_threading 0
    variable num_threads 4
    variable min_threading_batch 4

    # Thread-local world tracking
    variable thread_worlds {}

    # Detect number of CPUs available
    proc detect_num_cpus {{physical false}} {
	if {$physical} {
	    # Linux ARM: count physical cores via sysfs
	    set core_ids [list]
	    foreach cpu [glob -nocomplain /sys/devices/system/cpu/cpu\[0-9\]*/topology/core_id] {
		set f [open $cpu r]
		set id [string trim [read $f]]
		close $f
		if {$id ni $core_ids} { lappend core_ids $id }
	    }
	    set count [llength $core_ids]
	    if {$count > 0} { return $count }
	    
	    # Linux: count physical cores
	    if {[file exists /proc/cpuinfo]} {
		set f [open /proc/cpuinfo r]
		set data [read $f]
		close $f
		# Count unique physical id + core id combinations
		set cores [dict create]
		set phys_id 0
		set core_id 0
		foreach line [split $data "\n"] {
		    if {[regexp {^physical id\s*:\s*(\d+)} $line -> id]} {
			set phys_id $id
		    } elseif {[regexp {^core id\s*:\s*(\d+)} $line -> id]} {
			set core_id $id
			dict set cores "$phys_id:$core_id" 1
		    }
		}
		set count [dict size $cores]
		if {$count > 0} { return $count }
	    }
	    # macOS
	    if {![catch {exec sysctl -n hw.physicalcpu} result]} {
		if {[string is integer -strict $result] && $result > 0} {
		    return $result
		}
	    }
	}
	
        # Try nproc command first (most reliable on Linux)
        if {![catch {exec nproc} result]} {
            if {[string is integer -strict $result] && $result > 0} {
                return $result
            }
        }
	
        # Try Linux /proc/cpuinfo
        if {[file exists /proc/cpuinfo]} {
            set f [open /proc/cpuinfo r]
            set data [read $f]
            close $f
            set count [llength [regexp -all -inline -line {^processor\s*:} $data]]
            if {$count > 0} { return $count }
        }
        
        # Try sysctl (macOS/BSD)
        if {![catch {exec sysctl -n hw.ncpu} result]} {
            if {[string is integer -strict $result] && $result > 0} {
                return $result
            }
        }
        
        # Default fallback
        return 4
    }

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
        set params(accept_proc) accept_board
        return
    }

    # Threading configuration and management
    proc enable_threading { { threads {} } } {
        variable use_threading
        variable num_threads

        if {$threads eq {}} {
            set threads [detect_num_cpus]
        }
		     
        if {[catch {package require Thread}]} {
            puts "Warning: Thread package not available, falling back to serial generation"
            set use_threading 0
            return 0
        }

        set use_threading 1
        set num_threads $threads
        puts "Threading enabled with $num_threads threads (detected [detect_num_cpus] CPUs)"
        return 1
    }

    proc disable_threading {} {
        variable use_threading
        set use_threading 0
        puts "Threading disabled"
    }

    proc get_threading_info {} {
        variable use_threading
        variable num_threads
        variable min_threading_batch

        return [dict create enabled $use_threading threads $num_threads min_batch $min_threading_batch]
    }

    proc set_compute_host { host } {
        variable compute_host
        set compute_host $host
    }
        
    proc create_worker_script {} {
	return {
	    set ::planko_worker_thread 1
	    
	    # Setup worker thread environment (same as before)
	    set dlshlib [file join /usr/local/dlsh dlsh.zip]
	    set base [file join [zipfs root] dlsh]
	    set ::auto_path [linsert $::auto_path [set auto_path 0] $base/lib]
	    
	    if { [info exists ::env(ESS_SYSTEM_PATH)] } {
		tcl::tm::path add $::env(ESS_SYSTEM_PATH)/ess/lib
	    }
	    package require planko
	    
	    proc do_planko_work { n d worker_id } {
		puts "Worker $worker_id starting generation of $n worlds"
		
		set result [catch {
		    set g [planko::generate_worlds_serial $n $d]
		    dg_toString $g temp_result
		    set ::result_string $temp_result
		    dg_delete $g
		    puts "Worker $worker_id completed $n worlds successfully"
		} work_error]
		
		if {$result != 0} {
		    puts "ERROR in worker $worker_id: $work_error"
		    set ::result_string "ERROR: $work_error"
		    return "ERROR: $work_error"
		}
		
		return "SUCCESS"
	    }
	    thread::wait
	}
    }

    proc generate_worlds_serialized { n d } {
	variable use_threading
	variable min_threading_batch
	
	if {$use_threading && $n >= $min_threading_batch} {
	    set g [generate_worlds_parallel $n $d]
	    puts "created parallelized worlds"
	} else {
	    set g [generate_worlds_serial $n $d]
	    puts "created serialized worlds"
	}

	# put serialized dg into the variable "result"
	dg_toString64 $g result
	dg_delete $g  ;# clean up on remote
	return $result
    }
    
    proc generate_worlds_remote { n d } {
	variable compute_host
	
	# Remote system will auto-detect its own CPU count
	set ess_script [subst {
	    package require planko
	    planko::detect_num_cpus
	    planko::generate_worlds_serialized $n [list $d]
	}]
	
	set data [remoteEval $compute_host "send ess [list $ess_script]"]
	return [dg_fromString64 $data]
    }
    
    proc generate_worlds_parallel { n d } {
	variable num_threads
	
	if {$n < $num_threads * 2} {
	    return [generate_worlds_serial $n $d]
	}
	
	puts "Generating $n worlds using $num_threads threads"
	
	# Distribute work
	set worlds_per_thread [expr {$n / $num_threads}]
	set remainder [expr {$n % $num_threads}]
	
	set threads {}
	set thread_work {}
	
	# Create threads and assign work
	for {set i 0} {$i < $num_threads} {incr i} {
	    set thread_n $worlds_per_thread
	    if {$i < $remainder} {incr thread_n}
	    
	    if {$thread_n > 0} {
		set tid [thread::create [create_worker_script]]
		lappend threads $tid
		lappend thread_work [list $thread_n $d $i]
	    }
	}
	
	# Start all work asynchronously
	for {set i 0} {$i < [llength $threads]} {incr i} {
	    set tid [lindex $threads $i]
	    lassign [lindex $thread_work $i] thread_n thread_d worker_id
	    
	    # Start work without waiting - all threads begin immediately
	    thread::send -async $tid [list do_planko_work $thread_n $thread_d $worker_id]
	}
	
	# Collect results (blocks on any thread still working)
	set all_worlds ""
	set successful_threads 0
	
	for {set i 0} {$i < [llength $threads]} {incr i} {
	    set tid [lindex $threads $i]
	    
	    if {[catch {
		# Get the return value from the async call
		set thread_result [thread::send $tid {set ::result_string}]
		
		if {$thread_result ne "" && ![string match "ERROR:*" $thread_result]} {
		    set unique_name "temp_${tid}_[clock microseconds]"
		    set g [safe_dg_fromString $thread_result $unique_name]
		    
		    if {$all_worlds eq ""} {
			set all_worlds $g
		    } else {
			if {[catch {dg_append $all_worlds $g} append_error]} {
			    puts "Error appending data from thread $tid: $append_error"
			} else {
			    dg_delete $g
			}
		    }
		    incr successful_threads
		} else {
		    puts "Thread $tid failed: $thread_result"
		}
	    } result_error]} {
		puts "Error collecting from thread $tid: $result_error"
	    }
	    
	    thread::release $tid
	}
	
	puts "Parallel generation: $successful_threads/[llength $threads] threads successful"
	
	# Final processing
	if {$all_worlds ne ""} {
	    set total_worlds [dl_length $all_worlds:name]
	    dl_set $all_worlds:id [dl_fromto 0 $total_worlds]
	    puts "Parallel generation complete: $total_worlds worlds generated"
	}
	
	return $all_worlds
    }
    
    proc update_world { w d } {
	variable params
	# for now, just handle plank_restitution, but this need to be expanded
	dict for { k v } $d {
	    if { $k == "plank_restitution" } {
		dl_set $w:restitution [dl_replace $w:restitution [dl_regmatch $w:name plank*] $v]
		dl_set $w:plank_restitution [dl_flist $v]
	    }
	}
    }
    
    # Serial world generation
    proc generate_worlds_serial_multi { n d } {
        variable params

	set results {}
	
	if { ![dict exists $d multi_settings] } { return }

	# add dictionary defaults and then d for all worlds
        default_params
        dict for { k v } $d { set params($k) $v }

	# now update params with first of multi_settings
	set initial_settings [lindex $params(multi_settings) 0]
	dict for { k v } $initial_settings { set params($k) $v }

	set nsettings [llength $params(multi_settings)]

	set total_worlds 0
	
        for { set i 0 } { $i < $n } { } {

	    set done 0	
	    while { !$done } {
		set worlds(0) [generate_world]
		dl_set $worlds(0):world_id $i

		# if we can't create a satisfactory world, clean up and return
		if { $worlds(0) == "" } {
		    if { $results != "" } {
			dg_delete $results
		    }
		    return
		}

		# now pass a copy of the world with setting updates to verify
		for { set j 1 } { $j < $nsettings } { incr j } {
		    set msetting [lindex $params(multi_settings) $j]
		    set worlds($j) [verify_world $worlds(0) $msetting]
		    if { $worlds($j) == "" } {
			foreach k [array names worlds] {
			    if { $worlds($k) != "" } { dg_delete $worlds($k) }
			}
			unset worlds
			break
		    }
		    dl_set $worlds($j):world_id $i
		}

		if { [info exists worlds] } { 
		    set done 1
		}
	    }

	    # store resulting worlds
	    foreach k [array names worlds] {
		if { $results == "" } {
		    set results [pack_world $worlds($k)]
		} else {
		    set w [pack_world $worlds($k)]
		    dg_append $results $w
		    dg_delete $w
		}
		incr total_worlds
	    }
	    incr i
	}

        # first column is id - set to unique ids between 0 and n
        dl_set $results:id [dl_fromto 0 $total_worlds]

        return $results
    }
    
    proc generate_worlds_serial { n d } {
        variable params
        default_params

	# multi_settings means we have multiple criteria for acceptable worlds
	if { [dict exists $d multi_settings] } {
	    return [generate_worlds_serial_multi $n $d]
	}
	    
	# add dictionary defaults and then update with multi_settings:0 if present
        dict for { k v } $d { set params($k) $v }
	
        set worlds [pack_world [generate_world]]
        for { set i 1 } { $i < $n } { incr i } {
            set world [pack_world [generate_world]]
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
	variable compute_host
        variable use_threading
        variable min_threading_batch

        if { $compute_host ne "" } {
            return [generate_worlds_remote $n $d]
        } elseif { $use_threading && $n >= $min_threading_batch } {
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
	dl_set $g:visible [dl_ilist 1]
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
	dl_set $g:visible [dl_repeat [dl_ilist 1] 3]
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
	dl_set $g:visible [dl_ilist 1]
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
	dl_set $g:visible [dl_ones $n]
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
	    if { [dl_exists $dg:visible] } {
		set visible [dl_get $dg:visible $i]
	    } else {
		set visible 1
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

    proc generate_world {} {
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
            set outcome [$params(accept_proc) $sim_dg]
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

    # see if this world works with settings in dictionary d
    proc verify_world { w d } {
        variable params
        set new_world [dg_copy $w]

	# change the world to reflect criteria in d being tested
	update_world $new_world $d

	# create the world for simulation
        lassign [build_world $new_world] world ball

        set sim_dg [test_simulation $world $ball]
        set outcome [$params(accept_proc) $sim_dg]
        set result [dict get $outcome result]
        set nhit [dict get $outcome nhit]
        set land_time [dict get $outcome land_time]
        
        if { $result != -1 } {
            dl_set $new_world:side [dl_ilist $result]
            dl_set $new_world:nhit [dl_ilist $nhit]
            dl_set $new_world:land_time [dl_flist $land_time]

	    # most settings come from original world
	    
            dl_set $new_world:ball_t $sim_dg:t
            dl_set $new_world:ball_x $sim_dg:x
            dl_set $new_world:ball_y $sim_dg:y
            dl_set $new_world:contact_t $sim_dg:contact_t
            dl_set $new_world:contact_bodies $sim_dg:contact_bodies
            dg_delete $sim_dg
            
            box2d::destroy $world
            return $new_world
        } else {
            dg_delete $new_world
            box2d::destroy $world
            return
        }
    }

    proc pack_world { g } {
        # these are columns that are lists for each world
        set cols "name shape visible type tx ty sx sy angle restitution ball_t ball_x ball_y contact_t contact_bodies"

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
        if {[enable_threading]} {
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

        set func_info [dict create name $name description $description params $params body $body dependencies $dependencies created [clock seconds]]

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
        register_accept_function "accept_board" "Original planko accept function - ball must land in catcher and hit minimum planks" {g} {
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
    namespace export generate_world pack_world generate_worlds
    namespace export enable_threading disable_threading configure_threading
    namespace export get_threading_info benchmark_generation test_threading
    namespace export register_accept_function get_accept_functions
    namespace export test_world_parameter_combinations generate_worlds_with_parameter_sweeps
}

#########################################################################
# Visualization Helper Functions
#########################################################################

namespace eval planko {
    
    proc show_trial { trial { show_traj 0 } } {
	set g stimdg
	set w [get_world $g $trial]
	
	clearwin

	# Setup the viewport to be the middle of the original display
	setwindow -16 -12 16 12
	
	show_world $w $trial

	if { $show_traj } {
	    dlg_markers $g:ball_x:${trial} $g:ball_y:${trial} \
		-marker fcircle -size 0.5x -color [dlg_rgbcolor 180 190 180]
	}

	dg_delete $w
    }

    proc get_world { dg trial } {
	set w [dg_create]
	set vars "name shape visible type tx ty sx sy angle restitution contact_t contact_bodies ball_t ball_x ball_y"
	foreach l $vars {
	    dl_set $w:$l $dg:$l:$trial
	}
	
	foreach v "side nhit nplanks ball_start_x \
    	    	   ball_start_y ball_radius ball_restitution \
                   lcatcher_x lcatcher_y rcatcher_x rcatcher_y" {
	    dl_set $w:$v [dl_flist [dl_get $dg:$v $trial]]
	}
	return $w
    }

    proc show_world { w trial } {
	global nworld floor blocks sphere
	set nbodies [dl_length $w:type]
	
	for { set i 0 } { $i < $nbodies } { incr i } {
	    set name [dl_get $w:name $i]
	    set sx [dl_get $w:sx $i]
	    set sy [dl_get $w:sy $i]
	    set tx [dl_get $w:tx $i]
	    set ty [dl_get $w:ty $i]
	    set color_r 255
	    set color_g 255
	    set color_b 255
	    set angle [dl_get $w:angle $i]
	    
	    
	    if { [dl_get $w:shape $i] == "Box" } {
		set body [show_box $name $tx $ty $sx $sy $angle]
	    } elseif { [dl_get $w:shape $i] == "Circle" } {
		if { [dl_exists stimdg:ball_color] } {
		    lassign [dl_get stimdg:ball_color $trial] r g b
		    set r [expr {int($r*255)}]
		    set g [expr {int($g*255)}]
		    set b [expr {int($b*255)}]
		} else {
		    lassign "0 255 255" r g b
		}
		set color [dlg_rgbcolor $r $g $b]
		set body [show_sphere $name $tx $ty $sx $sy $color]
	    }
	}
    }
    
    proc show_box { name tx ty sx sy angle } {
	
	dl_local x [dl_mult $sx [dl_flist -.5 .5 .5 -.5 -.5 ]]
	dl_local y [dl_mult $sy [dl_flist -.5  -.5 .5 .5 -.5 ]]
	
	set cos_theta [expr cos($angle)]
	set sin_theta [expr sin($angle)]
	
	dl_local rotated_x [dl_sub [dl_mult $x $cos_theta] [dl_mult $y $sin_theta]]
	dl_local rotated_y [dl_add [dl_mult $y $cos_theta] [dl_mult $x $sin_theta]]
	
	dl_local x [dl_add $tx $rotated_x]
	dl_local y [dl_add $ty $rotated_y]
	
	dlg_lines $x $y  -fillcolor 7 -linecolor 7
    }
    
    proc show_sphere { name tx ty sx sy color } {
	dlg_markers $tx $ty fcircle -size $sx -scaletype x -color $color
    }

    proc highlight_catcher { trial response { feedback 0 } } {
	set side [expr {$response-1}]
	if { $side == 0 } {
	    set cx [dl_get stimdg:lcatcher_x $trial]
	    set cy [dl_get stimdg:lcatcher_y $trial]
	} else {
	    set cx [dl_get stimdg:rcatcher_x $trial]
	    set cy [dl_get stimdg:rcatcher_y $trial]
	}
	set sx 3
	set sy .25
	set tx $cx
	set ty [expr $cy-1.25]
	dl_local x [dl_mult $sx [dl_flist -.5 .5 .5 -.5 -.5 ]]
	dl_local y [dl_mult $sy [dl_flist -.5  -.5 .5 .5 -.5 ]]
	dl_local x [dl_add $tx $x]
	dl_local y [dl_add $ty $y]
	if { $feedback } {
	    if { $side == [dl_get stimdg:side $trial] } {
		set color [dlg_rgbcolor 10 200 10]
	    } else {
		set color [dlg_rgbcolor 230 10 10]
	    }
	} else {
	    set color [dlg_rgbcolor 200 200 200]
	}
	
	dlg_lines $x $y -fillcolor $color -linecolor $color
    }
}    

# Ensure Thread package is loaded before using planko with threading
# Only initialize threading in the main thread, not in worker threads
if {![info exists ::planko_worker_thread]} {
    if {[catch {package require Thread} err]} {
        puts "Warning: Thread package not available: $err"
        planko::disable_threading
    } else {
        puts "Thread package loaded successfully"
        planko::enable_threading
    }
}

