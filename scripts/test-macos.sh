#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/piaopal-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_DIR"' EXIT
COMMON_FLAGS=(-swift-version 5 -module-cache-path "$TEST_DIR/module-cache")
LOCALIZATION=(App/Localization/Language.swift App/Achievements/Achievement.swift)

xcrun swiftc "${COMMON_FLAGS[@]}" "${LOCALIZATION[@]}" \
  Tests/MacLocalization/main.swift -o "$TEST_DIR/localization-tests"
"$TEST_DIR/localization-tests"

xcrun swiftc "${COMMON_FLAGS[@]}" Engine/Simulation/PetMotion.swift Skins/SkinManager.swift Utils/Logging.swift \
  Tests/MacSprites/main.swift -o "$TEST_DIR/sprite-tests"
"$TEST_DIR/sprite-tests" "$REPO_DIR"

xcrun swiftc "${COMMON_FLAGS[@]}" Engine/Simulation/PetMotion.swift \
  Tests/MacMotion/main.swift -o "$TEST_DIR/motion-tests"
"$TEST_DIR/motion-tests"

xcrun swiftc "${COMMON_FLAGS[@]}" -parse-as-library \
  App/Updater.swift Utils/Logging.swift Tests/MacUpdater/UpdaterTests.swift \
  -o "$TEST_DIR/updater-tests"
"$TEST_DIR/updater-tests"


echo "PASS: PiaoPal macOS localization, sprites, motion, and updater checks."
