# Stretch Python Virtual Environment Configuration

This directory contains the version-controlled configuration for the Python virtual environment used by Stretch software.

## Layout

1. **Configuration (`~/stretch_install/stretch_venv/`)**:
   - `pyproject.toml`: Defines the core Python dependencies (such as `hello-robot-stretch4-urdf` and `hello-robot-stretch4-body`).
   - `uv.lock`: The lockfile containing exact versions, dependencies, and hashes for 100% reproducible installs.
   - `README.md`: This file.

2. **Runtime Environment (`~/stretch_user/stretch_venv/`)**:
   - The actual virtual environment containing the Python interpreter, libraries, and binaries. It is built locally during installation and is excluded from git version control.
   - Created with `--system-site-packages` to enable seamless integration with system ROS 2 Jazzy packages (like `rclpy`).

## Working with the Environment

### Activating the Environment
The environment is automatically activated in every new interactive shell via `~/.bashrc`. To activate it manually:
```bash
source ~/stretch_user/stretch_venv/bin/activate
```

### Updating Locked Dependencies
If you need to add, remove, or upgrade a package:
1. Update `pyproject.toml` in this directory.
2. Run `uv lock` from this directory to update `uv.lock`.
3. Commit both files to git.
4. Run the update script (`./stretch_update_user.sh` or `uv sync --frozen`) to apply changes to `~/stretch_user/stretch_venv/`.
