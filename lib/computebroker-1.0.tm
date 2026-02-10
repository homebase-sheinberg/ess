package provide computebroker 1.0
package require json

namespace eval computebroker {
    variable default_host "sheinberglab.org"
    variable default_port 9000
    
    # Internal helper to communicate with broker
    proc send_command {command {host ""} {port ""}} {
        variable default_host
        variable default_port
        
        if {$host eq ""} {set host $default_host}
        if {$port eq ""} {set port $default_port}
        
        set sock [socket $host $port]
        puts $sock $command
        flush $sock
        set response [read $sock]
        close $sock
        return [string trim $response]
    }
    
    # Get a worker IP (launches if needed)
    proc get {{host ""} {port ""}} {
        return [send_command "GET_WORKER" $host $port]
    }
    
    # Ping worker to keep it alive
    proc ping {worker_ip {host ""} {port ""}} {
        return [send_command "PING $worker_ip" $host $port]
    }
    
    # Release worker immediately (dev/testing)
    proc release {worker_ip {host ""} {port ""}} {
        return [send_command "RELEASE $worker_ip" $host $port]
    }
    
    # Get status of known workers
    proc status {{host ""} {port ""}} {
        set json_response [send_command "STATUS" $host $port]
        return [json::json2dict $json_response]
    }
    
    # List all running instances from AWS
    proc list_all {{host ""} {port ""}} {
        set json_response [send_command "LIST_ALL" $host $port]
        return [json::json2dict $json_response]
    }
    
    # Terminate all workers
    proc terminate_all {{host ""} {port ""}} {
        set json_response [send_command "TERMINATE_ALL" $host $port]
        return [json::json2dict $json_response]
    }
    
    # Format status as string
    proc format_status {{host ""} {port ""}} {
        set workers [status $host $port]
        
        if {[llength $workers] == 0} {
            return "No active workers"
        }
        
        set output "Active Workers:\n"
        append output [format "%-20s %-16s %12s %18s\n" "Instance ID" "IP Address" "Idle (sec)" "Terminate in"]
        append output [string repeat "-" 70]
        append output "\n"
        
        foreach worker $workers {
            set instance_id [dict get $worker instance_id]
            set ip [dict get $worker ip]
            set idle [dict get $worker idle_seconds]
            set terminate_in [dict get $worker will_terminate_in]
            
            append output [format "%-20s %-16s %12d %18d\n" $instance_id $ip $idle $terminate_in]
        }
        
        return $output
    }
    
    # Format all instances as string
    proc format_list_all {{host ""} {port ""}} {
        set instances [list_all $host $port]
        
        if {[llength $instances] == 0} {
            return "No running instances"
        }
        
        set output "All Running Instances:\n"
        append output [format "%-20s %-16s %-16s %-25s\n" "Instance ID" "Type" "IP Address" "Launch Time"]
        append output [string repeat "-" 80]
        append output "\n"
        
        foreach instance $instances {
            set instance_id [dict get $instance instance_id]
            set instance_type [dict get $instance instance_type]
            set ip [dict get $instance ip]
            set launch_time [dict get $instance launch_time]
            
            # Truncate launch time for display
            set launch_short [string range $launch_time 0 18]
            
            append output [format "%-20s %-16s %-16s %-25s\n" $instance_id $instance_type $ip $launch_short]
        }
        
        return $output
    }
    
    # Set default broker host/port
    proc set_broker {host {port 9000}} {
        variable default_host
        variable default_port
        set default_host $host
        set default_port $port
    }
}


