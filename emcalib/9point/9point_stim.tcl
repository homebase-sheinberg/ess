# NAME
#   emcalib_9point.tcl
#
# DESCRIPTION
#   calibration with 9 locations
#
# REQUIRES
#   polygon
#   metagroup
#
# AUTHOR
#   DLS
#


proc nexttrial { id } {
    glistInit 2
    resetObjList

    set fix_color ".7 .7 .1"

    foreach p "fix_targ_x fix_targ_y fix_targ_r" {
        set $p [dl_get stimdg:$p $id]
    }

    # load the initial fixation
    set mg [metagroup]
    set obj [polygon]
    polycirc $obj 1
    polycolor $obj {*}$fix_color
    translateObj $obj $fix_targ_x $fix_targ_y
    scaleObj $obj [expr {2*$fix_targ_r}]; # diameter is 2r
    set center [polygon]
    polycirc $center 1
    polycolor $center 0 0 0
    translateObj $center $fix_targ_x $fix_targ_y
    scaleObj $center [expr {0.3*2*$fix_targ_r}]; # diameter is 2r
    metagroupAdd $mg $obj
    metagroupAdd $mg $center
    glistAddObject $mg 0

    foreach p "jump_targ_x jump_targ_y jump_targ_r" {
        set $p [dl_get stimdg:$p $id]
    }

    # load the jump
    set mg [metagroup]
    set obj [polygon]
    polycirc $obj 1
    polycolor $obj {*}$fix_color
    translateObj $obj $jump_targ_x $jump_targ_y
    scaleObj $obj [expr {2*$jump_targ_r}]; # diameter is 2r
    set center [polygon]
    polycirc $center 1
    polycolor $center 0 0 0
    translateObj $center $jump_targ_x $jump_targ_y
    scaleObj $center [expr {0.3*2*$jump_targ_r}]; # diameter is 2r
    metagroupAdd $mg $obj
    metagroupAdd $mg $center
    glistAddObject $mg 1

}

proc fixon {} {
    glistSetCurGroup 0
    glistSetVisible 1
    redraw
}

proc fixjump {} {
    glistSetCurGroup 1
    glistSetVisible 1
    redraw
}

proc fixoff {} {
    glistSetVisible 0; redraw;
}

proc reset { } {
    glistSetVisible 0; redraw;
}

proc clearscreen { } {
    glistSetVisible 0; redraw;
}






