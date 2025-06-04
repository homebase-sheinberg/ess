#
# VARIANTS
#   planko training
#
# DESCRIPTION
#   variant dictionary for planko::training
# test 

namespace eval planko::training {
    variable variants {
	single {
	    description "one plank"
	    loader_proc basic_planko
	    loader_options {
		nr { 100 200 300}
		nplanks { 1 }
		wrong_catcher_alpha 1
		params { { defaults {} } }
	    }
	    init {
		rmtSend "setBackground 0 0 10"
	    }
	    deinit {}
	}
	jitter {
	    description "jitter ball start"
	    loader_proc basic_planko
	    loader_options {
		nr { 50 100 200 }
		nplanks { 1 }
		wrong_catcher_alpha { 1 0.5 }
		params { { jittered { ball_jitter_x 8 ball_start_y 5 ball_jitter_y 1 } } }
	    }
	}
	zero_one {
	    description "hit zero or one plank"
	    loader_proc basic_planko
	    loader_options {
		nr { 50 100 200 400 800}
		nplanks { 1 }
		wrong_catcher_alpha { 1.0 0.98 0.95 0.9 0.8 0.7 }
		params { { jittered { ball_jitter_x 10 ball_start_y 0 ball_jitter_y 3 minplanks 0 } } }
	    }
	}
 	two_plus {
	    description "show 2+ planks, hit 1+ plank"
	    loader_proc basic_planko
	    loader_options {
		nr { 50 100 200 400 800}
		nplanks { 2 3 4}
		wrong_catcher_alpha { 1.0 0.98 0.95 0.9 0.8 0.7 }
		params { { jittered { ball_jitter_x 10 ball_start_y 0 ball_jitter_y 3 minplanks 1 } } 
  		 	 { higher { ball_jitter_x 10 ball_start_y 5 ball_jitter_y 3 minplanks 1 } } 
    		         { two_plank { ball_jitter_x 10 ball_start_y 5 ball_jitter_y 3 minplanks 2 } } }
	    }
	}
	super_monkey {
	  description "jitter X ball start, vary hitplanks, select stim_dur"
      loader_proc basic_planko
      loader_options {
        nr { 10 20 30 40 50 60 70 80 90 100 }
    
        nplanks { 10 }
        wrong_catcher_alpha { 1.0 }
    
        
        params {
          { jittered { ball_jitter_x 6 ball_start_y 6 ball_jitter_y 0 } }
        }
      }
	}
    
}

