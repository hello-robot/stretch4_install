#!/usr/bin/env python3
"""Check an ament workspace's package.xml dependencies against the active
(pixi/RoboStack) environment.

This replaces `rosdep install` for the Stretch workspace. ROS 2 Jazzy and every
ROS dependency now come from RoboStack inside the pixi environment, declared in
stretch_venv/pyproject.toml, so there is nothing to install at build time --
only something to verify. Anything reported here needs either a new entry in
pyproject.toml (if RoboStack ships it) or a new entry in
stretch_ros2_jazzy.repos (if it has to be built from source).

Exits non-zero only if a dependency is genuinely unsatisfied.
"""

import importlib.util
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

DEPEND_TAGS = (
    "depend",
    "build_depend",
    "buildtool_depend",
    "build_export_depend",
    "buildtool_export_depend",
    "exec_depend",
    "test_depend",
    "run_depend",
)

# rosdep keys that are not ROS packages. Each maps to the python module or the
# file inside $CONDA_PREFIX that proves it is present, or to None for keys that
# are satisfied by an apt package outside the environment.
NON_ROS_KEYS = {
    "eigen": ("file", "include/eigen3/Eigen/Core"),
    "fmt": ("file", "lib/libfmt.so"),
    "libopencv-dev": ("file", "lib/libopencv_core.so"),
    "python-pytorch-pip": ("module", "torch"),
    "python-transforms3d-pip": ("module", "transforms3d"),
    "python3-deprecated": ("module", "deprecated"),
    "python3-jinja2": ("module", "jinja2"),
    "python3-numpy": ("module", "numpy"),
    "python3-opencv": ("module", "cv2"),
    "python3-pytest": ("module", "pytest"),
    "python3-scipy": ("module", "scipy"),
    "python3-seaborn": ("module", "seaborn"),
    "python3-transforms3d": ("module", "transforms3d"),
    "python3-trimesh-pip": ("module", "trimesh"),
    "python3-yaml": ("module", "yaml"),
    # System (apt) packages, installed by stretch_install_system.sh.
    "xterm": ("apt", "xterm"),
}


def collect(src_dir: Path):
    """Return (workspace package names, {dep key: {declaring package.xml}})."""
    local, deps = set(), {}
    ros_version = os.environ.get("ROS_VERSION", "2")
    for manifest in sorted(src_dir.glob("**/package.xml")):
        # Skip anything under a build/install artifact directory.
        if any(part in ("build", "install", "log") for part in manifest.parts):
            continue
        try:
            root = ET.parse(manifest).getroot()
        except ET.ParseError as exc:
            print(f"  WARNING: could not parse {manifest}: {exc}")
            continue
        name = root.find("name")
        if name is not None and name.text:
            local.add(name.text.strip())
        for tag in DEPEND_TAGS:
            for element in root.findall(tag):
                if not element.text:
                    continue
                # package.xml format 3 conditionals, e.g. ROS 1 only deps.
                condition = element.get("condition")
                if condition and f"$ROS_VERSION == {ros_version}" not in condition:
                    continue
                deps.setdefault(element.text.strip(), set()).add(
                    str(manifest.relative_to(src_dir))
                )
    return local, deps


def ros_packages():
    try:
        out = subprocess.run(
            ["ros2", "pkg", "list"], capture_output=True, text=True, timeout=180
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"  WARNING: could not run 'ros2 pkg list': {exc}")
        return set()
    return set(out.stdout.split())


def module_in_prefix(name, prefix: Path):
    """True only if `name` is importable FROM `prefix`.

    A plain find_spec() is not enough: user site-packages
    (~/.local/lib/pythonX.Y/site-packages) stays on sys.path even under
    `env -i`, so a stale `pip install --break-system-packages` of a package
    outside the environment would be reported as satisfied here and then be
    missing on a clean robot. Insist the module actually lives in the
    environment.
    """
    try:
        spec = importlib.util.find_spec(name)
    except (ImportError, ValueError):
        return False
    if spec is None:
        return False
    locations = []
    if spec.origin:
        locations.append(spec.origin)
    if spec.submodule_search_locations:
        locations.extend(spec.submodule_search_locations)
    prefix_str = str(prefix)
    return any(str(loc).startswith(prefix_str) for loc in locations)


def satisfied_non_ros(key, prefix: Path):
    kind, value = NON_ROS_KEYS[key]
    if kind == "module":
        return module_in_prefix(value, prefix)
    if kind == "file":
        return (prefix / value).exists()
    if kind == "apt":
        # Not in the environment by design; only warn if it is missing entirely.
        return subprocess.run(
            ["dpkg-query", "-W", value], capture_output=True
        ).returncode == 0
    raise AssertionError(kind)


def main():
    src_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "src").resolve()
    prefix = Path(os.environ.get("CONDA_PREFIX", sys.prefix))

    local, deps = collect(src_dir)
    available = ros_packages()

    missing = []
    for key in sorted(deps):
        if key in local or key in available:
            continue
        if key in NON_ROS_KEYS:
            if satisfied_non_ros(key, prefix):
                continue
        missing.append(key)

    print(
        f"  {len(local)} workspace packages, {len(deps)} declared dependencies, "
        f"{len(available)} ROS packages in {prefix}"
    )
    if not missing:
        print("  All workspace dependencies are satisfied by the pixi environment.")
        return 0

    print("")
    print("  UNSATISFIED DEPENDENCIES:")
    for key in missing:
        declarers = ", ".join(sorted(deps[key]))
        print(f"    {key}  (required by {declarers})")
    print("")
    print("  Fix by either:")
    print("    - adding 'ros-jazzy-<name-with-dashes>' to stretch_venv/pyproject.toml,")
    print("      if RoboStack ships it (search https://robostack.github.io), or")
    print("    - adding the upstream repository to stretch_ros2_jazzy.repos so that")
    print("      it is built from source in this workspace.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
