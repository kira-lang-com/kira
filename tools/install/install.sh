#!/bin/sh
# Installs Kira: knvm for this machine, then `knvm setup`, which installs klf,
# the LLVM it links with, every language, and the launchers onto PATH.
#
#   curl -fsSL https://github.com/kira-lang-com/kira/releases/latest/download/install.sh | sh
#
# Run again to bring everything up to date.
set -eu

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) host=aarch64-macos ;;
  Darwin-x86_64) host=x86_64-macos ;;
  Linux-aarch64 | Linux-arm64) host=aarch64-linux-gnu ;;
  Linux-x86_64) host=x86_64-linux-gnu ;;
  *) echo "Kira does not publish for $(uname -sm) yet" >&2; exit 1 ;;
esac

releases=https://github.com/kira-lang-com/kira/releases/latest/download
home=${KLFD_HOME:-$HOME/.klf}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

version=$(curl -fsSL "$releases/version")
archive="knvm-$version-$host.tar.gz"
echo "Fetching knvm $version for $host"
curl -fsSL -o "$scratch/$archive" "$releases/$archive"
curl -fsSL -o "$scratch/$archive.sha256" "$releases/$archive.sha256"
expected=$(cut -d' ' -f1 < "$scratch/$archive.sha256")
if command -v sha256sum >/dev/null; then actual=$(sha256sum "$scratch/$archive" | cut -d' ' -f1)
else actual=$(shasum -a 256 "$scratch/$archive" | cut -d' ' -f1); fi
[ "$expected" = "$actual" ] || { echo "$archive does not match its published checksum" >&2; exit 1; }

mkdir -p "$scratch/knvm"
tar -xzf "$scratch/$archive" -C "$scratch/knvm"
"$scratch/knvm/bin/knvm" setup
echo "Open a new terminal, or run: . $home/env"
