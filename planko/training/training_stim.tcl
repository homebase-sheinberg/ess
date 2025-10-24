#
# STIM
#   planko_stim.tcl
#
# DESCRIPTION
#   planko task stim code
#
# REQUIRES
#   box2d
#   polygon
#   metagroup
#
# AUTHOR
#   DLS
#

package require box2d

##############################################################
###                    check_contacts                      ###
##############################################################

proc check_contacts { w } {
    if { [setObjProp $w complete] } { return }
    if { [Box2D_getContactBeginEventCount $w] > 0 } {
        set contacts [Box2D_getContactBeginEvents $w]
        foreach c $contacts {
            if { [lsearch $c catchl_b] >= 0 } {
                qpcs::dsSet $::dservhost planko/complete left
                setObjProp $w complete 1
            } elseif { [lsearch $c catchr_b] >= 0 } {
                qpcs::dsSet $::dservhost planko/complete right
                setObjProp $w complete 1
            }
        }
    }
}

##############################################################
###                    update_position                     ###
##############################################################

proc update_position { ball body start } {
    global curtrial
    set now [expr {($::StimTime-$start)/1000.}]
    set i [dl_first [dl_indices [dl_gt stimdg:ball_t:$curtrial $now]]]
    if { $i != "" } {
        set x [dl_get stimdg:ball_x:$curtrial $i]
        set y [dl_get stimdg:ball_y:$curtrial $i]
        Box2D_setTransform $::world $body $x $y
    }
    if { ![setObjProp $ball landed] } {
        if { [expr {$now > [dl_get stimdg:land_time $curtrial]}] } {
            setObjProp $ball landed 1
            set side [dl_get stimdg:side $curtrial]
            if { $side } { set hit right } { set hit left }
            qpcs::dsSet $::dservhost planko/complete $hit
        }
    }
}


##############################################################
###                     Show Worlds                        ###
##############################################################

proc make_stims { trial } {
    set dg stimdg

    set bworld [Box2D]
    glistAddObject $bworld 0
    setObjProp $bworld complete 0

    set ::left_catcher {}
    set ::right_catcher {}
    set ::planks {}

    set n [dl_length $dg:name:$trial]

    # get side and show_only_correct_side flag for this trial
    foreach v "side wrong_catcher_alpha" {
        set $v [dl_get $dg:$v $trial]
    }

    for { set i 0 } { $i < $n } { incr i } {
        foreach v "name shape type tx ty sx sy angle restitution" {
            set $v [dl_get $dg:$v:$trial $i]
        }
        if { $shape == "Box" } {
            if { $side == "0" } { set wrong_catcher catchr_* } { set wrong_catcher catchl_* }
            if { [string match $wrong_catcher $name] } { set alpha $wrong_catcher_alpha } { set alpha 1.0 }
            set body [create_box $bworld $name $type $tx $ty $sx $sy $angle [list 9. 9. 9. $alpha ]]
        } elseif { $shape == "Circle" } {
            set body [create_circle $bworld $name $type $tx $ty $sx $angle { 0 1 1 1 }]
        }
        Box2D_setRestitution $bworld [setObjProp $body body] $restitution

        glistAddObject $body 0

        # track this so we can set in motion
        if { $name == "ball" } {
            set ::ball $body
            setObjProp $body landed 0
        }

        # track catcher bodies so we can give feedback
        if { [string match catchl* $name] } { lappend ::left_catcher $body }
        if { [string match catchr* $name] } { lappend ::right_catcher $body }
        if { [string match plank* $name] } { lappend ::planks $body }
    }

    addPostScript $bworld [list check_contacts $bworld]

    glistSetDynamic 0 1
    return $bworld
}

