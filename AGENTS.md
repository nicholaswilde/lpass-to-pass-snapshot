# lpass-to-pass-snapshot

## Project Overview
`lpass-to-pass-snapshot` is a Bash utility designed to perform a robust, one-way snapshot of a LastPass vault (`lpass`) into the standard Unix Password Store (`pass`) or `gopass`. It treats LastPass as the source of truth and overwrites matching entries in the local password store.

**Key Features:**
*   **One-Way Sync:** Imports data from LastPass to `pass`.
*   **Safety:** Supports dry-run mode (`--test`) and creates encrypted backups of the existing password store before modifications.
*   **Robustness:** Handles complex CSV exports from LastPass (including multiline notes) and normalizes entry names.
*   **Performance:** Temporarily disables Git integration in `pass` to speed up bulk imports, performing a single commit at the end.
*   **Feedback:** Includes a progress bar and supports email notifications via Mailrise.

## Building and Running

This project is a Bash script and does not require a compilation step. However, it relies on several system dependencies.

### Prerequisites
Ensure the following tools are installed:
*   `lpass` (LastPass CLI)
*   `pass` or `gopass`
*   `gpg`
*   `jq`
*   `tar`, `gzip`

### Taskfile
The project uses `task` (Taskfile) for common operations.

*   **Run Script:** `task run` (or `./lpass-to-pass-snapshot.sh`)
*   **Test Mode (Dry Run):** `task test` (or `./lpass-to-pass-snapshot.sh --test`)
*   **Lint Code:** `task lint` (runs `shellcheck`)
*   **Clean Backups:** `task clean-backups`

### Configuration
1.  Copy the template: `cp .env.tmpl .env`
2.  Edit `.env` to configure settings like `LPASS_USERNAME`, `ENABLE_BACKUP`, and notification details.

## Development Conventions

**General:**
*   **Language:** Strict Bash (no Python or other scripting languages).
*   **Style Guide:** Adhere to the Google Shell Style Guide, with specific project overrides found in `AGENTS.md`.

**Coding Style:**
*   **Shebang:** `#!/usr/bin/env bash`
*   **Safety:** Always use `set -e` and `set -o pipefail`.
*   **Formatting:** 2 spaces for indentation.
*   **Functions:** Declare with `function name { ... }`.
    *   `main` function must be at the bottom and called with `"$@"`.
    *   Helper functions defined before `main`.
*   **Variables:**
    *   Global/Env variables: `UPPER_CASE`
    *   Local variables: `lower_case`
    *   Constants: `readonly MY_CONST="value"` (defined after header).
*   **Logging:** Use the provided `log` function instead of `echo`.
    *   `INFO` (Blue), `WARN` (Yellow), `ERRO` (Red), `DEBU` (Purple).
*   **Dependencies:** Check all dependencies using `commandExists` at the start.
*   **File Operations:** Be extremely cautious with `rm`. Never use `rm -rf` without strict variable validation.

**Documentation:**
*   Update `README.md` with any new features or flags.
*   Use GitHub emoji shortcodes (e.g., `:sparkles:`) in Markdown.
