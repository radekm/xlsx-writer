#!/usr/bin/env bash
set -e

script_dir=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
build_dir="$script_dir/build"

mkdir -p "$build_dir"
cd "$build_dir"

c3c compile-test ../xlsx.c3l/*.c3

c3c compile --macos-min-version 13.0 --libdir .. --lib xlsx ../example/main.c3 -o example
