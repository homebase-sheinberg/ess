# NAME
#   shapematch_stim.tcl
#
# DESCRIPTION
#   match_to_sample with shapes
#
# REQUIRES
#   polygon
#   metagroup
#   shader
#
# AUTHOR
#   DLS
#

set paths {
    /usr/local/stim2/shaders/
    /Applications/stim2.app/Contents/Resources/shaders/
}

foreach dir $paths {
    if { [file exists $dir] } { shaderSetPath $dir; break }
}

# for creating images using CImg and other image processing tools
package require impro

proc create_shape { shader coords { filled 1 } } {

    # target image sampler size should be set in stimdg
    set width 512; set width_2 [expr ${width}/2]
    set height 512; set height_2 [expr ${height}/2]
    set depth 4

    set x $coords:0
    set y $coords:1

    dl_local xscaled [dl_add [dl_mult $x $width] $width_2]
    dl_local yscaled [dl_add [dl_mult [dl_negate $y] $height] $height_2]

    set img [img_create -width $width -height $height -depth $depth]
    if { $filled } {
        set poly [img_fillPolygonOutside $img $xscaled $yscaled 255 255 255 255]
        img_invert $poly
    } else {
        set poly [img_drawPolyline $img $xscaled $yscaled 255 255 255 255]
    }
    dl_local pix [img_imgtolist $poly]
    img_delete $poly $img

    set sobj [shaderObj $shader]
    set img [shaderImageCreate $pix $width $height linear]
    shaderObjSetSampler $sobj [shaderImageID $img] 0

    return $sobj
}

#
# nexttrial
#    create a triad of stimuli with sample on top and choices below
#
#
proc nexttrial { id } {
    # Reset the result so we can check if a new error is raised
    set ::errorInfo ""
    set ::errorCode NONE
    
    resetObjList             ;# unload existing objects
    shaderImageReset;        ;# free any shader textures
    shaderDeleteAll;         ;# reset any shader objects
    glistInit 2

    set shader_file image
    set shader [shaderBuild $shader_file]

    # grab relevant variables from stimdg
    foreach t "sample match nonmatch" {
	foreach p "${t}_x ${t}_y ${t}_scale ${t}_color" {
	    set $p [dl_get stimdg:$p $id]
	}
    }

    # add the sample
    foreach t sample {
	set obj [create_shape $shader stimdg:${t}_shape:$id]
	translateObj $obj [set ${t}_x] [set ${t}_y]
	scaleObj $obj [set ${t}_scale]
	glistAddObject $obj 0
    }

    # add the choices
    foreach t "match nonmatch" {
	set obj [create_shape $shader stimdg:${t}_shape:$id]
	translateObj $obj [set ${t}_x] [set ${t}_y]
	scaleObj $obj [set ${t}_scale]
	glistAddObject $obj 1
    }
}
    
proc sample_on {} {
    glistSetCurGroup 0
    glistSetVisible 1
    redraw
}

proc sample_off {} {
    logMessage "DEBUG: sample_off called"
    glistSetVisible 0
    redraw
}

proc choices_on {} {
    glistSetCurGroup 1
    glistSetVisible 1
    redraw
}

proc choices_off {} {
    logMessage "DEBUG: choices_off called"
    glistSetVisible 0
    redraw
}

# Create a filled circle polygon of radius 1, with specified color and alpha
proc create_circle { r g b { a 1 } } {
    logMessage "DEBUG: create_circle called"
    set c [polygon]
    polycirc $c 1
    polycolor $c $r $g $b $a
    return $c
}

# Show feedback circle: status=1 (green), status=0 (red)
proc show_feedback_circle { status } {
    logMessage "DEBUG: show_feedback_circle called with status = $status"
    global feedback_circle
    if { ![info exists feedback_circle(green)] } {
        logMessage "DEBUG: Creating green feedback circle for the first time."
        set feedback_circle(green) [create_circle 0 1 0 0.8]
        scaleObj $feedback_circle(green) 1.5
        translateObj $feedback_circle(green) 0 -3.5
        setVisible $feedback_circle(green) 0
        glistAddObject $feedback_circle(green) 1
    }
    if { ![info exists feedback_circle(red)] } {
        logMessage "DEBUG: Creating red feedback circle for the first time."
        set feedback_circle(red) [create_circle 1 0 0 0.8]
        scaleObj $feedback_circle(red) 1.5
        translateObj $feedback_circle(red) 0 -3.5
        setVisible $feedback_circle(red) 0
        glistAddObject $feedback_circle(red) 1
    }

    if { $status } {
        logMessage "DEBUG: Showing GREEN feedback circle."
        setVisible $feedback_circle(green) 1
        setVisible $feedback_circle(red) 0
    } else {
        logMessage "DEBUG: Showing RED feedback circle."
        setVisible $feedback_circle(green) 0
        setVisible $feedback_circle(red) 1
    }
    redraw

   # Schedule the circle to be cleared after 700ms
   logMessage "DEBUG: Scheduling clear_feedback_circle in 700ms."
   after 700 [list clear_feedback_circle]
}

proc clear_feedback_circle {} {
    logMessage "DEBUG: clear_feedback_circle called"
    global feedback_circle
    if {[info exists feedback_circle(green)]} { setVisible $feedback_circle(green) 0 }
    if {[info exists feedback_circle(red)]} { setVisible $feedback_circle(red) 0 }
    redraw
}

proc reset { } {
    glistSetVisible 0; redraw;
}

proc clearscreen { } {
    glistSetVisible 0; redraw;
}



