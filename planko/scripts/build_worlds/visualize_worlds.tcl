#
# simple example to show how to build a box2d world
#
set dlshlib [file join /usr/local/dlsh dlsh.zip]
set base [file join [zipfs root] dlsh]
if { ![file exists $base] && [file exists $dlshlib] } {
    zipfs mount $dlshlib $base
}
set ::auto_path [linsert $::auto_path [set auto_path 0] $base/lib]

package require box2d
package require dlsh
package require trajectory_analysis

proc get_box_coords { tx ty w h { a 0 } } {
    dl_local x [dl_mult $w [dl_flist -.5 .5 .5 -.5 -.5 ]]
    dl_local y [dl_mult $h [dl_flist -.5  -.5 .5 .5 -.5 ]]

    set cos_theta [expr cos($a)]
    set sin_theta [expr sin($a)]

    dl_local rotated_x [dl_sub [dl_mult $x $cos_theta] [dl_mult $y $sin_theta]]
    dl_local rotated_y [dl_add [dl_mult $y $cos_theta] [dl_mult $x $sin_theta]]

    dl_local x [dl_add $tx $rotated_x]
    dl_local y [dl_add $ty $rotated_y]

    lassign [deg_to_display $x $y] xlist ylist
    set coords [list]
    foreach a $xlist b $ylist {	lappend coords $a $b }
    return $coords
}

proc get_line_coords { tx ty r { a 0 } } {
    dl_local x [dl_flist 0 $r]
    dl_local y [dl_flist 0 0]

    set cos_theta [expr cos($a)]
    set sin_theta [expr sin($a)]

    dl_local rotated_x [dl_sub [dl_mult $x $cos_theta] [dl_mult $y $sin_theta]]
    dl_local rotated_y [dl_add [dl_mult $y $cos_theta] [dl_mult $x $sin_theta]]

    dl_local x [dl_add $tx $rotated_x]
    dl_local y [dl_add $ty $rotated_y]

    lassign [deg_to_display $x $y] xlist ylist
    set coords [list]
    foreach a $xlist b $ylist {	lappend coords $a $b }
    return $coords
}

proc show_box { name tx ty w h { a 0 } } {
    set coords [get_box_coords $tx $ty $w $h $a]
    return [$::display create polygon $coords -outline white -tag $name]
}

proc update_box { id tx ty w h { a 0 } } {
    set coords [get_box_coords $tx $ty $w $h $a]
    $::display coords $id $coords
}

proc update_ball { ball r x y a } {
    set radius [deg_to_pixels $r]
    lassign [deg_to_display $x $y] x0 y0
    $::display coords $ball \
	[expr $x0-$radius] [expr $y0-$radius] \
	[expr $x0+$radius] [expr $y0+$radius] 
    $::display coords $::ball_line [get_line_coords $x $y $r $a]
}

proc show_ball { tx ty r } {
    set radius [deg_to_pixels $r]
    set ::ball_id [$::display create oval 0 0 0 0 -outline white]
    set ::ball_line [$::display create line 0 0 $radius 0 -fill white]
    update_ball $::ball_id $r $tx $ty 0
    return $::ball_id
}

proc deg_to_pixels { x } {
    set w $::display_width
    set hrange_h $::display_hrange_h 
    return [expr $x*$w/(2*$hrange_h)]
}

proc deg_to_display { x y } {
    set w $::display_width
    set h $::display_height
    set hrange_h $::display_hrange_h
    set aspect [expr {1.0*$h/$w}]
    set hrange_v [expr $hrange_h*$aspect]
    set hw [expr $w/2]
    set hh [expr $h/2]
    dl_local x0 [dl_add [dl_mult [dl_div $x $hrange_h] $hw] $hw]
    dl_local y0 [dl_sub $hh [dl_mult [dl_div $y $hrange_v] $hh]]
    return [list [dl_tcllist $x0] [dl_tcllist $y0]]
}

proc get_world { dg id } {
    set w [dg_create]
    foreach l [dg_tclListnames $dg] {
	dl_set $w:$l $dg:$l:$id
    }
    return $w
}

proc build_world { dg } {
    
    # create the world
    set world [box2d::createWorld]

    set ::planks     {}
    set ::plank_ids  {}
    set ::plank_dims {}
    set ::plank_xys  {}

    set n [dl_length $dg:name]
    
    # load in objects
    for { set i 0 } { $i < $n } { incr i } {
	foreach v "name shape type tx ty sx sy angle restitution" {
	    set $v [dl_get $dg:$v $i]
	}

	if { $shape == "Box" } {
	    set body [box2d::createBox $world $name $type $tx $ty $sx $sy $angle]
	    set id [show_box $name $tx $ty $sx $sy $angle]
	} elseif { $shape == "Circle" } {
	    set body [box2d::createCircle $world $name $type $tx $ty $sx]
	    set id [show_ball $tx $ty $sx]
	}
	box2d::setRestitution $world $body $restitution

	# ball handles are returned
	if { $name == "ball" } {
	    set ball $body
	    set ball_id $id
	}

	if { [string match plank* $name] } {
	    lappend ::planks $body
	    lappend ::plank_ids $id
	    lappend ::plank_dims [list $sx $sy]
	    lappend ::plank_xys [list $tx $ty]
	}
    }
  
    # create a dynamic circle
    return "$world $ball $ball_id"
}

