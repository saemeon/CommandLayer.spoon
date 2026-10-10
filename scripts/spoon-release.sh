#!/bin/sh
# Writes what SpoonInstall downloads, into the folder given:
#   Spoons/CommandLayer.spoon.zip   the Spoon, as it runs: no tests, no git
#   docs/docs.json                  its hs.doc entry, which SpoonInstall lists
# Publishing that folder as a branch (say "spoons") is then a repository
# SpoonInstall can install from:
#   spoon.SpoonInstall.repos.CommandLayer = { url = "https://github.com/saemeon/CommandLayer.spoon",
#                                             branch = "spoons" }
set -eu
out=${1:?"usage: scripts/spoon-release.sh <folder>"}
here=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/CommandLayer.spoon" "$out/Spoons" "$out/docs"
for part in init.lua commandlayer.lua core config extensions matchers rankers presenters docs docs.json \
            README.md LICENSE; do
  cp -R "$here/$part" "$stage/CommandLayer.spoon/"
done
rm -f "$out/Spoons/CommandLayer.spoon.zip"
(cd "$stage" && zip -qr -X "$out/Spoons/CommandLayer.spoon.zip" CommandLayer.spoon -x '*.DS_Store')
cp "$here/docs.json" "$out/docs/docs.json"
echo "wrote $out/Spoons/CommandLayer.spoon.zip and $out/docs/docs.json"
