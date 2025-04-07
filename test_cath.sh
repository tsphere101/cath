#!/usr/bin/env bash

# Test script for cath.sh

# --- Configuration ---
# Path to the script being tested. Adjust if necessary.
# Assumes cath.sh is in the same directory as this test script.
SCRIPT_UNDER_TEST="$HOME/cath.sh"
# Base directory for test files
TEST_DIR_BASE="cath_test_env_"
TEST_DIR="" # Will be set by setup

# --- Test State ---
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
ASSERTION_FAILURE=0 # Flag used by assert functions

# --- Colors (Optional) ---
COL_RED="\033[0;31m"
COL_GREEN="\033[0;32m"
COL_YELLOW="\033[0;33m"
COL_RESET="\033[0m"

# --- Helper Functions ---

# Creates the test environment directory and populates it.
setup() {
    TEST_DIR=$(mktemp -d "${TEST_DIR_BASE}XXXXXX")
    if [[ -z "$TEST_DIR" || ! -d "$TEST_DIR" ]]; then echo "FATAL: Failed to create temporary test directory." >&2; exit 1; fi
    if ! pushd "$TEST_DIR" > /dev/null; then echo "FATAL: Failed to change directory to $TEST_DIR" >&2; exit 1; fi

    echo "Content File 1" > file1.txt
    echo "Content File 2" > file2.txt
    mkdir -p subdir/nested
    echo "Subdir File A" > subdir/fileA.txt
    echo "Nested File X" > subdir/nested/fileX.txt
    echo "File With Spaces" > "file with spaces.txt"
    touch empty_file.txt
    echo "Unreadable File Content" > unreadable_file.txt
    chmod 000 unreadable_file.txt
    mkdir unreadable_dir # Create dir first
    echo "Readable In Unreadable Dir" > unreadable_dir/readable.txt
    chmod 111 unreadable_dir # Executable only
    mkdir empty_dir
    ln -s subdir link_to_subdir
    echo "Setup complete in $TEST_DIR" >&2
}

# Cleans up the test environment.
teardown() {
    if [[ -n "$TEST_DIR" && "$PWD" == "$TEST_DIR" ]]; then if ! popd > /dev/null; then echo "Warning: Failed to popd from $TEST_DIR" >&2; fi; fi
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then echo "Cleaning up $TEST_DIR" >&2; rm -rf "$TEST_DIR"; TEST_DIR=""; fi
}

# Trap for cleanup on exit/interrupt
trap teardown EXIT INT TERM

# Function to run a single test case
run_test() {
    local test_name="$1"; ASSERTION_FAILURE=0; ((TEST_COUNT++)); printf "${COL_YELLOW}Running test: %s...${COL_RESET}\n" "$test_name"
    "$test_name"; local test_status=$? # Execute test directly
    if (( ASSERTION_FAILURE == 0 && test_status == 0 )); then printf "${COL_GREEN}PASS: %s${COL_RESET}\n\n" "$test_name"; ((PASS_COUNT++)); else printf "${COL_RED}FAIL: %s (Exit status: %d)${COL_RESET}\n\n" "$test_name" "$test_status"; ((FAIL_COUNT++)); fi
}

