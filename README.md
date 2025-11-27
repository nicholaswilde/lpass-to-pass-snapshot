[![task](https://img.shields.io/badge/Task-Enabled-brightgreen?style=for-the-badge&logo=task&logoColor=white)](https://taskfile.dev/#/)

# :arrows_counterclockwise: lpass-to-pass-snapshot :lock:

A Bash utility to perform a one-way snapshot of a LastPass vault (`lpass`) into the standard Unix Password Store (`pass`) or `gopass`.

>[!CAUTION]
>This project is currently under active development. While efforts are made to ensure stability and correctness, some features may be incomplete, or unexpected behavior may occur. Use with caution.

>[!WARNING]
>ONE-WAY OPERATION. This script treats LastPass as the source of truth. It exports the LastPass vault and imports it into the local Password Store. It does not push changes back to LastPass.

## Table of Contents
-   [Features](#features)
-   [Dependencies](#dependencies)
-   [Setup](#setup)
-   [Configuration](#configuration)
-   [Usage](#usage)
-   [Important Warnings](#important-warnings)

## :sparkles: Features
-   One-way snapshot from LastPass to Pass (or Gopass).
-   Customizable password name normalization (lowercase, spaces to hyphens, TLD removal).
-   Backup existing password store before import (optional).
-   Test mode to simulate import without actual changes.
-   **Robust CSV Parsing:** Handles complex CSV fields (including newlines and quoted commas) from LastPass export.
-   **Progress Bar:** Visual feedback during the import process.
-   Command-line argument overrides for configuration.

## :package: Dependencies

This script relies on the following tools:
-   **LastPass CLI (`lpass`):** For exporting your LastPass vault.
    -   [GitHub Repository](https://github.com/LastPass/lastpass-cli)
-   **Unix Password Store (`pass`) or `gopass`:** The target password manager.
    -   [`pass` GitHub Repository](https://github.com/zx2c4/password-store)
    -   [`gopass` GitHub Repository](https://github.com/gopasspw/gopass)
-   **GNU Privacy Guard (`gpg`):** Used by `pass` for encryption and for encrypting backups.
-   **`tar` and `gzip`:** For creating compressed backup archives.
-   **`bash`:** Version 4.0+ is recommended for full compatibility with string manipulation features.
-   **`jq`:**: For parsing json output.

### Installation Examples:

**Debian/Ubuntu:**
```bash
sudo apt update
sudo apt install lastpass-cli password-store gnupg tar gzip jq
```

**macOS (using Homebrew):**
```bash
brew install lastpass-cli password-store gnupg jq
```

**Initialize `pass` or `gopass`:**
If you haven't already, initialize your password store with your GPG key:
```bash
pass init <your_gpg_key_id>
# OR
gopass init
```
Replace `<your_gpg_key_id>` with the ID of your GPG key.

## :hammer_and_wrench: Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/nicholaswilde/lpass-to-pass-snapshot.git
    cd lpass-to-pass-snapshot
    ```
2.  **Make the script executable:**
    ```bash
    chmod +x lpass-to-pass-snapshot.sh
    ```

## :gear: Configuration

This script uses environment variables for sensitive information and customizable settings. A template file `.env.tmpl` is provided to help you set these up.

1.  **Create your `.env` file:**
    Copy the template file to `.env` in the project root:
    ```bash
    cp ./.env.tmpl ./.env
    ```

2.  **Edit `.env`:**
    Open the newly created `.env` file and uncomment/set the variables as needed. These settings can be overridden by command-line flags.

    ```
    # LastPass Username for login, if not already logged in.
    # LPASS_USERNAME="your_lastpass_username"

    # Enable debug logging (true/false)
    DEBUG="false"

    # Enable verbose logging (true/false) - outputs the name of the entry being processed
    VERBOSE="false"

    # Enable backup of the password store before import (true/false)
    ENABLE_BACKUP="false"

    # Directory to store the backup
    BACKUP_DIR="${HOME}"

    # Enable test mode to simulate import without making changes (true/false)
    TEST_MODE="false"
    ```
    Make sure to replace `"your_lastpass_username"` with your actual LastPass username.

## :rocket: Usage

### :computer: Running the script directly

```bash
./lpass-to-pass-snapshot.sh [OPTIONS]
```

Use the `-h` or `--help` flag for a list of available options:
```bash
./lpass-to-pass-snapshot.sh --help
```

#### Available Options

| Flag | Description |
| :--- | :--- |
| `-d`, `--debug` | Enable debug logging. |
| `-v`, `--verbose` | Enable verbose output (print entry names as they are processed). |
| `-b`, `--backup` | Enable backup of the password store before import. |
| `--backup-dir DIR` | Directory to store the backup (default: `$HOME`). |
| `-t`, `--test` | Enable test mode (simulate import without changes). |
| `-u`, `--username NAME` | LastPass username. |
| `-h`, `--help` | Show help message. |

**Example:** Run with a specific username, enable backup, and specify a backup directory.

```bash
./lpass-to-pass-snapshot.sh -u mylastpassuser --backup --backup-dir ~/my_pass_backups
```

**Example:** Run in test mode with debug logging enabled.
```bash
./lpass-to-pass-snapshot.sh --test -d
```

### :white_check_mark: Using Taskfile (Recommended)
This repository includes a `Taskfile.yml` to simplify common operations using the `task` tool.
If you don't have `task` installed, you can find instructions [here](https://taskfile.dev/installation/).

```bash
# List all available tasks
task -l

# Run the lpass-to-pass-snapshot script with default settings
task run

# Run the script in test mode (no actual import to pass)
task test

# Run shellcheck to lint the script
task lint

# Remove generated password store backup files from the default backup directory
task clean-backups
```
You can pass command-line options to `run` and `test` tasks:
```bash
task run -- -u myuser --backup
task test -- -d
```
Note the `--` before script options to separate `task` options from script options.

## :warning: Important Warnings
-   **Sensitive Data Handling:** `lpass export` outputs your LastPass vault content (including passwords) in an unencrypted CSV format to standard output before being piped to `pass`. Ensure your terminal and environment are secure when running this script. Avoid logging sensitive output.
-   **Pass GPG Key:** The script uses the GPG key configured for your `pass` store for both `pass` operations and backup encryption. Ensure this key is available, unlocked (if necessary), and correctly configured for `pass`.
-   **Overwrite Behavior:** The script uses `pass insert -f`, which means it will **overwrite** existing entries in your `pass` store if a new LastPass entry has the same normalized name.
    -   **ALWAYS** use the `--backup` flag to create an encrypted backup of your current `pass` store before running the script.
    -   **ALWAYS** use the `--test` (`-t`) flag first to see what changes would be made without actually importing anything.
-   **One-Way Synchronization:** This script performs a one-way synchronization from LastPass to `pass`. It **does not** push any changes back to LastPass.

## :balance_scale: License

[​Apache License 2.0](https://raw.githubusercontent.com/nicholaswilde/lpass-to-pass-snapshot/refs/heads/main/docs/LICENSE)

## :pencil:​Author

This project was started in 2025 by [Nicholas Wilde][2].

[2]: <https://github.com/nicholaswilde/>