# create a box2d body and visual box (angle is in degrees)
proc create_box { bworld name type tx ty sx sy { angle 0 } { color { 1 1 1 } } } {
    # create the box2d box
    set body [Box2D_createBox $bworld $name $type $tx $ty $sx $sy $angle]

    # make a polygon to visualize the box
    set box [make_rect]
    scaleObj $box [expr 1.0*$sx] [expr 1.0*$sy]
    translateObj $box $tx $ty
    rotateObj $box $angle 0 0 1
    polycolor $box {*}$color

    # create object matrix for updating
    set degrees [expr $angle*(180./$::pi)]
    set m [dl_tcllist [mat4_createTranslationAngle $tx $ty $degrees]]
    setObjMatrix $box {*}$m

    # link the box2d box to the polygon
    Box2D_linkObj $bworld $body $box
    setObjProp $box body $body
    setObjProp $box bworld $bworld

    return $box
}

# create a box2d body and visual circle (angle is in degrees)
proc create_circle { bworld name type tx ty radius { angle 0 } { color { 1 1 1 } } } {
    # create the box2d circle
    set body [Box2D_createCircle $bworld $name $type $tx $ty $radius $angle]

    # make a polygon to visualize the circle
    set circ [make_circle]
    scaleObj $circ [expr 2.0*$radius] [expr 2.0*$radius]
    translateObj $circ $tx $ty
    polycolor $circ {*}$color

    # create object matrix for updating
    # create object matrix for updating
    set degrees [expr $angle*(180./$::pi)]
    set m [dl_tcllist [mat4_createTranslationAngle $tx $ty $degrees]]
    setObjMatrix $circ {*}$m

    # link the box2d circle to the polygon
    Box2D_linkObj $bworld $body $circ
    setObjProp $circ body $body
    setObjProp $circ bworld $bworld

    return $circ
}

# Create a square which can be scaled to create rects
proc make_rect {} {
    set s [polygon]
    return $s
}

# Create a circle
proc make_circle {} {
    set circ [polygon]
    polycirc $circ 1
    return $circ
}

proc nexttrial { id } {
    set ::curtrial $id
    glistInit 2
    resetObjList
    set ::world [make_stims $id]

    set fix_color ".7 .7 .1"
    set mg [metagroup]
    set obj [polygon]
    polycirc $obj 1
    polycolor $obj {*}$fix_color
    translateObj $obj 0 0
    set fix_targ_r 0.2
    scaleObj $obj [expr {2*$fix_targ_r}]; # diameter is 2r
    set center [polygon]
    polycirc $center 1
    polycolor $center 0 0 0
    translateObj $center 0 0
    scaleObj $center [expr {0.3*2*$fix_targ_r}];
    metagroupAdd $mg $obj
    metagroupAdd $mg $center
    glistAddObject $mg 1
}

proc show_response { resp } {
    set simulate 0; # used stored trajectory to replay as built
    set body [setObjProp $::ball body]
    if { $simulate } {
        Box2D_setBodyType $::world $body 2; # dynamic
    } else {
        Box2D_setBodyType $::world $body 1; # kinematic
        addPreScript $::ball "update_position $::ball $body $::StimTime"
    }
    if { $resp == 0 } { set c $::left_catcher } { set c $::right_catcher }
    set color "0.7 0.7 0.7"
    foreach p $c {
        polycolor $p {*}$color
    }
}

proc show_feedback { resp correct } {
    if { $resp == 0 } { set c $::left_catcher } { set c $::right_catcher }
    set green "0.2 .9 .3"
    set red "1.0 .2 .2"
    foreach p $c {
        if { $correct } { set color $green } { set color $red }
        polycolor $p {*}$color
    }
}

proc stimon {} {
    glistSetCurGroup 0
    glistSetVisible 1
    redraw
}

proc stimoff {} {
    glistSetVisible 0
    redraw
}

proc fixon {} {
    glistSetCurGroup 1
    glistSetVisible 1
    redraw
}

proc fixoff {} {
    glistSetVisible 0; redraw;
}

proc plankson {} {
    foreach p $::planks {
        setVisible $p 1
    }
    redraw
}

proc planksoff {} {
    foreach p $::planks {
        setVisible $p 0
    }
    redraw
}

proc reset { } {
    glistSetVisible 0; redraw;
}

proc clearscreen { } {
    glistSetVisible 0; redraw;
}