# --- Assertion Functions ---
_fail() { local message="$1"; local caller_info; caller_info=$(caller 1 || caller 0); printf "${COL_RED}  Assertion Failed [%s]: %s${COL_RESET}\n" "$caller_info" "$message" >&2; ASSERTION_FAILURE=1; }
assert_success() { local status="$1"; local msg="${2:-"Command expected to succeed (exit 0), but failed with status ${status}"}"; (( status == 0 )) || _fail "$msg"; }
assert_fail() { local status="$1"; local msg="${2:-"Command expected to fail (exit non-0), but succeeded with status ${status}"}"; (( status != 0 )) || _fail "$msg"; }
assert_output_equals() { local actual="$1"; local expected="$2"; local msg="${3:-"Stdout mismatch"}"; local expected_printf; printf -v expected_printf "%s" "$expected"; local actual_printf; printf -v actual_printf "%s" "$actual"; [[ "$actual_printf" == "$expected_printf" ]] || _fail "$msg"$'\n'"  Expected: >${expected_printf}<"$'\n'"  Actual:   >${actual_printf}<"; }
assert_stderr_contains() { local actual_stderr="$1"; local expected_pattern="$2"; local msg="${3:-"Stderr missing expected pattern: '${expected_pattern}'"}"; echo "$actual_stderr" | grep -qF -- "$expected_pattern" || _fail "$msg"$'\n'"  Stderr Content:"$'\n'"${actual_stderr}"; }
assert_stderr_not_contains() { local actual_stderr="$1"; local unexpected_pattern="$2"; local msg="${3:-"Stderr contained unexpected pattern: '${unexpected_pattern}'"}"; ! (echo "$actual_stderr" | grep -qF -- "$unexpected_pattern") || _fail "$msg"$'\n'"  Stderr Content:"$'\n'"${actual_stderr}"; }
assert_file_exists() { local filepath="$1"; local msg="${2:-"Expected file '${filepath}' to exist, but it doesn't"}"; [[ -f "$filepath" ]] || _fail "$msg"; }
assert_file_content_equals() { local filepath="$1"; local expected_content="$2"; local msg="${3:-"File content mismatch for '${filepath}'"}"; if [[ ! -f "$filepath" ]]; then _fail "File '${filepath}' does not exist for content comparison."; return 1; fi; local actual_content; actual_content=$(<"$filepath"); local expected_printf; printf -v expected_printf "%s" "$expected_content"; local actual_printf; printf -v actual_printf "%s" "$actual_content"; [[ "$actual_printf" == "$expected_printf" ]] || _fail "$msg"$'\n'"  Expected: >${expected_printf}<"$'\n'"  Actual:   >${actual_printf}<"; }

# --- Test Cases ---

test_help_option_long() {
    local output status script_name=${SCRIPT_UNDER_TEST##*/}
    output=$("$SCRIPT_UNDER_TEST" --help 2>&1)
    status=$?
    assert_success $status "--help should exit 0"
    assert_output_equals "$output" "$(cat <<EOF
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
)" "Help output mismatch (--help)"
}
test_help_option_short() {
    local output status script_name=${SCRIPT_UNDER_TEST##*/}
    output=$("$SCRIPT_UNDER_TEST" -h 2>&1)
    status=$?
    assert_success $status "-h should exit 0"
    assert_stderr_contains "$output" "Usage: ${script_name}" "Help output missing usage (-h)"
}

test_no_arguments() {
    local stderr_file status stderr script_name=${SCRIPT_UNDER_TEST##*/}
    stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" >/dev/null 2> "$stderr_file"; status=$?; stderr=$(<"$stderr_file"); rm "$stderr_file"
    assert_fail $status "Script should fail with no arguments"
    assert_stderr_contains "$stderr" "Error: No input files or directories specified."
    assert_stderr_contains "$stderr" "Usage: ${script_name}"
}

test_bad_option() {
    local stderr_file status stderr script_name=${SCRIPT_UNDER_TEST##*/}
    stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" --bad-option file1.txt >/dev/null 2> "$stderr_file"; status=$?; stderr=$(<"$stderr_file"); rm "$stderr_file"
    assert_fail $status "Script should fail with bad option"
    assert_stderr_contains "$stderr" "Error: Unknown option '--bad-option'."
    assert_stderr_contains "$stderr" "Usage: ${script_name}"
}

test_o_without_arg() {
    local stderr_file status stderr script_name=${SCRIPT_UNDER_TEST##*/}
    stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" -o >/dev/null 2> "$stderr_file"; status=$?; stderr=$(<"$stderr_file"); rm "$stderr_file"
    assert_fail $status "Script should fail with -o but no filename"
    assert_stderr_contains "$stderr" "Error: -o option requires an output filename."
    assert_stderr_contains "$stderr" "Usage: ${script_name}"
}

test_basic_concat_stdout() {
    local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" file1.txt file2.txt > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"
    assert_success $status "Basic concatenation failed"
    local expected_output
    expected_output=$(cat <<EOF
file1.txt:
Content File 1

file2.txt:
Content File 2

EOF
)
    assert_output_equals "$stdout" "$expected_output"
    assert_stderr_contains "$stderr" "Processing complete. Processed 2 files."
}

test_concat_with_spaces_stdout() {
    local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" "file with spaces.txt" file1.txt > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"
    assert_success $status "Concatenation with spaces failed"
    local expected_output
    expected_output=$(cat <<EOF
file with spaces.txt:
File With Spaces

file1.txt:
Content File 1

EOF
)
    assert_output_equals "$stdout" "$expected_output"
    assert_stderr_contains "$stderr" "Processing complete. Processed 2 files."
}

test_output_to_file() {
    local stderr_file status stderr outfile="output.txt"
    stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" -o "$outfile" file1.txt file2.txt > /dev/null 2> "$stderr_file"; status=$?; stderr=$(<"$stderr_file"); rm "$stderr_file"
    assert_success $status "Output to file command failed"
    assert_file_exists "$outfile" "Output file '$outfile' was not created"
    local expected_content
    expected_content=$(cat <<EOF
file1.txt:
Content File 1

file2.txt:
Content File 2

EOF
)
    assert_file_content_equals "$outfile" "$expected_content"
    assert_stderr_contains "$stderr" "Processing complete. Processed 2 files."
}

test_recursive_concat_stdout() {
    local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" file1.txt subdir > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"
    assert_success $status "Recursive concatenation failed"
    local block1; block1=$(printf '%s\n' "file1.txt:" "Content File 1" "")
    local blockA; blockA=$(printf '%s\n' "subdir/fileA.txt:" "Subdir File A" "")
    local blockX; blockX=$(printf '%s\n' "subdir/nested/fileX.txt:" "Nested File X" "")
    echo "$stdout" | grep -qF -- "$block1" || _fail "Missing block for file1.txt"
    echo "$stdout" | grep -qF -- "$blockA" || _fail "Missing block for subdir/fileA.txt"
    echo "$stdout" | grep -qF -- "$blockX" || _fail "Missing block for subdir/nested/fileX.txt"
    assert_stderr_contains "$stderr" "Processing complete. Processed 3 files."
}

test_recursive_with_link_stdout() {
    local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" file1.txt link_to_subdir > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"
    assert_success $status "Recursive concat with link failed"
    local block1; block1=$(printf '%s\n' "file1.txt:" "Content File 1" "")
    local blockA; blockA=$(printf '%s\n' "link_to_subdir/fileA.txt:" "Subdir File A" "")
    local blockX; blockX=$(printf '%s\n' "link_to_subdir/nested/fileX.txt:" "Nested File X" "")
    echo "$stdout" | grep -qF -- "$block1" || _fail "Missing block for file1.txt (link test)"
    echo "$stdout" | grep -qF -- "$blockA" || _fail "Missing block for link_to_subdir/fileA.txt"
    echo "$stdout" | grep -qF -- "$blockX" || _fail "Missing block for link_to_subdir/nested/fileX.txt"
    assert_stderr_contains "$stderr" "Processing complete. Processed 3 files."
}

test_non_existent_input() {
    local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" non_existent_file file1.txt > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"
    assert_success $status "Should succeed with one valid file and one invalid"
    assert_stderr_contains "$stderr" "Warning: Input item is not a file or directory, or is inaccessible: 'non_existent_file'"
    local expected_output; expected_output=$(cat <<EOF
file1.txt:
Content File 1

EOF
)
    assert_output_equals "$stdout" "$expected_output" "Output should only contain file1.txt"
    assert_stderr_contains "$stderr" "Processing complete. Processed 1 files."
}

test_unreadable_file_input() {
     local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" unreadable_file.txt file1.txt > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"
    assert_success $status "Should succeed with one readable file and one unreadable"
    assert_stderr_contains "$stderr" "Warning: Skipping unreadable input file: 'unreadable_file.txt'"
    local expected_output; expected_output=$(cat <<EOF
file1.txt:
Content File 1

EOF
)
    assert_output_equals "$stdout" "$expected_output" "Output should only contain file1.txt (unreadable test)"
    assert_stderr_contains "$stderr" "Processing complete. Processed 1 files."
}

test_unreadable_subdir() {
    local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    # Try processing the unreadable dir and a readable file
    "$SCRIPT_UNDER_TEST" unreadable_dir file1.txt > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"

    assert_success $status "Should succeed with one readable file (unreadable dir test)"

    local expected_output; expected_output=$(cat <<EOF
file1.txt:
Content File 1

EOF
)
    assert_output_equals "$stdout" "$expected_output" "Output should only contain file1.txt (unreadable dir test)"
    # Still expect it to report processing only 1 file.
    assert_stderr_contains "$stderr" "Processing complete. Processed 1 files."
}

test_quiet_mode() {
    local stderr_file status stderr outfile="quiet_out.txt"
    stderr_file=$(mktemp)
    # Run with -q, -o, and simple valid file inputs
    "$SCRIPT_UNDER_TEST" -q -o "$outfile" file1.txt file2.txt >/dev/null 2> "$stderr_file"
    status=$?; stderr=$(<"$stderr_file"); rm "$stderr_file"
    assert_success $status "Quiet mode command failed (-q -o file1 file2)"
    assert_file_exists "$outfile" "Quiet mode did not create output file"
    # Check that PROGRESS messages are NOT in stderr
    assert_stderr_not_contains "$stderr" "Processing file"
    assert_stderr_not_contains "$stderr" "Progress:"
    assert_stderr_not_contains "$stderr" "Processing complete."
    assert_stderr_not_contains "$stderr" "Proceed? (y/N)"
    # Errors/Warnings *should* still appear if they occur (none expected here)
}

test_empty_dir() {
    local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" empty_dir file1.txt > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"
    assert_success $status "Should succeed with empty dir + valid file"
    local expected_output; expected_output=$(cat <<EOF
file1.txt:
Content File 1

EOF
)
    assert_output_equals "$stdout" "$expected_output" "Output should only contain file1.txt (empty dir test)"
    assert_stderr_contains "$stderr" "Processing complete. Processed 1 files."
}

test_only_empty_dir() {
    local stdout_file stderr_file status stdout stderr
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    "$SCRIPT_UNDER_TEST" empty_dir > "$stdout_file" 2> "$stderr_file"; status=$?; stdout=$(<"$stdout_file"); stderr=$(<"$stderr_file"); rm "$stdout_file" "$stderr_file"
    assert_success $status "Should succeed with only empty dir (exit 0)"
    assert_output_equals "$stdout" "" "Stdout should be empty (only empty dir test)"
    assert_stderr_contains "$stderr" "No readable files found to process."
}

# --- Test Runner ---
if [[ ! -x "$SCRIPT_UNDER_TEST" ]]; then echo "${COL_RED}FATAL: Script under test '$SCRIPT_UNDER_TEST' is not executable or not found.${COL_RESET}" >&2; exit 1; fi
setup # Setup is run once before all tests
declare -a test_functions=( test_help_option_long test_help_option_short test_no_arguments test_bad_option test_o_without_arg test_basic_concat_stdout test_concat_with_spaces_stdout test_output_to_file test_recursive_concat_stdout test_recursive_with_link_stdout test_non_existent_input test_unreadable_file_input test_unreadable_subdir test_quiet_mode test_empty_dir test_only_empty_dir )
for test_func in "${test_functions[@]}"; do if declare -F "$test_func" > /dev/null; then run_test "$test_func"; else printf "${COL_RED}ERROR: Test function '%s' not found! Skipping.${COL_RESET}\n\n" "$test_func"; ((TEST_COUNT++)); ((FAIL_COUNT++)); fi; done
printf "\n--- Test Summary ---\n"; printf "Total Tests: %d\n" "$TEST_COUNT"; printf "${COL_GREEN}Passed:      %d${COL_RESET}\n" "$PASS_COUNT";
if (( FAIL_COUNT > 0 )); then printf "${COL_RED}Failed:      %d${COL_RESET}\n" "$FAIL_COUNT"; exit 1; else exit 0; fi
