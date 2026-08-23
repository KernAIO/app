#!/usr/bin/env python3
"""The Coolify stack is a second copy of the self-host stack, and a copy is only useful while it
stays the same stack. Two things make it the same: the environment `core` is handed, and the paths
Caddy routes. Both are easy to change in one file and forget in the other, and neither shows up as
a failure until somebody deploys.

    python3 scripts/check-selfhost-drift.py
    python3 scripts/check-selfhost-drift.py --emit-caddyfile /tmp/Caddyfile

`--emit-caddyfile` writes out the config the Coolify stack builds at run time, so `caddy validate`
can read it. Nothing else ever would: it lives in a heredoc inside a container command.
"""

import re
import subprocess
import sys

import yaml

HOST = "selfhost/docker-compose.yml"
COOLIFY = "selfhost/coolify/docker-compose.yml"


def config(path):
    """`docker compose config` rather than a plain YAML load, so anchors and defaults are resolved
    the way Docker resolves them."""
    out = subprocess.run(["docker", "compose", "-f", path, "config"], capture_output=True, text=True)
    if out.returncode:
        sys.exit(f"::error::{path} does not parse:\n{out.stderr}")
    return yaml.safe_load(out.stdout)


failed = False


def compare(what, host_set, coolify_set):
    global failed
    if host_set == coolify_set:
        print(f"✔ {what}")
        return
    failed = True
    for key in sorted(host_set - coolify_set):
        print(f"::error::{what}: {key} is in {HOST} and missing from {COOLIFY}")
    for key in sorted(coolify_set - host_set):
        print(f"::error::{what}: {key} is in {COOLIFY} and missing from {HOST}")


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


host, coolify = config(HOST), config(COOLIFY)

compare("core environment", set(host["services"]["core"]["environment"]), set(coolify["services"]["core"]["environment"]))
compare("Kern images", kern_images(host), kern_images(coolify))

# The Coolify file has no Caddyfile beside it: a pasted Compose file has no files to mount, so the
# config is a heredoc inside the container's command.
inline = coolify["services"]["caddy"]["command"][0].split("<<'CADDYFILE'", 1)[1].split("\nCADDYFILE", 1)[0]

if "--emit-caddyfile" in sys.argv:
    destination = sys.argv[sys.argv.index("--emit-caddyfile") + 1]
    open(destination, "w").write(inline)
    print(f"✔ wrote the Coolify Caddy config to {destination}")

if routes(open("selfhost/Caddyfile").read()) == routes(inline):
    print("✔ Caddy routes")
else:
    failed = True
    print(f"::error::the Caddy config inside {COOLIFY} no longer routes the same paths as selfhost/Caddyfile")
    print("  host:    ", routes(open("selfhost/Caddyfile").read()))
    print("  coolify: ", routes(inline))

sys.exit(1 if failed else 0)
