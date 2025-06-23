##
## PROTOCOL
##   hapticvis identify
##
## DESCRIPTION
##   Present a shape and subject selects matching spatial location
##

namespace eval hapticvis::identify {

    ######################################################################
    #                         Data Processing                            #
    #                                                                    #
    # 1. Open the original ess file                                      #
    # 2. Read using dslogReadESS                                         #
    # 3. Pull out response, response time, and status from valid trials  #
    # 4. Pull out stimtype for all valid trials                          #
    # 5. Use stimtype to pull all trial attributes from stimdg           #
    # 6. Add to new dg                                                   #
    # 7. Convert to JSON and export as new file or return JSON string    #
    #                                                                    #
    ######################################################################
    
    proc load_data { essfile { jsonfile {} } } {
	package require dlsh
	package require dslog
	set g [::dslog::readESS $essfile]
	
	# get relevant event ids
	lassign [::ess::evt_id ENDTRIAL ABORT]    endt_id     endt_abort 
	lassign [::ess::evt_id ENDOBS   COMPLETE] endobs_id   endobs_complete 
	lassign [::ess::evt_id CHOICES  ON]       choices_id  choices_on
	lassign [::ess::evt_id SAMPLE   ON]       sample_id   sample_on
	lassign [::ess::evt_id RESP]              resp_id 
	lassign [::ess::evt_id STIMTYPE]          stimtype_id 
	
	# valid trials have an endtrial subtype which is 0 or 1
	dl_local endtrial [dl_select $g:e_subtypes \
			       [dl_eq $g:e_types $endt_id]]
	dl_local endobs   [dl_select $g:e_subtypes \
			       [dl_eq $g:e_types $endobs_id]]
	dl_local valid    [dl_sums \
			       [dl_and \
				    [dl_eq $endobs $endobs_complete] \
				    [dl_lengths $endtrial] \
				    [dl_lt $endtrial $endt_abort]]]
	
	# extract event types/subtypes/times/params for valid trials
	foreach v "types subtypes times params" {
	    dl_local $v [dl_select $g:e_$v $valid]
	}
	
	# pull out variables of interest
	dl_local correct  \
	    [dl_unpack [dl_select $subtypes [dl_eq $types $endt_id]]]
	dl_local stimon_t  \
	    [dl_unpack [dl_select $times \
			    [dl_and \
				 [dl_eq $types $sample_id] \
				 [dl_eq $subtypes $sample_on]]]]
	dl_local response_t \
	    [dl_unpack [dl_select $times [dl_eq $types $resp_id]]]
	dl_local response \
	    [dl_unpack [dl_select $subtypes [dl_eq $types $resp_id]]]
	dl_local stimtype \
	    [dl_unpack [dl_deepUnpack \
			    [dl_select $params \
				 [dl_eq $types $stimtype_id]]]]
	
	# create table to export
	set out [dg_create]
	dl_set $out:status $correct
	dl_set $out:rt [dl_sub $response_t $stimon_t]
	dl_set $out:response $response
	
	# find all stimdg columns and their names without <stimdg>
	set stimdg_cols \
	    [lsearch -inline -all -glob [dg_tclListnames $g] "<stimdg>*"]
	set cols [regsub -all <stimdg> $stimdg_cols {}]
	foreach c $cols {
	    dl_set $out:$c [dl_choose $g:<stimdg>${c} $stimtype]
	}
	
	# find all ds columns and their names without <ds>
	set ds_cols \
	    [lsearch -inline -all -glob [dg_tclListnames $g] "<ds>*"]
	set cols [regsub -all <ds> $ds_cols {}]
	foreach c $cols {
	    dl_set $out:$c [dl_choose $g:<ds>${c} $stimtype]
	}
	
	# close original ESS dg
	dg_delete $g
	
	# store as JSON
	set data [dg_toJSON $out]
	dg_delete $out
	if { $jsonfile != "" } {
	    set f [open $jsonfile w]
	    puts $f $data
	    close $f
	} else {
	    return $data
	}
    }
    return
}

