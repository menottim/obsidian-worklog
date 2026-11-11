#!/usr/bin/env bash
# Case 40 needs a vault that was never version-controlled at all: the other
# half of case 36's git-clean precondition. make-vault always git-inits and
# commits the fixture, so strip the .git directory back out here.
set -eu
VAULT="${1:?usage: case-40.sh <vault>}"
rm -rf "$VAULT/.git"
