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
    glistSetVisible 0
    redraw
}

proc choices_on {} {
    glistSetCurGroup 1
    glistSetVisible 1
    redraw
}

proc choices_off {} {
    glistSetVisible 0
    redraw
}

proc reset { } {
    glistSetVisible 0; redraw;
}

proc clearscreen { } {
    glistSetVisible 0; redraw;
}



