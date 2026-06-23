# Stretch Python Unified Environment (Pixi)

This directory contains the version-controlled configuration for the unified development environment used by Stretch software, managed by [Pixi](https://pixi.sh).

## Layout

1. **Configuration (`~/stretch_install/stretch_venv/`)**:
   - `pyproject.toml`: Defines the core Python dependencies (such as `hello-robot-stretch4-urdf` and `hello-robot-stretch4-body`) and build tools (`cmake`, `ninja`, `compilers`).
   - `pixi.lock`: The lockfile containing exact versions, dependencies, and hashes for 100% reproducible installs.
   - `README.md`: This file.

2. **Runtime Environment**:
   - The environment is managed by Pixi and typically resides in the `.pixi` directory within this folder.
   - It is configured to handle both Python packages and system-level build tools required for ROS 2 development.

## Working with the Environment

### Installation

If you haven't installed Pixi yet, run:
```bash
curl -fsSL https://pixi.sh/install.sh | sh
```

To set up or update the environment:
```bash
cd ~/stretch_install/stretch_venv
pixi install
```

### Activating the Environment
The environment is automatically managed. To drop into a shell with the environment active:
```bash
pixi shell
```
Or run commands directly:
```bash
pixi run <command>
```

### Updating Dependencies
If you need to add, remove, or upgrade a package:
1. Update `pyproject.toml` in this directory.
2. Pixi will automatically update the lockfile on the next `install` or `run`.
3. Commit both files to git.
4. Run `pixi install` to apply changes.
