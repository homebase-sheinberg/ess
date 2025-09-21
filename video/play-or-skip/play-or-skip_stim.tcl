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
proc add_buttons { stimtype } {
    set playbutton_svg {<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20" viewBox="0 0 20 20">
        <path d="M9.5 20c-2.538 0-4.923-0.988-6.718-2.782s-2.782-4.18-2.782-6.717c0-2.538 0.988-4.923 2.782-6.718s4.18-2.783 6.718-2.783c2.538 0 4.923 0.988 6.718 2.783s2.782 4.18 2.782 6.718-0.988 4.923-2.782 6.717c-1.794 1.794-4.18 2.782-6.718 2.782zM9.5 2c-4.687 0-8.5 3.813-8.5 8.5s3.813 8.5 8.5 8.5c4.687 0 8.5-3.813 8.5-8.5s-3.813-8.5-8.5-8.5z" fill="#000000"></path>
        <path d="M6.5 16c-0.083 0-0.167-0.021-0.242-0.063-0.159-0.088-0.258-0.256-0.258-0.437v-10c0-0.182 0.099-0.349 0.258-0.437s0.353-0.083 0.507 0.013l8 5c0.146 0.091 0.235 0.252 0.235 0.424s-0.089 0.333-0.235 0.424l-8 5c-0.081 0.051-0.173 0.076-0.265 0.076zM7 6.402v8.196l6.557-4.098-6.557-4.098z" fill="#000000"></path>
        </svg>
    }

    set skipbutton_svg {<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20" viewBox="0 0 20 20">
        <path d="M9.5 20c-2.538 0-4.923-0.988-6.718-2.782s-2.782-4.18-2.782-6.717c0-2.538 0.988-4.923 2.782-6.718s4.18-2.783 6.718-2.783c2.538 0 4.923 0.988 6.718 2.783s2.782 4.18 2.782 6.718-0.988 4.923-2.782 6.717c-1.794 1.794-4.18 2.782-6.718 2.782zM9.5 2c-4.687 0-8.5 3.813-8.5 8.5s3.813 8.5 8.5 8.5c4.687 0 8.5-3.813 8.5-8.5s-3.813-8.5-8.5-8.5z" fill="#000000"></path>
        <path d="M6.5 16c-0.072 0-0.144-0.016-0.212-0.047-0.176-0.082-0.288-0.259-0.288-0.453v-10c0-0.194 0.112-0.371 0.288-0.453s0.383-0.056 0.532 0.069l6 5c0.114 0.095 0.18 0.236 0.18 0.384s-0.066 0.289-0.18 0.384l-6 5c-0.092 0.076-0.205 0.116-0.32 0.116zM7 6.568v7.865l4.719-3.933-4.719-3.932z" fill="#000000"></path>
        <path d="M13.5 15c-0.276 0-0.5-0.224-0.5-0.5v-8c0-0.276 0.224-0.5 0.5-0.5s0.5 0.224 0.5 0.5v8c0 0.276-0.224 0.5-0.5 0.5z" fill="#000000"></path>
        </svg>
    }

    set nextbutton_svg {<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20" viewBox="0 0 20 20">
        <path d="M7.5 15c-0.076 0-0.153-0.017-0.224-0.053-0.169-0.085-0.276-0.258-0.276-0.447v-9c0-0.189 0.107-0.363 0.276-0.447s0.372-0.066 0.524 0.047l6 4.5c0.126 0.094 0.2 0.243 0.2 0.4s-0.074 0.306-0.2 0.4l-6 4.5c-0.088 0.066-0.194 0.1-0.3 0.1zM8 6.5v7l4.667-3.5-4.667-3.5z" fill="#000000"></path>
        <path d="M19.5 2h-19c-0.276 0-0.5 0.224-0.5 0.5v15c0 0.276 0.224 0.5 0.5 0.5h19c0.276 0 0.5-0.224 0.5-0.5v-15c0-0.276-0.224-0.5-0.5-0.5zM3 11h-2v-2h2v2zM3 8h-2v-2h2v2zM1 12h2v2h-2v-2zM4 3h12v14h-12v-14zM17 9h2v2h-2v-2zM17 8v-2h2v2h-2zM17 12h2v2h-2v-2zM19 5h-2v-2h2v2zM3 3v2h-2v-2h2zM1 15h2v2h-2v-2zM17 17v-2h2v2h-2z" fill="#000000"></path>
        </svg>}

    set y [expr {-0.9*[screen_set HalfScreenDegreeY]}]
    set scale [expr {.1*[screen_set HalfScreenDegreeY]}]

    set play_button [svg $playbutton_svg]
    set skip_button [svg $skipbutton_svg]
    set next_button [svg $nextbutton_svg]

    lassign [dl_get stimdg:next_button $stimtype] next_x next_y next_r
    svgColor $next_button 1 0.8 0.8 0.8 1.0
    translateObj $next_button $next_x $next_y
    scaleObj $next_button $next_r $next_r
    glistAddObject $next_button 1

    # Put choice buttons in metagroup (that we can turn off)
    set ::choice_mg [metagroup]
    lassign [dl_get stimdg:play_button $stimtype] play_x play_y play_r
    lassign [dl_get stimdg:skip_button $stimtype] skip_x skip_y skip_r
    foreach b "play skip" {
        set button [set ${b}_button]
        svgColor $button 1 0.8 0.8 0.8 1.0
        translateObj $button [set ${b}_x] [set ${b}_y]
        scaleObj $button [set ${b}_r] [set ${b}_r]
        metagroupAdd $::choice_mg $button
    }
    glistAddObject $::choice_mg 0
}

proc videoComplete {} {
    qpcs::dsSet $::dservhost video/complete 1
}

proc nexttrial { id } {
    glistSetVisible 0; redraw

    resetObjList
    shaderImageReset
    shaderDeleteAll
    glistInit 2

    set system_path [lindex [qpcs::dsGet $::dservhost ess/system_path] 5]
    set asset_path [file join $system_path assets]
    dl_local videos [dl_slist {*}[glob $asset_path/pixabay_vids/*.mp4]]

    set v [video [dl_pickone $videos]]
    set ::video $v

    set w [expr {0.8*[screen_set HalfScreenDegreeX]*2}]
    set h [expr {0.8*[screen_set HalfScreenDegreeY]*2}]
    scaleObj $v $w $h
    videoEofCallback $v videoComplete

    glistAddObject $v 0
    glistSetDynamic 0 1

    add_buttons $id
}

proc show_next_video {} {
    glistSetCurGroup 1
    glistSetVisible 1
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
    setVisible $::choice_mg 0; # hide buttons during playback
    videoPause $::video 0
}
