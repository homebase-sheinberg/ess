# `ess` Tcl Library Documentation

This document provides a guide to the Tcl functions available in the `ess` namespace, which are used to control and interact with the ESS (Experiment Sequencing System).

## Understanding the ESS Task Structure

The ESS framework is designed around a clear hierarchical structure that organizes psychophysics tasks into reusable components. This structure is reflected in both the file system layout and the core Tcl commands.

### The Core Hierarchy: System → Protocol → Variant

A task in ESS is defined by three levels:

1.  **System:** The highest level of organization, representing a family of related experiments. A system defines the fundamental state machine (e.g., `intertrial`, `stimulus`, `response`) and the core parameters that are common to all tasks within it.
    *   *On Disk:* A directory inside `/usr/local/dserv/systems/ess/`.
    *   *Example:* `search`

2.  **Protocol:** A specific experiment within a system. It inherits the system's state machine but can define its own parameters and logic. It also defines the different variants that can be run.
    *   *On Disk:* A subdirectory within a system directory.
    *   *Example:* `search/circles`

3.  **Variant:** A specific configuration of a protocol. This is where the fine details of an experiment are set, such as the number of trials, stimulus properties, or timing parameters. A single protocol can have many variants.
    *   *On Disk:* Defined within a protocol's `_variants.tcl` and `_loaders.tcl` files.
    *   *Example:* The `circles` protocol has variants like `single`, `variable`, and `distractors`.

### How It Works: The Loading Process

When you call `ess::load_system system_name protocol_name variant_name`, ESS performs a sequence of loading and initialization steps based on this hierarchy:

1.  **System File:** It sources the main `<system_name>.tcl` file. This file typically sets up the core state machine using `add_state` and defines system-wide parameters.
2.  **Protocol File:** It sources the `<protocol_name>.tcl` file from the protocol's subdirectory. This file defines protocol-specific parameters and logic.
3.  **Variant Files:** It sources the protocol's `_variants.tcl` and `_loaders.tcl` files.
    *   `_variants.tcl` defines the available variants and their specific parameter overrides.
    *   `_loaders.tcl` defines the `proc`s (procedures) that actually load the trial data and configure the experiment for a given variant.
4.  **Initialization:** Finally, the loader `proc` for the chosen variant is executed, which sets up the `stimdg` (stimulus data group) and prepares the system to run.

This layered approach allows for modular and reusable task design. A base system can be created once and then extended with numerous protocols and variants without duplicating code.

## Calling `ess` Functions

All functions in this library reside within the `ess` namespace. To execute them using `essctrl`, you must prepend `ess::` to the function name.

**Example:**
```bash
# Correct syntax for calling the 'load_system' function
essctrl -c "ess::load_system my_system"

# Load the 'search' system, allowing the default protocol and variant to be selected
essctrl -c "ess::load_system search"
```

---

## Core Functions

### `ess::load_system`

Loads and initializes a system, along with a specific protocol and variant. This is the primary function for setting up an experimental environment.

**Syntax:**
```tcl
ess::load_system ?system? ?protocol? ?variant?
```

**Arguments:**

*   `system` (optional, string): The name of the system to load. If omitted, the first available system will be loaded.
*   `protocol` (optional, string): The name of the protocol to load within the specified system. If omitted, the first available protocol in that system is used.
*   `variant` (optional, string): The name of the variant to load for the given protocol. If omitted, the first available variant is used.

**Usage:**

When called, this function performs the following steps:
1.  Unloads any currently active system.
2.  Searches for and identifies all available systems.
3.  Loads the specified (or default) system and initializes it.
4.  Finds and loads the specified (or default) protocol for that system.
5.  Finds and loads the specified (or default) variant for that protocol.
6.  Initializes all loaders associated with the chosen variant.

**Example:**
```bash
# Load the 'search' system, allowing the default protocol and variant to be selected
essctrl -c "ess::load_system search"
```

### `ess::find_systems`

Discovers and returns a list of all available systems.

**Syntax:**
```tcl
ess::find_systems
```

**Arguments:** None.

**Returns:** A Tcl list of strings, where each string is the name of a found system.

**Example (Verified):**
```bash
essctrl -c "ess::find_systems"
# → emcalib match_to_sample hapticvis search planko
```

### `ess::find_protocols`

Discovers and returns a list of all available protocols within a given system.

**Syntax:**
```tcl
ess::find_protocols system_name
```

**Arguments:**

*   `system_name` (string): The name of the system to query.

**Returns:** A Tcl list of strings, where each string is the name of a protocol found in the specified system.

**Example (Verified):**
```bash
# First, load a system
essctrl -c "ess::load_system search"

# Then, find its protocols
essctrl -c "ess::find_protocols search"
# → circles
```

### `ess::find_variants`

Discovers and returns a list of all available variants for a given protocol within a system.

**Syntax:**
```tcl
ess::find_variants system_name protocol_name
```

**Arguments:**

*   `system_name` (string): The name of the system to query.
*   `protocol_name` (string): The name of the protocol to query within that system.

**Returns:** A Tcl list of strings, where each string is the name of a variant.

**Example (Verified):**
```bash
# First, load a system
essctrl -c "ess::load_system search"

# Then, find the variants for its 'circles' protocol
essctrl -c "ess::find_variants search circles"
# → single variable distractors
```

## State Management

These functions control the execution state of the currently loaded system.

### `ess::start`

Starts the execution of the currently loaded system. The system begins running through its defined states and transitions.

**Syntax:**
```tcl
ess::start
```

**Arguments:** None.

**Note:** These functions do not produce any direct output, but they change the internal state of the system.

### `ess::stop`

