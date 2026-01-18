#
# emcalib_analyze.tcl - Post-close analysis for emcalib system
#
# Computes biquadratic calibration coefficients from trial data
# and publishes to dserv for use by eye tracking systems.
#

package require em 1.0

namespace eval emcalib {
    
    #
    # Main analysis entry point - called by dfconf after file close
    #
    # Arguments:
    #   trials   - rectangular dg from extract_trials
    #   filepath - path to the original .ess file
    #
    # Returns:
    #   dict with analysis results
    #
    proc analyze {trials filepath} {
        puts "emcalib::analyze: Processing $filepath"
        
        # Check we have required columns
        foreach col {eye_mean_x eye_mean_y calib_x calib_y} {
            if {![dl_exists $trials:$col]} {
                puts "emcalib::analyze: Missing required column: $col"
                return ""
            }
        }
        
        # Get data as Tcl lists for fitting
        set eye_x [dl_tcllist $trials:eye_mean_x]
        set eye_y [dl_tcllist $trials:eye_mean_y]
        set calib_x [dl_tcllist $trials:calib_x]
        set calib_y [dl_tcllist $trials:calib_y]
        
        # Check we have enough points
        if {[llength $eye_x] < 9} {
            puts "emcalib::analyze: Need at least 9 points for fit, have [llength $eye_x]"
            return ""
        }
        
        # Fit biquadratic using em package
        set coeffs [em::biquadratic_fit $eye_x $eye_y $calib_x $calib_y]
        if {$coeffs eq ""} {
            puts "emcalib::analyze: Biquadratic fit failed"
            return ""
        }
        
        lassign $coeffs x_coeffs y_coeffs
        
        # Calculate RMS error
        set rms [em::biquadratic_rms $coeffs $eye_x $eye_y $calib_x $calib_y]
        
        # Build result
        set result [dict create \
            source $filepath \
            filename [file tail $filepath] \
            timestamp [clock seconds] \
            x_coeffs $x_coeffs \
            y_coeffs $y_coeffs \
            rms_error $rms \
            n_trials [llength $eye_x]]
        
        # Publish to dserv
        publish_calibration $result
        
        puts "emcalib::analyze: Calibration complete, RMS error: [format %.3f $rms] deg, n=$n_trials"
        
        return $result
    }
    
    #
    # Publish calibration results to dserv
    #
    proc publish_calibration {result} {
        # Main calibration datapoint
        dservSet em/biquadratic $result
        
        # Also set a simple timestamp for quick checks
        dservSet em/calibration_timestamp [dict get $result timestamp]
        
        puts "emcalib::analyze: Published calibration to em/biquadratic"
    }
}
