#!/usr/bin/env bash

set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for entry in "$root_dir"/* "$root_dir"/.[!.]* "$root_dir"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue

    name=${entry##*/}
    case "$name" in
        early-init.el|init.el|config.org|lisp|cleanup.sh|.git|.gitignore|.gitattributes|.gitmodules)
            continue
            ;;
    esac

    rm -rf -- "$entry"
done