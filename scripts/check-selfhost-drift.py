#!/usr/bin/env python3
"""The Coolify stack and the Kern Cloud stack are second and third copies of the self-host stack,
and a copy is only useful while it stays the same stack. Two things make them the same: the
environment `core` is handed, and the paths Caddy routes. Both are easy to change in one file and
forget in the others, and none of it shows up as a failure until somebody deploys.

    python3 scripts/check-selfhost-drift.py
    python3 scripts/check-selfhost-drift.py --emit-caddyfile /tmp/Caddyfile
    python3 scripts/check-selfhost-drift.py --emit-cloud-caddyfile /tmp/Caddyfile.cloud

The emit flags write out the config a stack builds at run time, so `caddy validate` can read it.
Nothing else ever would: it lives in a heredoc inside a container command.

What a copy is allowed to differ in is the *value* of a variable, never the set of keys — Kern
Cloud points S3_PUBLIC_ENDPOINT at its own storage hostname, for instance, because Cloudflare
rejects a proxied body over 100 MB and core signs single-PUT URLs far larger than that.

Routes are compared as ordered directive lists, but a copy may deliberately drop a route when the
service behind it does not exist there — Kern Cloud keeps no MinIO on the box (files go to Hetzner
Object Storage, see cloud/docker-compose.yml), so it has no `/s3` handler to keep alive. Such
omissions must be declared here, or the check fails; nothing else about the routing order may move.
"""

import re
import subprocess
import sys

import yaml

HOST = "selfhost/docker-compose.yml"
COOLIFY = "selfhost/coolify/docker-compose.yml"
CLOUD = "cloud/docker-compose.yml"

# Directives a copy is allowed to be missing, per path. Kern Cloud proxies no MinIO.
ALLOWED_MISSING = {
    CLOUD: {"handle_path /s3/* {", "reverse_proxy minio:9000"},
    COOLIFY: set(),
}


def config(path):
    """`docker compose config` rather than a plain YAML load, so anchors and defaults are resolved
    the way Docker resolves them."""
    out = subprocess.run(["docker", "compose", "-f", path, "config"], capture_output=True, text=True)
    if out.returncode:
        sys.exit(f"::error::{path} does not parse:\n{out.stderr}")
    return yaml.safe_load(out.stdout)


failed = False


def compare(what, other_path, host_set, other_set):
    global failed
    if host_set == other_set:
        print(f"✔ {what} ({other_path})")
        return
    failed = True
    for key in sorted(host_set - other_set):
        print(f"::error::{what}: {key} is in {HOST} and missing from {other_path}")
    for key in sorted(other_set - host_set):
        print(f"::error::{what}: {key} is in {other_path} and missing from {HOST}")


def kern_images(doc):
    return {
        image.split("/")[-1].split(":")[0]
        for service in doc["services"].values()
        for image in [service.get("image", "")]
        if image.startswith("ghcr.io/kernaio/")
    }


def routes(caddyfile):
    """The directives that decide where a request goes. Formatting and comments are free to differ;
    the order matters, because Caddy's first matching handler wins."""
    directive = re.compile(r"^\s*(reverse_proxy|handle|handle_path|@\w+ path|rewrite)\b")
    return [re.sub(r"\s+", " ", line).strip() for line in caddyfile.splitlines() if directive.match(line)]


def inline_caddyfile(doc):
    """Neither copy has a Caddyfile beside it: a pasted Compose file has no files to mount, so the
    config is a heredoc inside the container's command."""
    return doc["services"]["caddy"]["command"][0].split("<<'CADDYFILE'", 1)[1].split("\nCADDYFILE", 1)[0]


def emit(flag, text):
    if flag in sys.argv:
        destination = sys.argv[sys.argv.index(flag) + 1]
        open(destination, "w").write(text)
        print(f"✔ wrote {destination}")


host = config(HOST)
host_routes = routes(open("selfhost/Caddyfile").read())

for path, emit_flag in ((COOLIFY, "--emit-caddyfile"), (CLOUD, "--emit-cloud-caddyfile")):
    doc = config(path)
    compare("core environment", path, set(host["services"]["core"]["environment"]), set(doc["services"]["core"]["environment"]))
    compare("Kern images", path, kern_images(host), kern_images(doc))

    inline = inline_caddyfile(doc)
    emit(emit_flag, inline)

    if routes(inline) == host_routes:
        print(f"✔ Caddy routes ({path})")
    else:
        missing = set(host_routes) - set(routes(inline))
        allowed = ALLOWED_MISSING[path]
        if routes(inline) == [d for d in host_routes if d not in allowed] and missing <= allowed:
            print(f"✔ Caddy routes ({path}, minus declared omissions: {sorted(missing)})")
        else:
            failed = True
            print(f"::error::the Caddy config inside {path} no longer routes the same paths as selfhost/Caddyfile")
            print("  host: ", host_routes)
            print(f"  {path}: ", routes(inline))

sys.exit(1 if failed else 0)