proc test_simulation { { simtime 6 } } {
    global params world ball ball_id
    box2d::setBodyType $world $ball 2    
    set step 0.0167
    set nsteps [expr {int(ceil(6.0/$step))}]
    set contacts {}
    for { set t 0 } { $t < $simtime } { set t [expr $t+$step] } {
	box2d::step $world $step
        if { [box2d::getContactBeginEventCount $world] } { 
	    lappend contacts [box2d::getContactBeginEvents $world]
        }
    }
    lassign [box2d::getBodyInfo $world $ball] tx ty a
    box2d::setTransform $world $ball 0 $params(ball_start)
    box2d::setBodyType $world $ball 0
    return  "$tx $ty [list $contacts]"
}


proc add_t_stats { x y ts ps { alpha 0.01 } } {
    global display
    lassign [deg_to_display $x $y] xpix ypix
    lassign $ts t_x t_y t_angle
    lassign $ps p_x p_y p_angle
    set t_x [expr abs($t_x)]
    set t_y [expr abs($t_y)]
    set t_angle [expr abs($t_angle)]
    if { $p_x < $alpha ||
	 $p_y < $alpha ||
	 $p_angle < $alpha } {
	set t_info [format "%.1f %.1f %.1f" $t_x $t_y $t_angle]
	$display create text $xpix $ypix -text $t_info -anchor c -fill white -font "Arial 12"
    }
}

proc add_board_info { worlds jitters id } {
    global display
    
    # Define some variables
    set x_start 20
    set y_start 30
    set y_increment 25
    set bullet_char "•"
    set indent 15
    
    # Create bulleted items
    set items {
	"Board: $id"
    }
    
    set items [subst $items]
    
    set y $y_start
    foreach item $items {
	# Add the bullet
	$display create text $x_start $y -text $bullet_char -anchor w -fill white -font "Arial 14"
	
	# Add the text, indented after the bullet
	$display create text [expr {$x_start + $indent}] $y -text $item \
	    -anchor w -width 350 -fill white -font "Arial 14"
	
	# Move to next line
	incr y $y_increment
    }
}


proc add_jitter_trajs { worlds jitters id { n 100 } } {
    set xs $jitters:x:$id
    set ys $jitters:y:$id
    set n [dl_length $xs]
    dl_local subset [dl_choose [dl_randfill $n] [dl_fromto 0 $n]]

    for { set i 0 } { $i < $n } { incr i } {
	set nc [dl_length $xs:$i]
	set coords {}
	lassign [deg_to_display $xs:$i $ys:$i] xlist ylist
	foreach a $xlist b $ylist { lappend coords $a $b }
	$::display create line $coords -fill magenta -tag jitter_traj
    }
}

proc remove_jitter_trajs {} {
    $::display delete jitter_traj
}

proc add_trajectory_peaks { worlds jitters id } {
    dl_local traj [dl_transpose [dl_llist $jitters:x:$id $jitters:y:$id]]
    set g [trajectory_analyze $traj]
    set npeaks [dl_length $g:peaks_x]
    for { set i 0 } { $i < $npeaks } { incr i } {
	set radius [expr {[dl_get $g:peak_values $i]*200.}]
	set x [dl_get $g:peaks_x $i]
	set y [dl_get $g:peaks_y $i]
	lassign [deg_to_display $x $y] x0 y0
	$::display create oval [expr $x0-$radius] [expr $y0-$radius] \
	    [expr $x0+$radius] [expr $y0+$radius]  -outline red
    }
}

proc run_simulation { worlds jitters id } {
    global done world ball ball_id display
    set done 0

    $display delete all
    box2d::destroy all

    set new_world [get_world $worlds $id]
    lassign [build_world $new_world] ::world ::ball ::ball_id
    dg_delete $new_world

    add_jitter_trajs $worlds $jitters $id
    remove_jitter_trajs
    
    add_trajectory_peaks $worlds $jitters $id

    add_board_info $worlds $jitters $id
    
    update
    
    while !$::done { 
    	after 20
    	box2d::step $world .0167

	foreach p $::planks id $::plank_ids dims $::plank_dims {
	    lassign [box2d::getBodyInfo $world $p] tx ty a
	    update_box $id $tx $ty {*}$dims $a
	}
	
    	lassign [box2d::getBodyInfo $world $ball] tx ty a
    	update_ball $ball_id .5 $tx $ty $a
    	update
    }
}

set worlds [dg_read worlds]
set jitters [dg_read ball_jitters]
set cur_world 0
set max_worlds [dl_length $worlds:name]

set display_width 1024
set display_height 600
set display_hrange_h 17.7
set display [canvas .c -width $display_width -height $display_height -background black]
pack $display
wm protocol . WM_DELETE_WINDOW { set ::done 1; exit }

bind . <Right> {
    incr ::cur_world;
    if { $::cur_world >= $max_worlds } {
	set ::cur_world [expr $max_worlds-1]
    };
    set ::done 1;
    run_simulation $::worlds $::jitters $::cur_world
}
bind . <Left> {
    incr ::cur_world -1;
    if { $::cur_world < 0 } {
	set ::cur_world 0
    };
    set ::done 1;
    run_simulation $::worlds $::jitters $::cur_world
}
bind . <Down> { box2d::setBodyType $::world $::ball 2 }
bind . <Escape> { set ::done 1; exit }
bind . <J> { add_jitter_trajs $::worlds $::jitters $::cur_world }
bind . <j> { remove_jitter_trajs }

run_simulation $::worlds $::jitters $::cur_world
