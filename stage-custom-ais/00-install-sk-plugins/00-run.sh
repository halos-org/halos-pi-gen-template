#!/bin/bash -e
set -o pipefail

# The pi-gen builder container doesn't include python3 by default.
apt-get update -qq && apt-get install -y -qq python3 >/dev/null

SK_DATA="${ROOTFS_DIR}/var/lib/container-apps/marine-signalk-server-container/data/data"
PLUGIN_NAME="ais-forwarder"
PLUGIN_VERSION="0.4.1"
TARBALL_URL="https://registry.npmjs.org/${PLUGIN_NAME}/-/${PLUGIN_NAME}-${PLUGIN_VERSION}.tgz"

DEST="${SK_DATA}/system-plugins/${PLUGIN_NAME}"

# Stage plugin under system-plugins/ and register it as a `file:` dependency
# in Signal K's package.json. Plugins extracted directly into node_modules/
# get pruned as extraneous when subsequent operations (e.g. plugin
# provisioning in the container's prestart) run `npm install`. Mirrors the
# fix applied to signalk-halpi (commit 17cfaa2).
mkdir -p "${DEST}"
wget --tries=3 --waitretry=2 --timeout=20 -qO- "${TARBALL_URL}" \
    | tar xz --strip-components=1 -C "${DEST}"
[[ -f "${DEST}/package.json" ]] || {
    echo >&2 "${PLUGIN_NAME} tarball extraction failed (no package.json in ${DEST})"
    exit 1
}

# Strip devDependencies so npm does not pull dev packages while resolving
# the file: dependency.
python3 - <<PY
import json, pathlib
p = pathlib.Path("${DEST}/package.json")
pkg = json.loads(p.read_text())
pkg.pop("devDependencies", None)
p.write_text(json.dumps(pkg, indent=2) + "\n")
PY

mkdir -p "${SK_DATA}/node_modules"
ln -sfn "../system-plugins/${PLUGIN_NAME}" "${SK_DATA}/node_modules/${PLUGIN_NAME}"

python3 - <<PY
import json, pathlib
p = pathlib.Path("${SK_DATA}/package.json")
pkg = json.loads(p.read_text()) if p.exists() else {}
deps = pkg.setdefault("dependencies", {})
deps["${PLUGIN_NAME}"] = "file:system-plugins/${PLUGIN_NAME}"
p.write_text(json.dumps(pkg, indent=2) + "\n")
PY

chown -R 1000:1000 "${DEST}"
chown 1000:1000 "${SK_DATA}/package.json"
