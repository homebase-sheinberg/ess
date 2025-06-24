use lib/ess-2.0.tm to understand how state systems are controlled

use lib/tcl_dl.c and lib/tcl_dl.h to understand the custom dl functions

DO NOT MODIFY ess-2.0.tm or tcl_dl.c or tcl_dl.h

Prepend the following to the beginning of all tcl scripts before running:

package require dlsh

package require qpcs



Steps for adding your own variant

    Open search/circles/circles_variants.tcl.

    Insert a new dictionary entry under variable variants { ... }.

        Provide a unique key name (e.g., my_variant).

        Fill in description, loader_proc (usually basic_search), and loader_options.

        Include a dist_color entry. Use { { same {} } } if distractors share the target color.

    Optionally add init, deinit, or additional params blocks if the variant needs special setup.

    Save the file and reload the protocol; the system will pick up the new variant when calling ess::load_system.

    
