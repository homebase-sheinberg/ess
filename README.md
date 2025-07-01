# ESS Development Guide & API Reference

This document provides a guide for developers working with the ESS (Experiment Sequencing System), including how to create new tasks and a reference for the Tcl API accessible via the `essctrl` tool.

---

## How to Add a New Variant

This guide explains the process of adding a new variant to a system and protocol. A variant is a specific configuration of a task, defined by its stimulus properties.

### 1. Understand the Core Architecture

Before adding a variant, it's crucial to understand the data-driven architecture of ESS.

#### The Hierarchy: System → Protocol → Variant
A task is defined by three levels:
1.  **System:** The highest level of organization (e.g., `search`).
2.  **Protocol:** A specific experiment within a system (e.g., `circles`).
3.  **Variant:** A specific configuration of a protocol (e.g., `single`).

#### The Data Flow: Decoupling Generation from Rendering
The system follows a clear data flow that separates data generation from visual rendering:

`Variant Config → Loader → Stimulus Datagram (`stimdg`) → Rendering Function → Visual Display`

The `stimdg` is the central source of truth—a columnar table where each row represents a trial and each column a stimulus parameter. Loaders (defined in `*_loaders.tcl`) populate this datagram, and rendering functions (in `*_stim.tcl`) consume data from it to draw stimuli on the screen. This design allows you to change stimulus logic (in the loader) without touching rendering code, and vice-versa.

### 2. Define the Variant

All variants are defined in `[system]/[protocol]/[protocol]_variants.tcl`. Add a new entry to the `variants` dictionary, which contains:
*   **`description`**: A human-readable description.
*   **`loader_proc`**: The name of the Tcl procedure that will generate the stimulus data.
*   **`loader_options`**: A dictionary of parameters passed to the `loader_proc`.

#### Parameter Types
- **Top-level `loader_options`**: Affect `stimdg` construction (stimulus properties, physics). Values in `{}` become GUI dropdowns.
- **`params` Section**: System-level parameters used by the state machine during trial execution (timing, trial behavior).

### 3. Implement the Loader (`loader_proc`)

Loaders are defined in `[system]/[protocol]/[protocol]_loaders.tcl`. It's best to **use an existing loader** whenever possible. Create a new loader only for fundamentally different logic.

When adding a new parameter to an existing loader:
1.  Update the loader's signature in its `add_method` call.
2.  Pass the new parameter to the data generation function (e.g., `planko::generate_worlds`).
3.  Update all variants using that loader to include the new parameter.

### 4. Test the Variant

