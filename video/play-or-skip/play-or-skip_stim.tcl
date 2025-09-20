# NAME
#   play-or-skip_stim.tcl
#
# DESCRIPTION
#   Show videos and let subject play or skip
#
# REQUIRES
#   svg
#   video
#
# AUTHOR
#   DLS
#


#
# add two SVG buttons to our display
#
proc add_buttons { group } {
    set playbutton_svg {<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20" viewBox="0 0 20 20">
	<path d="M9.5 20c-2.538 0-4.923-0.988-6.718-2.782s-2.782-4.18-2.782-6.717c0-2.538 0.988-4.923 2.782-6.718s4.18-2.783 6.718-2.783c2.538 0 4.923 0.988 6.718 2.783s2.782 4.18 2.782 6.718-0.988 4.923-2.782 6.717c-1.794 1.794-4.18 2.782-6.718 2.782zM9.5 2c-4.687 0-8.5 3.813-8.5 8.5s3.813 8.5 8.5 8.5c4.687 0 8.5-3.813 8.5-8.5s-3.813-8.5-8.5-8.5z" fill="#000000"></path>
	<path d="M6.5 16c-0.083 0-0.167-0.021-0.242-0.063-0.159-0.088-0.258-0.256-0.258-0.437v-10c0-0.182 0.099-0.349 0.258-0.437s0.353-0.083 0.507 0.013l8 5c0.146 0.091 0.235 0.252 0.235 0.424s-0.089 0.333-0.235 0.424l-8 5c-0.081 0.051-0.173 0.076-0.265 0.076zM7 6.402v8.196l6.557-4.098-6.557-4.098z" fill="#000000"></path>
	</svg>
    }
    
    set nextbutton_svg {<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20" viewBox="0 0 20 20">
	<path d="M9.5 20c-2.538 0-4.923-0.988-6.718-2.782s-2.782-4.18-2.782-6.717c0-2.538 0.988-4.923 2.782-6.718s4.18-2.783 6.718-2.783c2.538 0 4.923 0.988 6.718 2.783s2.782 4.18 2.782 6.718-0.988 4.923-2.782 6.717c-1.794 1.794-4.18 2.782-6.718 2.782zM9.5 2c-4.687 0-8.5 3.813-8.5 8.5s3.813 8.5 8.5 8.5c4.687 0 8.5-3.813 8.5-8.5s-3.813-8.5-8.5-8.5z" fill="#000000"></path>
	<path d="M6.5 16c-0.072 0-0.144-0.016-0.212-0.047-0.176-0.082-0.288-0.259-0.288-0.453v-10c0-0.194 0.112-0.371 0.288-0.453s0.383-0.056 0.532 0.069l6 5c0.114 0.095 0.18 0.236 0.18 0.384s-0.066 0.289-0.18 0.384l-6 5c-0.092 0.076-0.205 0.116-0.32 0.116zM7 6.568v7.865l4.719-3.933-4.719-3.932z" fill="#000000"></path>
	<path d="M13.5 15c-0.276 0-0.5-0.224-0.5-0.5v-8c0-0.276 0.224-0.5 0.5-0.5s0.5 0.224 0.5 0.5v8c0 0.276-0.224 0.5-0.5 0.5z" fill="#000000"></path>
	</svg>
    }

    set y [expr {-0.9*[screen_set HalfScreenDegreeY]}]
    set scale [expr {.1*[screen_set HalfScreenDegreeY]}]
    set play_button [svg $playbutton_svg]
    set next_button [svg $nextbutton_svg]

    foreach b "play next" x "-2 2" {
        set button [set ${b}_button]
        svgColor $button 1 0.8 0.8 0.8 1.0
        translateObj $button $x $y
        scaleObj $button $scale $scale
        glistAddObject $button $group
    }
    
}

proc videoComplete {} { 
    qpcs::dsSet $::dservhost video/complete 1
}

proc nexttrial { id } {
    glistSetVisible 0; redraw
    glistInit 1
    resetObjList
    shaderImageReset
    shaderDeleteAll

    dl_local videos [dl_slist {*}[glob /Users/sheinb/src/stim2/examples/pixabay_vids/*.mp4]]
    set v [video [dl_pickone $videos]]
    set ::video $v
    
    set w [expr {0.8*[screen_set HalfScreenDegreeX]*2}]
    set h [expr {0.8*[screen_set HalfScreenDegreeY]*2}]
    scaleObj $v $w $h
    videoEofCallback $v videoComplete
    
    glistAddObject $v 0
    glistSetDynamic 0 1

    add_buttons 0

    glistSetVisible 1;
    redraw
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

proc reset { } {
    glistSetVisible 0; redraw;
}

proc clearscreen { } {
    glistSetVisible 0; redraw;
}

proc play { } {
    videoPause $::video 0
}







