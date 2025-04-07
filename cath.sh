#!/usr/bin/env bash

#===============================================================================
# cath.sh - Concatenate files recursively with headers and progress.
#
# Concatenates the content of specified files and files found recursively
# within specified directories. Prepends each file's content with its path.
# Provides interactive confirmation for large numbers of files and includes
# a progress bar. Allows output redirection to a file.
#
# Requires Bash 4.4+ for mapfile -d.
#===============================================================================

# --- Configuration ---
# Ask for confirmation if more files than this threshold are found.
readonly CONFIRMATION_THRESHOLD=100
# Width of the progress bar in characters (only shown if stderr is a TTY).
readonly PROGRESS_BAR_WIDTH=40
# Base name for temporary files created when using -o.
readonly TEMP_FILE_BASE="cath_output_"

# --- Global Variable for Cleanup ---
# Stores the path to the temporary file if created via -o.
_temp_output_file=""
# Stores the quiet mode setting for trap access
_opt_quiet=0


# --- Cleanup Function ---
# Ensures the temporary file is removed on script exit (normal or error).
# Also attempts to clear the progress line if the script is interrupted.
cleanup() {
  # Check if stderr is an interactive terminal and quiet mode is off
  if [[ -t 2 ]] && (( _opt_quiet == 0 )); then
     local term_width
     # Use default width if tput fails
     term_width=$(tput cols 2>/dev/null || echo 80)
     # Ensure width is a number
     [[ "$term_width" =~ ^[0-9]+$ ]] || term_width=80
     # Clear the current line in case progress bar was active
     printf "\r%*s\r" "$term_width" "" >&2
  fi
  # Remove the temporary file if it exists and is a file
  if [[ -n "$_temp_output_file" && -f "$_temp_output_file" ]]; then
    rm -f -- "$_temp_output_file"
  fi
}

# --- Register Cleanup ---
# Run the cleanup function on script exit, interrupt, or termination.
trap cleanup EXIT INT TERM


# --- Helper Functions ---

