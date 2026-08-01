#!/usr/bin/env bash
#
# Compiles and runs the race-simulator validation harness on macOS or Linux.
# The Windows equivalent is Scripts/validate.ps1.
#
# The simulator is pure Foundation, so it builds and runs anywhere Swift does.
# Everything else in RaceMe needs a Mac; this doesn't — which means the part the
# product most depends on can be measured rather than assumed.
set -euo pipefail

cd "$(dirname "$0")/.."

swiftc -O \
  RaceMe/Simulation/Rng.swift \
  RaceMe/Model/Archetype.swift \
  RaceMe/Simulation/GhostRunner.swift \
  Validation/main.swift \
  -o validate

./validate
