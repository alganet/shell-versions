# Shell Versions Project - AI Coding Assistant Instructions

## Project Overview

This project builds Docker images containing multiple versions of multiple shell interpreters (bash, dash, zsh, ksh, mksh, oksh, loksh, yash, yashrs, osh, brush, busybox, posh). It's designed for testing portable shell scripts across different shell versions and implementations.

## Architecture

### Core Components

- **`shvr.sh`**: Central build orchestration script that dynamically loads variant definitions and executes subcommands
- **`variants/*.sh`**: Shell-specific build definitions (one file per shell type like `bash.sh`, `dash.sh`, etc.)
- **`build/`**: Host location for source tarballs and patches organized by shell type and version.
- **GitHub Actions**: Automated workflow generation for building and publishing Docker images

### The Build System

The system uses a function-based pattern where each variant defines required functions:

```sh
shvr_current_<shell>    # Lists the 2 most recent versions for "latest" image
shvr_targets_<shell>    # Lists all versions to build for "all" image
shvr_download_<shell>   # Downloads source tarballs and patches
shvr_build_<shell>      # Compiles and installs the shell
shvr_versioninfo_<shell> # Optional: Parses version strings (sets version_baseline for caching)
```

Example: `bash_5.2.37` means bash version 5.2 with 37 patches applied.

### Version Naming Convention

Format: `<shell>_<version>` where version may include:
- Simple versions: `dash_0.5.13`
- Versions with patches: `bash_5.2.37` (baseline 5.2 + 37 patches)
- Fork variants: `ksh_shvrA93uplusm-v1.0.10` (fork identifier + version)

## Key Workflows

### Adding a New Shell Version

1. Edit the appropriate `variants/<shell>.sh` file
2. Add version to `shvr_targets_<shell>` function (keep sorted by version)
3. Add version to `shvr_current_<shell>` if it's one of the two most recent
4. Regenerate GitHub workflows: `sh shvr.sh github_regen_all`
5. Test locally: `sh shvr.sh download <shell>_<version>` then `sh shvr.sh build <shell>_<version>`

### Auto-Generating GitHub Workflows

**Critical**: The `.github/workflows/*.yml` and `.github/actions/downloads/action.yml` files have auto-generated sections marked with `# AUTO-GENERATED LIST. DO NOT EDIT MANUALLY.`

Regenerate after changing versions:
```sh
sh shvr.sh github_regen_all
```

This updates:
- `docker-all.yml`: All versions for the `:all` image
- `docker-test.yml` & `docker-latest.yml`: Current versions only
- `actions/downloads/action.yml`: Download steps with caching

### Local Building (Example)

```sh
# List all available targets
sh shvr.sh targets

# Download sources for specific versions
sh shvr.sh download bash_5.3 dash_0.5.13

# Build specific versions
sh shvr.sh build bash_5.3 dash_0.5.13

# Build Docker image
docker build -t test-image --build-arg TARGETS="bash_5.3 dash_0.5.13" .
```

## Project-Specific Patterns

### Version Parsing with `shvr_versioninfo_<shell>`

For shells with idiosyncratic versions (like bash), implement `shvr_versioninfo_<shell>` to set:
- `version_baseline`: Base version for tarball downloading (e.g., "5.2" from "5.2.37")
- `version_major`, `version_minor`, `version_patch`: Parsed components
- `fork_name`, `fork_version`: For forked shells like ksh variants

Versioning parsing is crucial for caching downloads and applying patches correctly.

### Patch Application Pattern (Bash Only)

Bash downloads a baseline tarball plus individual patch files, then applies them sequentially:
```sh
# Download bash-5.2.tar.gz plus bash52-001 through bash52-037
# Extract tarball, apply patches in order with patch(1)
```

### Rust-Based Shells (brush, yashrs)

These shells install Rust toolchain once and cache `$HOME/.cargo/env`:
```sh
if ! test -f "$HOME/.cargo/env"
then curl -o "$HOME/rustup.sh" --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs
     sh rustup.sh -y
fi
. "$HOME/.cargo/env"
cargo build --release
```

### POSIX Compatibility

All scripts use POSIX shell syntax (#!/usr/bin/env sh) and must work with dash/busybox. Avoid bashisms.

## File Organization

- **Built binaries**: Installed to `${SHVR_DIR_OUT}/<shell>_<version>/bin/<shell>`
- **Build sources**: Downloaded to `${SHVR_DIR_SRC}/<shell>/<version>`
- **Patches**: Stored in `build/<shell>/<baseline>-patches/` directory

## Testing

Ensure the distfile is present:
```sh
shvr.sh download bash_5.3
```

Build the desired image:
```sh
docker build -t test-image --build-arg TARGETS="bash_5.3" .
```

Run a specific shell version:
```sh
docker run -it --rm alganet/shell-versions /opt/bash_5.3/bin/bash -c "echo test"
```

List all available shells:
```sh
docker run -it --rm alganet/shell-versions find /opt -type f
```

## Common Pitfalls

- **Don't manually edit auto-generated sections** in workflow files
- **Always run `github_regen_all`** after changing version lists
- **Test downloads separately** before building (network errors are common)
- **Version sorting matters**: Use `--version-sort` when listing versions
- **Some old versions need specific dependencies**: Check existing `shvr_build_*` functions for apt-get patterns
