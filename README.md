# cath.sh - Recursive File Concatenator with Headers

A Bash script to recursively find and concatenate readable files from specified directories and files, prepending each file's content with a customizable header (defaulting to the file path). Includes features like progress bars, confirmation prompts, and output redirection.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) <!-- Optional: Add a license badge if you add a LICENSE file -->

## Features

- Recursively searches directories for readable files.
- Concatenates the content of found files in the order provided/found.
- Adds a header line (default: file path) before each file's content for easy identification.
- **Customizable header format** using the `-H` option with placeholders:
  - `%p`: Full path of the file
  - `%f`: Basename (filename only) of the file
  - `%d`: Directory containing the file
  - `%%`: A literal percent sign (`%`)
- Displays an interactive **progress bar** when outputting to a terminal (`stderr`).
- Prompts for **confirmation** if processing a large number of files (>100 by default).
- Option to **output** the concatenated result to a specified file (`-o <filename>`).
- **Quiet mode** (`-q`) to suppress progress bar and confirmation messages (errors are still shown).
- Standard **help message** (`-h`, `--help`).
- Handles filenames with spaces and special characters.
- Attempts to securely handle temporary files when using `-o`.
- Includes basic error handling for inaccessible files/directories.

## Requirements

- **Bash:** Version **4.4+** is required due to the use of `mapfile -d`. Check with `bash --version`.
- **Standard Unix/Linux command-line tools:** `find`, `cat`, `xargs`, `grep`, `chmod`, `mktemp`, `mv`, `rm`, `tput` (optional, for better progress bar visuals), `tr`. These are typically available on most Linux distributions and macOS.

## Installation

1.  **Clone or Download:**

    ```bash
    # Using Git (Recommended)
    git clone https://github.com/<your-username>/<your-repo-name>.git
    cd <your-repo-name>

    # Or download the cath.sh file directly
    # wget https://raw.githubusercontent.com/<your-username>/<your-repo-name>/main/cath.sh
    ```

2.  **Make Executable:**
    ```bash
    chmod +x cath.sh
    ```
3.  **Place in PATH (Optional):**
    For easier access, move or link `cath.sh` to a directory in your system's `$PATH`:

    ```bash
    # Example: Move to /usr/local/bin (may require sudo)
    # sudo mv cath.sh /usr/local/bin/cath

    # Example: Move to a personal bin directory (ensure ~/bin is in your PATH)
    # mkdir -p ~/bin
    # mv cath.sh ~/bin/cath
    ```

    Alternatively, create an alias in your shell's configuration file (e.g., `~/.bashrc`, `~/.zshrc`):

    ```bash
    # Example alias
    alias cath='/full/path/to/your/cath.sh'
    ```

    Remember to source your config file (`source ~/.zshrc`) or restart your shell after adding an alias.

## Usage

```bash
cath.sh [-q] [-h] [-o <output_file>] [-H <format>] <file_or_dir1> [file_or_dir2] ...
```

**Arguments:**

- `<file_or_dir>`: One or more files or directories to process. Directories will be searched recursively for readable files. The order of arguments influences the order of concatenation for files specified directly; files found within directories are typically processed in the order returned by `find`.

**Options:**

- `-o <output_file>`: Write the combined output to `<output_file>` instead of printing to standard output. The file will be **overwritten** if it exists. A temporary file is used during processing to avoid data loss if the script is interrupted.
- `-H <format>`: Use a custom format string for the header printed before each file's content. See "Header Format Placeholders" below for available substitutions. If this option is omitted, the default header used is the file path followed by a colon (equivalent to `-H '%p:'`).
- `-q`, `--quiet`: Run silently. Suppresses the interactive progress bar (if stderr is a terminal) and the confirmation prompt normally shown when processing a large number of files (default >100). Error messages and final status messages (like "Output successfully written...") are **not** suppressed.
- `-h`, `--help`: Display this help message and exit immediately.

**Header Format Placeholders (for `-H <format>`):**

These placeholders are substituted within the format string provided to the `-H` option:

- `%p`: Replaced with the full, potentially relative or absolute, path to the current file as found by the script (e.g., `src/utils/helpers.js`, `/etc/hosts`).
- `%f`: Replaced with the basename of the file (the filename component only, e.g., `helpers.js`, `hosts`).
- `%d`: Replaced with the directory path containing the file (e.g., `src/utils`, `/etc`). For files in the current directory, this will be `.`.
- `%%`: Replaced with a single literal percent sign (`%`). Use this if you need to include a percent sign in your custom header.

## Examples

````bash
# Concatenate two specific files to the terminal (default header)
./cath.sh /etc/hosts /etc/resolv.conf

# Concatenate all readable files in the 'src' directory recursively
./cath.sh src/

# Concatenate files and directories, outputting to a log file
./cath.sh main.log config.txt logs/ -o combined.log

# Use a custom header showing only the filename, surrounded by markers
./cath.sh -H "=== START FILE: %f ===" src/ project.conf

# Use a more complex custom header with directory and full path
./cath.sh -H "[DIR: %d | FILE: %f | FULL: %p]" notes.txt data/

# Include a literal percentage sign in the header
./cath.sh -H "File: %f (100%% Complete!)" report.txt

# Process a potentially large directory quietly, outputting to a file
# (No progress bar, no confirmation prompt)
./cath.sh -q -o system_logs.txt /var/log```

## Testing

A test script (`test_cath.sh`) is included in the repository to verify the core functionality and options of `cath.sh`.

1.  Ensure both `cath.sh` and `test_cath.sh` are present and executable:
    ```bash
    chmod +x cath.sh test_cath.sh
    ```
2.  Run the test script from the same directory:
    ```bash
    ./test_cath.sh
    ```
    The script will create a temporary environment, execute a series of tests covering different scenarios (basic concatenation, recursion, options like `-o`, `-q`, `-h`, error conditions), report PASS or FAIL for each, and provide a final summary. It exits with status 0 if all tests pass, and 1 otherwise.
````
