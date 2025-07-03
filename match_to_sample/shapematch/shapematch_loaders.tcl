#
# LOADERS
#   match_to_sample shapematch
#
# DESCRIPTION
#   loader methods defined in loaders_init
#

package require blob; # for creating random shapes

namespace eval match_to_sample::shapematch {
    proc loaders_init { s } {
        $s add_method setup_trials { n_rep targ_scale shape_choices shape_params show_feedback } {
            # could specify these in shape_params
            set npolys 3
            set nverts 5

            # build our stimdg
            if { [dg_exists stimdg] } { dg_delete stimdg }
            set g [dg_create stimdg]
            dg_rename $g stimdg

            set xoff 3.0
            set yoff 2.0

            set n_obs [expr $n_rep]
            set n_per_side [expr $n_rep/2]

            set maxx [expr $screen_halfx]
            set maxy [expr $screen_halfy]

            dl_set $g:stimtype [dl_fromto 0 $n_obs]
            dl_set $g:shape_choices [dl_repeat [dl_slist $shape_choices] $n_obs]
            dl_set $g:side [dl_repeat "0 1" $n_per_side]

            dl_local white [dl_flist 1 1 1]
            dl_local gray [dl_flist .5 .5 .5]
            dl_local sample_colors [dl_repeat [dl_llist $white $white] $n_per_side]
            dl_local nonmatch_colors [dl_repeat [dl_llist $gray $gray] $n_per_side]

            if { $shape_choices == "single_pair" } {
                set nshapes 2
                dl_local sample_id [dl_repeat "0 1" [expr {$n_rep/2}]]
                dl_local match_id $sample_id
                dl_local nonmatch_id [dl_repeat "1 0" [expr {$n_rep/2}]]
            } elseif { $shape_choices == "single_pair_arbitrary" } {
                set nshapes 4
                # Arbitrary pairings: 0 -> 2, 1 -> 3
                dl_local sample_id [dl_repeat "0 1" [expr {$n_rep/2}]]
                dl_local match_id [dl_add $sample_id 2]
                dl_local nonmatch_id [dl_add [dl_sub 1 $sample_id] 2]
            }

            set blob_table [blob::create_blobs $nshapes $npolys $nverts]

            # Store show_feedback as a protocol variable for use during the trial
            if {![namespace exists ::match_to_sample::shapematch]} {
                namespace eval ::match_to_sample::shapematch {}
            }
            if {[info exists show_feedback]} {
                set ::match_to_sample::shapematch::show_feedback $show_feedback
            } else {
                set ::match_to_sample::shapematch::show_feedback 0
            }

            dl_set $g:sample_x [dl_repeat 0. $n_obs]
            dl_set $g:sample_y [dl_repeat $yoff $n_obs]
            dl_set $g:sample_scale [dl_repeat $targ_scale $n_obs]
            dl_set $g:sample_color $sample_colors
            dl_set $g:sample_pos  [dl_reshape [dl_interleave $g:sample_x $g:sample_y] - 2]
            dl_set $g:sample_shape [dl_choose $blob_table:shape $sample_id]
            dl_set $g:sample_control_points  [dl_choose $blob_table:control_points $sample_id]
            dl_set $g:sample_nsteps  [dl_choose $blob_table:nsteps $sample_id]

            dl_set $g:match_x [dl_mult 2 [dl_sub $g:side .5] $xoff]
            dl_set $g:match_y [dl_repeat [expr -1*$yoff] $n_obs]
            dl_set $g:match_scale [dl_repeat $targ_scale $n_obs]
            dl_set $g:match_color $sample_colors
            dl_set $g:match_pos [dl_reshape [dl_interleave $g:match_x $g:match_y] - 2]
            dl_set $g:match_shape [dl_choose $blob_table:shape $match_id]
            dl_set $g:match_control_points  [dl_choose $blob_table:control_points $match_id]
            dl_set $g:match_nsteps  [dl_choose $blob_table:nsteps $match_id]

            dl_set $g:nonmatch_x [dl_mult 2 [dl_sub [dl_sub 1 $g:side] .5] $xoff]
            dl_set $g:nonmatch_y [dl_repeat [expr -1*$yoff] $n_obs]
            dl_set $g:nonmatch_scale [dl_repeat $targ_scale $n_obs]
            dl_set $g:nonmatch_color $nonmatch_colors
            dl_set $g:nonmatch_pos  [dl_reshape [dl_interleave $g:nonmatch_x $g:nonmatch_y] - 2]
            dl_set $g:nonmatch_shape [dl_choose $blob_table:shape $nonmatch_id]
            dl_set $g:nonmatch_control_points  [dl_choose $blob_table:control_points $nonmatch_id]
            dl_set $g:nonmatch_nsteps  [dl_choose $blob_table:nsteps $nonmatch_id]

            dl_set $g:remaining [dl_ones $n_obs]

            dg_delete $blob_table

            return $g
        }
    }
}

