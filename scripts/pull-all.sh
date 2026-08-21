#!/usr/bin/env bash
cd "$(dirname "$0")/.."
for d in . repos/*; do [ -d "$d/.git" ] && echo "↻ $d" && git -C "$d" pull --ff-only; done