# Prints usage instructions to stderr and exits.
_usage() {
  # Use ${0##*/} to get script name only, making it portable
  local script_name="${0##*/}"
  cat >&2 << EOF
Usage: ${script_name} [-q] [-h] [-o <output_file>] <file_or_dir1> [file_or_dir2] ...

Concatenates files recursively with filename headers.

Arguments:
  <file_or_dir>   One or more files or directories to process recursively.

Options:
  -o <output_file>  Write concatenated output to the specified file instead of stdout.
                    The output file will be overwritten if it exists.
  -q, --quiet       Suppress progress bar and confirmation prompt messages (but not errors).
  -h, --help        Display this help message and exit.
EOF
  # Exit with non-zero status if called due to an error, zero if called via -h
  [[ "$1" == "error" ]] && exit 1 || exit 0
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Draws a text-based progress bar to stderr.
# Arguments: $1:current, $2:total, $3:width
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
_draw_progress_bar() {
    local current=$1 total=$2 width=$3
    # Ensure numeric arguments
    [[ "$current" =~ ^[0-9]+$ ]] || current=0
    [[ "$total" =~ ^[0-9]+$ ]] || total=1 # Avoid division by zero later
    [[ "$width" =~ ^[0-9]+$ ]] || width=10 # Avoid issues if width is bad

    local filled_char="#" empty_char="-"
    local percent filled_width empty_width filled_part empty_part

    (( total <= 0 )) && percent=100 || percent=$(( (current * 100) / total ))
    (( percent > 100 )) && percent=100
    filled_width=$(( (percent * width) / 100 ))
    # Ensure width calculations don't go negative if width is small
    (( filled_width < 0 )) && filled_width=0
    empty_width=$(( width - filled_width ))
    (( empty_width < 0 )) && empty_width=0

    # Assemble the bar string using printf for efficiency
    filled_part=$(printf "%${filled_width}s" "" | tr ' ' "${filled_char}")
    empty_part=$(printf "%${empty_width}s" "" | tr ' ' "${empty_char}")

    # Print the bar to stderr, overwriting the previous line
    printf "\rProgress: [%s%s] %3d%% (%d/%d) " "${filled_part}" "${empty_part}" "$percent" "$current" "$total" >&2
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Prints a single file with its header to stdout.
# Arguments: $1:filepath
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
_print_file_with_header() {
  local filepath="$1"
  # Check readability *just before* reading
  if [[ -r "$filepath" ]]; then
    # Print path as provided (relative or absolute)
    printf "%s:\n" "$filepath"
    # Use cat -- to handle filenames potentially starting with '-'
    cat -- "$filepath"
    printf "\n" # Add an empty line for separation
  else
    # This warning implies a potential race condition or filesystem issue
    # if the file was deemed readable by _gather_files_recursive previously.
    printf "\nWarning: Skipping unreadable file encountered during processing: '%s'\n" "$filepath" >&2
  fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Processes the final list of files after optional confirmation, with progress.
# Arguments: $@: list of file paths
# Environment: Reads _opt_quiet
# Returns: 0 on success, 1 on user cancellation.
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
_process_file_list() {
  # Use local -a for arrays (Bash specific)
  local -a files_to_process=("${@}")
  local file_count=${#files_to_process[@]}
  local filepath confirm current_count=0 is_tty=0

  # Check if stderr is a terminal for progress/prompt decisions
  [[ -t 2 ]] && is_tty=1

  # --- Confirmation Check (only if not quiet and over threshold) ---
  if (( _opt_quiet == 0 )) && (( file_count > CONFIRMATION_THRESHOLD )); then
    # Print prompt to stderr
    printf "==> Found %d files. Proceed? (y/N) " "$file_count" >&2
    # Read from terminal directly if possible for interactive prompt
    read -r confirm < /dev/tty || read -r confirm

    if ! ( [[ "$confirm" == "y" || "$confirm" == "Y" ]] ); then
      # Add newline for clarity before the cancellation message
      printf "\nOperation cancelled by user.\n" >&2
      return 1 # Indicate cancellation
    fi
     # Add newline after 'y' confirmation if interactive, for cleaner subsequent output
    (( is_tty == 1 )) && printf "\n" >&2
  fi

  # --- Initial Progress Bar Draw (if applicable) ---
  if (( is_tty == 1 && _opt_quiet == 0 )); then
      _draw_progress_bar 0 "$file_count" "$PROGRESS_BAR_WIDTH"
  elif (( _opt_quiet == 0 )); then
      # Fallback message if not a TTY and not quiet
      printf "Processing %d files...\n" "$file_count" >&2
  fi

  # --- Process Files ---
  for filepath in "${files_to_process[@]}"; do
    ((current_count++))

    # Output the actual concatenated content (goes to stdout or redirected file)
    _print_file_with_header "$filepath"

    # Update progress bar (only if stderr is a terminal and not quiet)
    if (( is_tty == 1 && _opt_quiet == 0 )); then
        _draw_progress_bar "$current_count" "$file_count" "$PROGRESS_BAR_WIDTH"
    fi
  done

  # --- Finalize progress output ---
  if (( is_tty == 1 && _opt_quiet == 0 )); then
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)
    [[ "$term_width" =~ ^[0-9]+$ ]] || term_width=80
    # Clear the line completely before printing final status
    printf "\r%*s\r" "$term_width" "" >&2
  fi
  # Always print completion message to stderr if not quiet
  if (( _opt_quiet == 0 )); then
     printf "Processing complete. Processed %d files.\n" "$file_count" >&2
  fi

  return 0 # Indicate success
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Recursively finds readable files from input items using POSIX tools.
# Arguments: $@: list of input files or directories
# Output: Prints null-delimited readable file paths to stdout.
# Returns: 0 if successful (even with minor warnings), 1 if a specified
#          input item was invalid/inaccessible. Doesn't fail for find errors
#          within subdirs unless no files are ultimately found.
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
_gather_files_recursive() {
    local item
    local -i errors_found=0 # Track if any *input item* caused an error
    local find_failed=0     # Track if the find|xargs pipeline failed

    for item in "$@"; do
        # Ensure item path exists before type check if it contains slashes,
        # prevents errors if an intermediate directory is missing.
        # Use -e for generic existence check (file, dir, link etc.)
        if [[ "$item" == */* ]] && [[ ! -e "$item" ]]; then
             printf "Warning: Input item path does not exist: '%s'\n" "$item" >&2
             errors_found=1
             continue # Skip to next item
        fi


        if [[ -f "$item" ]]; then
            # Handle regular files provided as input
            if [[ -r "$item" ]]; then
                printf "%s\0" "$item" # Null-delimit output
            else
                # File exists but is not readable
                printf "Warning: Skipping unreadable input file: '%s'\n" "$item" >&2
                errors_found=1 # Mark error for specific input item
            fi
        elif [[ -d "$item" ]]; then
            # Handle directories provided as input
            find_failed=0
            # Use find to locate files (-type f), follow symlinks into dirs (-L), print null-delimited (-print0).
            # Pipe to xargs reading null-delimited input (-0).
            # For each file ({}), execute bash to test readability (-r)
            # If readable, print the filename null-delimited.
            # Errors from find itself (e.g., permission denied on subdir) are sent to /dev/null.
            # Check exit status of the pipeline.
            if ! find -L "$item" -type f -print0 2>/dev/null | xargs -0 -I {} bash -c 'test -r "{}" && printf "%s\0" "{}"' ; then
                # Pipeline failed. Check if find *itself* likely failed (e.g., permission on top dir).
                # This is heuristic, as xargs or bash could also cause failure status.
                if ! find -L "$item" -type f -print0 >/dev/null 2>&1; then
                     printf "Warning: Error searching directory '%s'. Some files might be missed.\n" "$item" >&2
                     # Don't set errors_found=1 here, only if the *input item* was bad.
                     # Let the main logic handle the case where no files are found overall.
                fi
                # If pipeline failed but find alone works, it might be an xargs/bash issue or
                # simply no readable files found (which isn't an error itself).
            fi
        else
            # Handle items that are not regular files or directories, or symlinks to such
            # (after the -e check above for paths with slashes)
            printf "Warning: Input item is not a file or directory, or is inaccessible: '%s'\n" "$item" >&2
            errors_found=1 # Mark error for specific input item
        fi
    done
    # Return non-zero only if a specific input item provided by the user
    # was invalid or inaccessible *at the top level*.
    return $errors_found
}


# --- Main Execution Logic ---
main() {
  # --- Local Variables ---
  local output_file=""
  local -a input_items=()          # Store validated input files/dirs
  local -a all_files_to_process=() # Final list of files to concatenate

  # Ensure _opt_quiet is reset for this run (if script sourced multiple times)
  _opt_quiet=0

  # --- Argument Parsing ---
  while (( $# > 0 )); do
    case "$1" in
      -o)
        if [[ -n "$2" ]]; then
          output_file="$2"
          shift 2 # Consume -o and filename
        else
          printf "Error: -o option requires an output filename.\n" >&2
          _usage "error" # Exit non-zero
        fi
        ;;
      -q|--quiet)
        _opt_quiet=1 # Set global flag used by trap and helpers
        shift 1
        ;;
      # FIX: Add explicit cases for -h and --help
      -h|--help)
        _usage # Display help and exit(0)
        ;;
      --) # End of options marker
        shift
        # Add all remaining arguments as input items
        input_items+=("$@")
        break # Stop parsing options
        ;;
      -*) # Unknown option LAST
        printf "Error: Unknown option '%s'.\n" "$1" >&2
        _usage "error" # Exit non-zero
        ;;
      *) # Positional argument (file or directory)
        input_items+=("$1")
        shift 1
        ;;
    esac
  done

  # --- Input Validation ---
  if (( ${#input_items[@]} == 0 )); then
    printf "Error: No input files or directories specified.\n" >&2
    _usage "error"
  fi

  # --- Gather Files ---
  # Use mapfile (Bash 4.4+) to read null-delimited output from the helper.
  # The helper function prints warnings to stderr directly.
  # Capture helper's exit status to see if any *input items* were invalid.
  local gather_status=0
  mapfile -d '' all_files_to_process < <(_gather_files_recursive "${input_items[@]}") || gather_status=$?
  # Note: gather_status reflects if any *input item* was bad, not necessarily if find failed internally.

  # Check if *any* files were actually found and are readable
   if (( ${#all_files_to_process[@]} == 0 )); then
    printf "No readable files found to process.\n" >&2
    # Exit successfully (0) if input items were valid but yielded no files.
    # Exit with error (1) if the reason for no files was an invalid input item.
    return $gather_status
  fi

  # --- Processing & Output Handling ---
  local process_status=0
  if [[ -n "$output_file" ]]; then
    # --- Output to File ---
    _temp_output_file=$(mktemp -- "${output_file}.XXXXXX" 2>/dev/null || mktemp -t "${TEMP_FILE_BASE}XXXXXX")
    if [[ -z "$_temp_output_file" || ! -f "$_temp_output_file" ]]; then
       printf "Error: Could not create temporary output file.\n" >&2
       return 1 # Exit indicating failure
    fi

    # Process files, redirecting standard output to the temporary file.
    # Use a subshell to capture the exit status reliably.
    ( _process_file_list "${all_files_to_process[@]}" ) > "$_temp_output_file"
    process_status=$? # Capture status of _process_file_list from the subshell

    if (( process_status == 0 )); then
      # Processing was successful (or user confirmed), move temp file to final destination.
      if mv -- "$_temp_output_file" "$output_file"; then
         # Final status message printed by _process_file_list to stderr (if not quiet)
         # Print confirmation of file write to *stdout* for scripting.
         [[ $_opt_quiet -eq 0 ]] && printf "Output successfully written to '%s'\n" "$output_file"
         _temp_output_file="" # Prevent trap from removing the *moved* file
         return 0 # Success
      else
         printf "Error: Could not move temporary file to '%s'. Check permissions.\n" "$output_file" >&2
         # Trap will clean up the temporary file at its original location.
         return 1 # Failure
      fi
    else
      # Processing failed or was cancelled by user (process_status != 0)
      # Status message already printed by _process_file_list to stderr (if not quiet)
      # Trap will clean up the temporary file.
      return $process_status
    fi
  else
    # --- Output to Standard Output ---
    _process_file_list "${all_files_to_process[@]}"
    process_status=$? # Capture status
    return $process_status
  fi
}

# --- Execute Main Function ---
# Pass all script arguments ("$@") to the main function.
# The script's exit code will be the return code from main().
main "$@"
