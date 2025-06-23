# -*- mode: tcl -*-

##
## Blob making code
##

package require impro
package require curve

namespace eval blob {
    ############### Blob Creation Code #################
    #
    # given a dg with points already, add a new, random one, in order
    #
    #    poly: input polygon with into which points are added
    #       n: number of points to add
    # mindist: minimum distance between points
    #
    proc add_points { poly n { mindist 0.1 } } {
	set maxtries 1000
	set mind2 [expr {$mindist*$mindist}]
	for { set i 0 } { $i < $n } { incr i } {
	    set done 0
	    set tries 0
	    while { !$done && $tries < $maxtries } {
		dl_local randoms [dl_sub [dl_mult 0.8 [dl_urand 2]] 0.4]
		set x [dl_get $randoms 0]
		set y [dl_get $randoms 1]
		dl_local xd [dl_sub $poly:x $x]
		dl_local yd [dl_sub $poly:y $y]
		dl_local d2 [dl_add [dl_mult $xd $xd] [dl_mult $yd $yd]]
		if { [dl_min $d2] >= $mind2 } { set done 1 }
		incr tries
	    }
	    if { $tries == $maxtries } { error "unable to place points" }

	    set index [curve::closestPoint $poly:x $poly:y $x $y]
	    dl_insert $poly:x [expr {$index+1}] $x
	    dl_insert $poly:y [expr {$index+1}] $y
	}
	return $poly
    }

    #
    # create a random polygon
    #
    #  returns a dynamic group with x and y positions of control points
    proc create_poly { n } {
	set done 0
	set g [dg_create]
	while { !$done } {
	    dl_set $g:x [dl_sub [dl_mult 0.6 [dl_urand 3]] .3]
	    dl_set $g:y [dl_sub [dl_mult 0.6 [dl_urand 3]] .3]
	    add_points $g $n
	    if { ![curve::polygonSelfIntersects $g:x $g:y] } {
		set done 1
	    }
	}
	return $g
    }

    #
    # interpolate (using curve::cubic) and draw
    #
    proc show_poly { poly { nsteps 20 } } {
	setwindow -.5 -.5 .5 .5
	dl_local interped [curve::cubic $poly:x $poly:y $nsteps]
	dlg_lines $interped:0 $interped:1 -filled $::filled
	return $poly
    }

    #
    # create union from polygons (curve::clipper)
    #
    proc poly_union { nsteps args } {
	set s 10000.
	dl_local ps [dl_llist]
	foreach poly $args {
	    dl_local interped [curve::cubic $poly:x $poly:y $nsteps]
	    dl_append $ps $interped
	}
	dl_local polys [dl_int [dl_mult $ps $s]]
	dl_local union [dl_div [curve::clipper $polys] $s]
	dl_return $union
    }

    # a valid symmetrical object has a single path returned from the initial clip
    proc symmetrical_valid { v } {
	set s 1000.0
	dl_local clip [dl_int [dl_mult [dl_llist [dl_flist -.5 0 0 -.5] \
					    [dl_flist -.5 -.5 .5 .5]] $s]]
	dl_local poly [dl_int [dl_mult $v $s]]
	dl_local left_half [curve::clipper [dl_llist $poly] [dl_llist $clip]]
	if { [dl_length $left_half] == 1 } { return 1 } { return 0 }
    }

    # simple routine that creates a symmetric object by cutting in half
    # and then making union between cut half and mirror opposite
    proc make_symmetrical { v } {
	set s 1000.0
	dl_local clip [dl_int [dl_mult [dl_llist [dl_flist -.5 0 0 -.5] \
					    [dl_flist -.5 -.5 .5 .5]] $s]]
	dl_local poly [dl_int [dl_mult $v $s]]
	dl_local left_half [curve::clipper [dl_llist $poly] [dl_llist $clip]]
	dl_local right_half [dl_mult $left_half [dl_llist [dl_ilist -1 1]]]
	dl_local union [dl_div [curve::clipper [dl_llist $left_half:0 $right_half:0]] $s]
	dl_return [dl_llist $union:0:0 $union:0:1]
    }


    proc create { npolys nverts { nsteps 20 } } {
	set g [dg_create]

	set done 0
	set maxtries 100
	set tries 0

	while { !$done } {
	    set ps ""
	    incr tries
	    for { set i 0 } { $i < $npolys } { incr i } {
		lappend ps [create_poly $nverts]
	    }

	    dl_local union [poly_union $nsteps {*}$ps]
	    if { [dl_length $union] == 1 &&
		 [symmetrical_valid [dl_llist $union:0:0 $union:0:1]] } {
		set done 1
	    } else {
		foreach p $ps { dg_delete $p }
	    }
	    if { $tries == $maxtries } { error "unable to create single union" }
	}

	dl_local control_points [dl_llist]
	foreach p $ps {
	    dl_append $control_points [dl_llist $p:x $p:y]
	    dg_delete $p
	}

	dl_set $g:control_points [dl_llist $control_points]
	dl_set $g:nsteps [dl_ilist $nsteps]
	dl_set $g:shape [dl_llist [dl_llist $union:0:0 $union:0:1]]
	return $g
    }

    proc create_blobs { n npolys nverts { nsteps 20 } } {
	if { $n <= 0 } { return }
	set g [create $npolys $nverts $nsteps]
	for { set i 1 } { $i < $n } { incr i } {
	    set g1 [create $npolys $nverts $nsteps]
	    dg_append $g $g1
	    dg_delete $g1
	}
	return $g
    }
}