Once defined, the variant must be tested.
1.  Test your new variant to ensure it loads and produces the correct `stimdg`.
2.  Test a pre-existing variant that uses the same `loader_proc` (if applicable) to check for regressions.
(For the detailed procedure, see the [Standard Testing Procedure](#standard-testing-procedure) section below.)

---

## API Reference

### CLI Tool: `essctrl`

| Aspect | CLI Interface (`essctrl`) |
| :------- | :----------------------- |
| **Usage** | `essctrl [server] [options]` |
| **Connection** | Connects to `localhost` by default. |
| **Error Format** | Clean error messages to `stdout`. |
| **Exit Codes** | `0` = success, `1` = error. |
| **Service Selection** | `-s` flag for `ess`, `db`, `dserv`, etc. |
| **Execution** | `-c "command"` for one-shot commands. |
| **Output** | Clean output suitable for scripting. |

---
## `ess` Namespace Functions

### System Loading & Discovery

| Command      | Description & Arguments                                                                                                     |
| :----------- | :---------------------------------------------------------------------------------------------------------------------------- |
| `load_system`| `ess::load_system ?system? ?protocol? ?variant?`<br/>Loads a system. Arguments are optional.                                    |
| `find_systems`| `ess::find_systems`<br/>Discovers all available systems.                                                                      |
| `find_protocols`| `ess::find_protocols <system_name>`<br/>Discovers protocols within a system.                                                    |
| `find_variants` | `ess::find_variants <system_name> <protocol_name>`<br/>Discovers variants within a protocol.                                     |

**Examples (Verified):**
```bash
# Load a system
essctrl -c "ess::load_system search"

# Discover systems
essctrl -c "ess::find_systems"
# → emcalib match_to_sample hapticvis search planko

# Discover variants
essctrl -c "ess::find_variants search circles"
# → single variable distractors
```

### State Management & Querying

| Command      | Description                                                     |
| :----------- | :-------------------------------------------------------------- |
| `start`      | `ess::start`<br/>Starts the currently loaded system. No output.  |
| `stop`       | `ess::stop`<br/>Stops the current experiment session. No output. |
| `reset`      | `ess::reset`<br/>Resets the system to its initial state. No output. |
| `query_system`| `ess::query_system`<br/>Returns the name of the loaded system. |
| `query_state` | `ess::query_state`<br/>Returns the current system state (`stopped`, `running`). |

### Parameter Management

| Command | Description |
| :--- | :--- |
| `get_param_vals` | `ess::get_param_vals`<br/>Returns a dictionary of all parameters and their values. |
| `get_param`| `ess::get_param <name>`<br/>Retrieves the value and type of a single parameter. |
| `set_param` | `ess::set_param <name> <val>`<br/>Sets a single parameter. |
| `set_params` | `ess::set_params {...}`<br/>Sets multiple parameters from a key-value list. |

**Example (Verified):**
```bash
# Set a parameter and verify the change
essctrl -c "ess::set_param response_timeout 4000"
essctrl -c "ess::get_param response_timeout"
# → 4000 1 int
```

### Subject & Settings Management

| Command | Description |
| :--- | :--- |
| `set_subject`| `ess::set_subject <id>`<br/>Sets the current subject ID. |
| `get_subject`| `ess::get_subject`<br/>Gets the current subject ID. |
| `save_settings` | `ess::save_settings`<br/>**(Experimental)** Saves settings for the subject. |
| `load_settings` | `ess::load_settings`<br/>**(Experimental)** Loads settings for the subject. |
| `reset_settings`| `ess::reset_settings`<br/>**(Experimental)** Resets settings for the subject. |

**Warning:** The `*_settings` functions perform direct file I/O and may be unstable.

### System Reloading

| Command      | Description                                                     |
| :----------- | :-------------------------------------------------------------- |
| `reload_system` | `ess::reload_system`<br/>Reloads the current system, protocol, and variant. |
| `reload_protocol` | `ess::reload_protocol`<br/>Reloads the current protocol and variant. |
| `reload_variant` | `ess::reload_variant`<br/>Reloads just the current variant's initialization scripts. |

---

## Other Services & Commands

### Data Services (`dg_...`)
| Command     | Description                                                      |
| :---------- | :--------------------------------------------------------------- |
| `dg_toJSON` | `dg_toJSON <datagram_name>`<br/>Retrieves a datagram (e.g., `stimdg`) as JSON. |

### Database Service (`-s db`)
| Command Format | `essctrl -s db -c "db eval {SQL_QUERY}"` |
| :------------- | :--------------------------------------- |

**Example:**
```bash
# Get the 5 most recent trial records from the database
essctrl -s db -c "db eval {SELECT block_id, variant, n_trials FROM trials ORDER BY block_id DESC LIMIT 5}"
```

---

## Standard Testing Procedure

This document outlines the standard procedure for testing new or modified systems, protocols, or variants in the ESS project.

### 1. Load the System

After making changes, the first step is to attempt to load the new or modified configuration using the `ess::load_system` command.

```bash
essctrl -c "ess::load_system <s> <protocol> <variant>"
```

*   **Expected Success**: No output with exit code 0.
*   **Failure**: Clean error message with exit code 1.

### 2. Set Variant Parameters (Optional)

To test a variant with non-default parameters, first load the system as described in Step 1. Then, use the `::ess::set_variant_args` and `::ess::reload_variant` commands to apply the new parameters. The `set_variant_args` command takes a Tcl dictionary of key-value pairs.

```bash
essctrl -c "::ess::set_variant_args {n_rep 200}; ::ess::reload_variant"
```

*   **Expected Success**: No output with exit code 0.

### 3. Inspect the Stimulus Datagram (`stimdg`)

If the system loads successfully, the next step is to inspect the stimulus datagram (`stimdg`) to ensure it has been generated correctly.

```bash
essctrl -c "dg_toJSON stimdg" > lib/stimdg.json
```

*   **Expected Success**: A JSON object saved to `lib/stimdg.json`.

#### Validation Checks

The returned JSON object must be validated against the following criteria:

1.  **Column Presence**: The JSON object must contain all expected columns for the given configuration. (The specific columns will vary depending on the protocol).
2.  **Row Count Consistency**: For a given datagram, there is a primary number of rows, `N`. All columns must contain either `N` rows or 0 rows. An empty datagram (where `N=0` and all columns are empty) is also valid.

A simple way to check for row count consistency is to use the `jq` command-line tool. The following command will display the length of each column array in the datagram:

```bash
jq 'map_values(length)' lib/stimdg.json
```

If these checks pass, the basic integrity of the new/modified configuration is confirmed.

### 4. Complete Session Testing

To fully test the system and verify database recording, perform a complete start/stop session cycle with status monitoring. 

**⚠️ Important**: You must wait for **at least one complete trial** to finish before stopping the session. Otherwise, no trial records will be written to the database.

#### Trial Duration Guidelines

Different systems have different trial durations. Check the system's timing parameters to determine how long to wait:

- **Planko**: Up to ~35 seconds (25s response timeout + 8s feedback + 1s post-feedback + buffer)
- **Search**: Typically 10-15 seconds  
- **Other systems**: Check `response_timeout`, `max_feedback_time`, and `post_feedback_time` parameters

**Rule of thumb**: Wait `response_timeout + max_feedback_time + post_feedback_time + 5 seconds buffer`

#### Step 1: Start Session
```bash
essctrl -c "ess::start"
```

#### Step 2: Check System Status
```bash
essctrl -s db -c "db eval {SELECT status_value FROM status WHERE status_type='status' ORDER BY sys_time DESC LIMIT 1}"
```
*   **Expected**: `running`

#### Step 3: Get Current Block ID
```bash
BLOCK_ID=$(essctrl -s db -c "db eval {SELECT status_value FROM status WHERE status_type='block_id' ORDER BY sys_time DESC LIMIT 1}")
echo "Block ID: $BLOCK_ID"
```
*   **Expected**: A numeric block ID (e.g., `2`, `3`, etc.)

#### Step 4: Wait for Complete Trial
```bash
# For planko (35 seconds)
echo "Waiting 35 seconds for complete trial..."
sleep 35

# For search (15 seconds) 
echo "Waiting 15 seconds for complete trial..."
sleep 15

# Or check timing parameters manually:
# essctrl -c "puts \$response_timeout; puts \$max_feedback_time; puts \$post_feedback_time"
```

#### Step 5: Stop Session
```bash
essctrl -c "ess::stop"
```

#### Step 6: Verify Trial Record
```bash
essctrl -s db -c "db eval {SELECT block_id, state_system, protocol, variant, n_trials, n_complete FROM trials WHERE block_id=\$BLOCK_ID}"
```

*   **Expected**: A record showing the session details. `n_complete` will be 0 if no actual responses were given, but `n_trials` should show the total trials in the block.

---
## See Also

For more information, refer to the following files:

*   [`ess_socket_api.md`](./ess_socket_api.md): Detailed documentation of the API commands.
*   [`ess-2.0.tm`](./ess-2.0.tm): The core server-side Tcl script. **(Reference only, do not modify)**
*   [`tcl_dl.c`](./tcl_dl.c) / [`tcl_dl.h`](./tcl_dl.h): The C source for custom Tcl commands. **(Reference only, do not modify)** 
