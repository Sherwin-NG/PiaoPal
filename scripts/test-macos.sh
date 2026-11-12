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

xcrun swiftc "${COMMON_FLAGS[@]}" App/CatStats.swift \
  Tests/MacStats/main.swift -o "$TEST_DIR/stats-tests"
"$TEST_DIR/stats-tests"

xcrun swiftc "${COMMON_FLAGS[@]}" Utils/Logging.swift \
  Tests/MacLifecycle/main.swift -o "$TEST_DIR/lifecycle-tests"
"$TEST_DIR/lifecycle-tests"

xcrun swiftc "${COMMON_FLAGS[@]}" -parse-as-library \
  App/Updater.swift Utils/Logging.swift Tests/MacUpdater/UpdaterTests.swift \
  -o "$TEST_DIR/updater-tests"
"$TEST_DIR/updater-tests"


xcrun swiftc "${COMMON_FLAGS[@]}" Engine/Simulation/PetMotion.swift Skins/SkinManager.swift Utils/Logging.swift \
  Skins/CustomPet/CustomPetImages.swift Skins/CustomPet/CustomPetAtlas.swift \
  Skins/CustomPet/CustomPetStore.swift Skins/CustomPet/CustomPetGenerator.swift \
  Tests/MacCustomPet/main.swift -o "$TEST_DIR/custom-pet-tests"
"$TEST_DIR/custom-pet-tests"

echo "PASS: PiaoPal macOS localization, sprites, motion, statistics, lifecycle, updater, and custom pet checks."
