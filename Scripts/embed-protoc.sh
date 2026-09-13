#!/bin/bash
set -euo pipefail

# Embeds a build-machine protoc helper plus well-known .proto imports into the app
# bundle. Sandboxed macOS apps cannot execute host-installed tools, even when PROTOC
# is set in the shell or Xcode scheme environment.

APP_BUNDLE="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
HELPERS_DIR="${APP_BUNDLE}/Contents/Helpers"
LIB_DIR="${HELPERS_DIR}/lib"
WELL_KNOWN_DIR="${APP_BUNDLE}/Contents/Resources/well-known"

resolve_protoc_source() {
    local candidate

    if [[ -n "${PROTOC:-}" && -x "${PROTOC}" && "${PROTOC}" != "${APP_BUNDLE}"* ]]; then
        echo "${PROTOC}"
        return 0
    fi

    for candidate in \
        /opt/homebrew/bin/protoc \
        /usr/local/bin/protoc \
        /opt/local/bin/protoc; do
        if [[ -x "${candidate}" && "${candidate}" != "${APP_BUNDLE}"* ]]; then
            echo "${candidate}"
            return 0
        fi
    done

    if command -v protoc >/dev/null 2>&1; then
        candidate="$(command -v protoc)"
        if [[ -x "${candidate}" && "${candidate}" != "${APP_BUNDLE}"* ]]; then
            echo "${candidate}"
            return 0
        fi
    fi

    return 1
}

if ! PROTOC_SOURCE="$(resolve_protoc_source)"; then
    echo "warning: protoc was not found while embedding helpers. Install protobuf (for example \`brew install protobuf\`) or set PROTOC, then rebuild. Sandboxed Fetcher cannot use a host-installed protoc at runtime."
    exit 0
fi

rm -rf "${HELPERS_DIR}" "${WELL_KNOWN_DIR}"
mkdir -p "${HELPERS_DIR}" "${LIB_DIR}" "${WELL_KNOWN_DIR}"

python3 - "${PROTOC_SOURCE}" "${HELPERS_DIR}" "${LIB_DIR}" "${WELL_KNOWN_DIR}" <<'PY'
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

protoc_source = Path(sys.argv[1]).resolve()
helpers_dir = Path(sys.argv[2])
lib_dir = Path(sys.argv[3])
well_known_dir = Path(sys.argv[4])
protoc_dest = helpers_dir / "protoc"

if protoc_source == protoc_dest.resolve():
    raise SystemExit(f"refusing to embed protoc from its own output path: {protoc_source}")

def otool_load_commands(path: Path) -> list[str]:
    output = subprocess.check_output(["otool", "-L", str(path)], text=True)
    deps: list[str] = []
    for line in output.splitlines()[1:]:
        dep = line.strip().split(" (", 1)[0]
        if dep == str(path):
            continue
        deps.append(dep)
    return deps

def resolve_dependency(dep: str, owner: Path, protobuf_lib_dir: Path) -> Optional[Path]:
    if dep.startswith("/"):
        path = Path(dep)
        return path if path.exists() else None

    if dep.startswith("@rpath/"):
        name = dep.removeprefix("@rpath/")
        candidate = protobuf_lib_dir / name
        if candidate.exists():
            return candidate
        return None

    if dep.startswith("@loader_path/"):
        base = owner.parent
        suffix = dep.removeprefix("@loader_path/")
        candidate = (base / suffix).resolve()
        return candidate if candidate.exists() else None

    return None

def collect_dependencies(root: Path, protobuf_lib_dir: Path) -> list[Path]:
    seen: set[Path] = set()
    queue: list[Path] = [root]

    while queue:
        current = queue.pop()
        current = current.resolve()
        if current in seen:
            continue
        seen.add(current)

        for dep in otool_load_commands(current):
            resolved = resolve_dependency(dep, current, protobuf_lib_dir)
            if resolved is not None:
                queue.append(resolved)

    return sorted(seen)

def rewrite_dependency(binary: Path, old: str, new: str) -> None:
    subprocess.check_call(["install_name_tool", "-change", old, new, str(binary)])

def add_rpath(binary: Path, rpath: str) -> None:
    existing = subprocess.check_output(["otool", "-l", str(binary)], text=True)
    if rpath in existing:
        return
    subprocess.check_call(["install_name_tool", "-add_rpath", rpath, str(binary)])

protobuf_root = protoc_source.parent.parent
protobuf_lib_dir = protobuf_root / "lib"
include_root = protobuf_root / "include"

shutil.copy2(protoc_source, protoc_dest)
os.chmod(protoc_dest, 0o755)

dependencies = collect_dependencies(protoc_dest, protobuf_lib_dir)
copied_names: set[str] = set()
for dependency in dependencies:
    if dependency == protoc_dest:
        continue
    destination = lib_dir / dependency.name
    if not destination.exists():
        shutil.copy2(dependency, destination)
    copied_names.add(destination.name)

for binary in [protoc_dest, *sorted(lib_dir.iterdir())]:
    for dep in otool_load_commands(binary):
        basename = Path(dep).name
        if basename not in copied_names:
            continue
        bundled = f"@executable_path/lib/{basename}"
        if dep != bundled:
            rewrite_dependency(binary, dep, bundled)
    add_rpath(binary, "@executable_path/lib")

google_proto_src = include_root / "google" / "protobuf"
google_proto_dest = well_known_dir / "google" / "protobuf"
if google_proto_src.is_dir():
    if google_proto_dest.exists():
        shutil.rmtree(google_proto_dest)
    shutil.copytree(google_proto_src, google_proto_dest)
else:
    print(f"warning: well-known protobuf includes not found at {google_proto_src}")

print(f"embedded protoc at {protoc_dest}")
PY
