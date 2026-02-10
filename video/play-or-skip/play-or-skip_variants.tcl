#
# VARIANTS
#   video play-or-skip
#
# DESCRIPTION
#   variant dictionary
#

namespace eval video::play-or-skip {
    variable variants {
        test {
            description "no distractors"
            loader_proc basic_load
            loader_options {
                nr { 200 100 50 }
            }
            init { rmtSend "setBackground 10 10 10" }
            deinit {}
        }
    }
    
    # use subst to replace variables in variant definition above
    set variants [subst $variants]
}

