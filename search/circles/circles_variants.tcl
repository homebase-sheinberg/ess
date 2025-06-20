#
# VARIANTS
#   search circles
#
# DESCRIPTION
#   variant dictionary
#   requires datalib to be loaded before sourcing
#

namespace eval search::circles {
    variable variants {
	single {
	    description "no distractors"
	    loader_proc basic_search
            loader_options {
                nr { 200 100 50 }
                nd { 0 }
                targ_r { 1.5 2.0 }
                dist_prop { 1 }
                mindist { 1.5 }
                targ_range { 8 9 10 }
                targ_color {
                    { cyan { 0 1 1 } }
                    { red { 1 0 0 } }
                }
                dist_color {}
            }
	    init { rmtSend "setBackground 10 10 10" } 
	    deinit {}
	}
	variable {
	    description "variable number of distractors"
	    loader_proc basic_search
            loader_options {
                nr { 40 60 100 }
                nd {
                    { 0,2,4,6,8 { [dl_tcllist [dl_series 0 8 2]] } }
                    { 0,5,10    { 0 5 10 } }
                }
                targ_r { 1.5 2.0 }
                dist_prop { 1.2 1.1 0.9 0.8 }
                mindist {1.5 2.0}
                targ_range { 8 9 10 }
                targ_color {
                    { cyan { 0 1 1 } }
                    { red { 1 0 0 } }
                }
                dist_color {}
            }
	    params { interblock_time 750 }
	}
        distractors {
            description "fixed number of distractors"
            loader_proc basic_search
            loader_options {
                nr { 100 200 }
                nd { 4 6 8 }
                targ_r { 1.5 2.0 }
                dist_prop { 1.2 1.1 0.9 0.8 }
                mindist { 2.0 3.0 }
                targ_range { 8 9 10 }
                targ_color {
                    { cyan { 0 1 1 } }
                    { red { 1 0 0 } }
                    { purple { 1 0 1 } }
                }
                dist_color {}
            }
        }
        diff_color {
            description "distractors marked by color"
            loader_proc basic_search
            loader_options {
                nr { 100 }
                nd { 4 }
                targ_r { 1 }
                dist_prop { 1 }
                mindist { 2.0 }
                targ_range { 8 9 10 }
                targ_color {
                    { blue { 0 0 1 } }
                }
                dist_color {
                    { red { 1 0 0 } }
                }
            }
        }
    }
    # use subst to replace variables in variant definition above
    set variants [subst $variants]
}

