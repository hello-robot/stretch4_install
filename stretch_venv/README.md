# Stretch Unified Environment (Pixi + RoboStack)

This directory contains the version-controlled configuration for the unified
environment used by Stretch software, managed by [Pixi](https://pixi.sh).

**Everything lives in this one environment**, including ROS 2 Jazzy itself,
which comes from [RoboStack](https://robostack.github.io) (conda-forge builds of
ROS 2) rather than from apt. There is no `/opt/ros/jazzy`, and `rosdep install`
is not used: ROS packages are declared in `pyproject.toml` and locked in
`pixi.lock` like any other dependency.

## Layout

1. **Configuration (`~/stretch4_install/stretch_venv/`)**:
   - `pyproject.toml`: Defines the Python dependencies (such as
     `hello-robot-stretch4-urdf` and `hello-robot-stretch4-body`), the build
     tools (`cmake`, `ninja`, `compilers`), and ROS 2 Jazzy (`ros-jazzy-*` from
     the `robostack-jazzy` channel).
   - `pixi.lock`: The lockfile containing exact versions, dependencies, and
     hashes for 100% reproducible installs.
   - `setup_venv.sh`: Bootstraps or restores the environment, then verifies it
     (including asserting NumPy 2 — see below).
   - `update_bashrc.sh`: Adds the activation block to `~/.bashrc`.
   - `README.md`: This file.

2. **Runtime Environment**:
   - The environment lives in `.pixi/envs/default` within this folder.
   - Activating it is what sets `ROS_DISTRO`, `AMENT_PREFIX_PATH`, and puts
     `ros2`, `colcon`, `vcs`, and `rosdep` on the `PATH`.
   - The locally built workspace in `~/ament_ws` is overlaid on top of it.

## NumPy 2

NumPy 2 is required, and it is a real constraint rather than a preference:
RoboStack publishes two build variants of every ROS package, `np126py312*`
(capped at `numpy <2.0a0`) and `np2py312*` (`numpy >=1.25,<3`). The
`numpy = ">=2.0.0,<3.0.0"` pin in `pyproject.toml` is what forces the solver
onto the `np2py312*` variants, together with `ros2-distro-mutex >=0.15.0`
(`jazzy_18` and newer are the NumPy 2 build series).

Do not relax either constraint. `setup_venv.sh` fails loudly if the resulting
environment ends up with NumPy 1.x.

## Working with the Environment

### Installation

If you haven't installed Pixi yet, run:
```bash
curl -fsSL https://pixi.sh/install.sh | sh
```

To set up or update the environment:
```bash
~/stretch4_install/stretch_venv/setup_venv.sh
```

That wraps `pixi install` and adds the post-install verification. A first
install downloads roughly 1.5 GB, most of it ROS 2.

### Activating the Environment
Interactive shells activate it automatically via the block that
`update_bashrc.sh` adds to `~/.bashrc`. To drop into a shell with the
environment active explicitly:
```bash
cd ~/stretch4_install/stretch_venv
pixi shell
```
Or run commands directly:
```bash
pixi run <command>
```

For systemd units and other non-interactive contexts that do not read
`~/.bashrc`, use the wrapper, which activates the environment and the
`~/ament_ws` overlay before exec'ing the command:
```bash
~/stretch4_install/factory/24.04/run_in_stretch_env.sh ros2 topic list
```

### Adding a ROS dependency
A new dependency in some package's `package.xml` is **not** resolved by
`rosdep`. Instead:

1. If RoboStack ships it (search <https://robostack.github.io>), add
   `ros-jazzy-<name-with-dashes> = "*"` to `[tool.pixi.dependencies]` here.
2. If it does not, add the upstream repository to
   `factory/24.04/stretch_ros2_jazzy.repos` so it is built from source in
   `~/ament_ws`. `simple_actions` and `tf2_web_republisher` are handled this
   way.

`factory/24.04/stretch_create_ament_workspace.sh` runs
`check_workspace_dependencies.py`, which reports any `package.xml` dependency
the environment does not satisfy.

### Updating Dependencies
If you need to add, remove, or upgrade a package:
1. Update `pyproject.toml` in this directory.
2. Pixi will automatically update the lockfile on the next `install` or `run`.
3. Run `pixi install` to apply changes, and confirm NumPy is still 2.x.
4. Commit both files to git.
