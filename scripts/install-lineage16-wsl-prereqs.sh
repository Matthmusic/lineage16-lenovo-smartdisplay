#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

disable_problematic_apt_hooks() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$path" ]; then
      echo "[prereqs] disable apt hook $path"
      $SUDO mv "$path" "$path.disabled-for-lineage"
    fi
  done < <(grep -R -l -E 'ubuntu-advantage/apt-esm-hook|snap advise-snap' /etc/apt/apt.conf.d 2>/dev/null || true)
}

BASE_PACKAGES=(
  bc
  bison
  build-essential
  ccache
  curl
  flex
  g++-multilib
  gcc-multilib
  git
  git-lfs
  gnupg
  gperf
  imagemagick
  lib32ncurses5-dev
  lib32readline-dev
  lib32z1-dev
  libdw-dev
  libelf-dev
  libncurses5
  libncurses5-dev
  libssl-dev
  libxml2
  libxml2-utils
  lz4
  lzop
  pngcrush
  protobuf-compiler
  python3-protobuf
  rsync
  schedtool
  squashfs-tools
  unzip
  xz-utils
  xsltproc
  zip
  zlib1g-dev
)

echo "[prereqs] apt update"
disable_problematic_apt_hooks
$SUDO apt-get update

echo "[prereqs] install base packages"
$SUDO apt-get install -y "${BASE_PACKAGES[@]}"

if apt-cache show python-is-python2 >/dev/null 2>&1; then
  echo "[prereqs] install python-is-python2"
  $SUDO apt-get install -y python-is-python2
fi

if ! command -v repo >/dev/null 2>&1; then
  echo "[prereqs] install repo"
  $SUDO curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
  $SUDO chmod 0755 /usr/local/bin/repo
fi

echo "[prereqs] validate tools"
git --version
python --version || true
repo version || true
git lfs install --system || true

echo "[prereqs] done"
