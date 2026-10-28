#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/tests
awk '/^if CommandLine.arguments.contains\("--self-test"\)/ { exit } { print }' main.swift > .build/tests/Library.swift
swiftc .build/tests/Library.swift Tests/main.swift -o .build/tests/BehaviorTests
.build/tests/BehaviorTests
