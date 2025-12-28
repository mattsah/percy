version = "0.0.0"

author = "Matthew J. Sahagian"
description = "A package manager for Nim"
license = "MIT"
binDir = "bin"
bin = @[
  "percy"
]

requires "nim >= 2.2.6"
requires "semver >= 1.2.0"
requires "checksums >= 0.2.1"
requires "https://codeberg.org/mininim/core#head"
requires "https://codeberg.org/mininim/cli#head"