Stops the execution of the currently running system.

**Syntax:**
```tcl
ess::stop
```

**Arguments:** None.

**Note:** These functions do not produce any direct output, but they change the internal state of the system.

### `ess::reset`

Resets the system to its initial state. This is typically used to prepare the system for another run without completely reloading it.

**Syntax:**
```tcl
ess::reset
```

**Arguments:** None.

**Note:** These functions do not produce any direct output, but they change the internal state of the system.

## Parameter Management

These functions allow you to inspect and modify the parameters of the currently loaded system. Parameters control the behavior of different components within the system.

### `ess::get_param_vals`

Retrieves a dictionary of all parameters and their current values for the loaded system.

**Syntax:**
```tcl
ess::get_param_vals
```

**Arguments:** None.

**Returns:** A Tcl dictionary where keys are parameter names and values are the corresponding parameter values.

**Example (Verified):**
```bash
# Load a system first
essctrl -c "ess::load_system search"

essctrl -c "ess::get_param_vals"
# → interblock_time 1000 prestim_time 250 response_timeout 5000 rmt_host localhost juice_ml 0.6 use_buttons 1 left_button 24 right_button 25
```

### `ess::get_param`

Retrieves the value and type information of a single, specific parameter.

**Syntax:**
```tcl
ess::get_param parameter_name
```

**Arguments:**

*   `parameter_name` (string): The name of the parameter to retrieve.

**Returns:** A Tcl list containing the parameter's value, its type ID, and its type name (e.g., `5000 1 int`).

**Example (Verified):**
```bash
essctrl -c "ess::get_param response_timeout"
# → 5000 1 int
```

### `ess::set_param`

Sets the value of a single parameter.

**Syntax:**
```tcl
ess::set_param parameter_name new_value
```

**Arguments:**

*   `parameter_name` (string): The name of the parameter to modify.
*   `new_value`: The new value to assign to the parameter.

**Example (Verified):**
```bash
# Set a new value
essctrl -c "ess::set_param response_timeout 4000"

# Verify the change
essctrl -c "ess::get_param response_timeout"
# → 4000 1 int
```

### `ess::set_params`

Sets multiple parameters at once using a list of key-value pairs.

**Syntax:**
```tcl
ess::set_params {parameter_1 value_1 parameter_2 value_2 ...}
```

**Arguments:**

*   An even-numbered list of arguments, alternating between parameter names and their new values.

**Example (Verified):**
```bash
# Set multiple values
essctrl -c "ess::set_params response_timeout 5000 juice_ml 0.7"

# Verify the changes
essctrl -c "ess::get_param_vals"
# → interblock_time 1000 prestim_time 250 response_timeout 5000 rmt_host localhost juice_ml 0.7 use_buttons 1 left_button 24 right_button 25
```

## Subject Management

These functions control the current subject ID, which is used for data logging and settings management.

### `ess::set_subject`

Sets the identifier for the current subject.

**Syntax:**
```tcl
ess::set_subject subject_id
```

**Arguments:**

*   `subject_id` (string): A unique identifier for the subject (e.g., `subj_01`).

**Example (Verified):**
```bash
essctrl -c "ess::set_subject test_subject"
```

### `ess::get_subject`

Retrieves the identifier for the current subject.

**Syntax:**
```tcl
ess::get_subject
```

**Arguments:** None.

**Returns:** The current subject's ID as a string.

**Example (Verified):**
```bash
essctrl -c "ess::set_subject test_subject; ess::get_subject"
# → test_subject
```

## Settings Management (Experimental)

These functions are used to save, load, and reset settings for a particular subject, system, protocol, and variant combination.

**Warning:** These functions perform direct file I/O and have been found to be unstable, potentially causing the `essctrl` server to hang. Use with caution.

### `ess::save_settings`

Saves the current parameter and variant settings to a file, associated with the current subject.

**Syntax:**
```tcl
ess::save_settings
```

**Arguments:** None.

### `ess::load_settings`

Loads the settings from a file for the current subject.

**Syntax:**
```tcl
ess::load_settings
```

**Arguments:** None.

### `ess::reset_settings`

Removes the saved settings for the current subject, reverting them to the default.

**Syntax:**
```tcl
ess::reset_settings
```

**Arguments:** None.

## System Querying

These functions return information about the currently loaded system and its state.

### `ess::query_system`

Returns the name of the currently loaded system.

**Syntax:**
```tcl
ess::query_system
```

**Arguments:** None.

**Returns:** The name of the loaded system as a string.

**Example (Verified):**
```bash
essctrl -c "ess::load_system search; ess::query_system"
# → search
```

### `ess::query_state`

Returns the current execution state of the system.

**Syntax:**
```tcl
ess::query_state
```

**Arguments:** None.

**Returns:** The state as a string (e.g., `stopped`, `running`).

**Example (Verified):**
```bash
essctrl -c "ess::load_system search; ess::query_state"
# → stopped

essctrl -c "ess::start; ess::query_state"
# → running
```

## System Reloading

These functions are shortcuts to reload the current system, protocol, or variant. This is useful when settings or scripts have changed and need to be reapplied without starting from scratch.

### `ess::reload_system`

Reloads the entire current system, including the protocol and variant.

**Syntax:**
```tcl
ess::reload_system
```

**Arguments:** None.

### `ess::reload_protocol`

Reloads the current protocol and variant.

**Syntax:**
```tcl
ess::reload_protocol
```

**Arguments:** None.

### `ess::reload_variant`

Reloads the current variant, re-running its initialization scripts.

**Syntax:**
```tcl
ess::reload_variant
```

**Arguments:** None. 
