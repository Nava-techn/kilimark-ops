#!/usr/bin/env bash
# Created in Session 5, lab S5.1: idempotent deploy of the storefront (site/), shellcheck clean.
# It automates the manual "atomic swap" of S1.5 / S4.6, with releases and an automatic rollback.
#
# Usage (from the repo root):
#   scripts/session-05/s5.1-deploy-storefront.sh [options] <ssh-host>
#     -n name    site name for the health check (https://name/health.json, asked on the server itself)
#     -g group   team group owning the files (shared folder: dirs 2775, files 664). Default: root, 755/644
#     -r root    web root served by Nginx (default /srv/navmarket)
#     -k keep    releases to keep (default 3)
#     -x         test only: simulate a broken release (health.json removed) to see the rollback
#   scripts/session-05/s5.1-deploy-storefront.sh -n kilimark.com vps01
#   scripts/session-05/s5.1-deploy-storefront.sh -n www.navmarket.lan -g <team-group> srv01
#
# On the server:
#   /srv/navmarket-releases/1.0.0-3f2a9c1/   one folder per release (version + Git commit)
#   /srv/navmarket -> navmarket-releases/...  a symlink: Nginx serves the live release
#
# Idempotent: run it twice with the same commit and the second run changes nothing.
# Safe: the symlink is switched atomically; if the health check fails, the previous
# release comes back automatically. Exit codes: 0 deployed or nothing to do, 1 failed.
set -euo pipefail

root=/srv/navmarket keep=3 name=localhost group="" broken=""
usage() { echo "Usage: $0 [-n name] [-g group] [-r root] [-k keep] [-x] <ssh-host>" >&2; exit 1; }
while getopts "n:g:r:k:xh" opt; do
  case $opt in n) name=$OPTARG ;; g) group=$OPTARG ;; r) root=$OPTARG ;; k) keep=$OPTARG ;; x) broken=yes ;; *) usage ;; esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
host=$1

[ -f site/health.json ] || { echo "Run me from the repo root (site/ not found)" >&2; exit 1; }
version=$(grep -oP '"version":\s*"\K[^"]+' site/health.json)
commit=$(git log -1 --format=%h -- site)       # last commit that changed site/, not the repo HEAD
git diff --quiet HEAD -- site || commit="$commit-dirty"   # uncommitted changes are visible in the name
release="$version-$commit${broken:+-broken}"
echo "Deploying $release to $host:$root"

# The part that runs on the server, as root. Arguments: release root keep name version group broken
remote() {
  set -euo pipefail
  local release=$1 root=$2 keep=$3 name=$4 version=$5 group=$6 broken=${7:-}
  local releases=$root-releases new=$root-releases/$release prev=""

  if [ "$(readlink -f "$root")" = "$new" ]; then
    echo "Already live: $release. Nothing to do."; rm -f "/tmp/$release.tgz"; return 0
  fi
  install -d -m 755 "$releases"
  if [ ! -d "$new" ]; then                         # unpack next to the live site, rights included
    rm -rf "$new.tmp"; mkdir -p "$new.tmp"
    tar -xzf "/tmp/$release.tgz" -C "$new.tmp"
    [ -n "$broken" ] && rm -f "$new.tmp/health.json"   # -x: a broken build, on purpose
    if [ -n "$group" ]; then                       # shared with a team (S1.2): setgid + group write
      chown -R "root:$group" "$new.tmp"
      find "$new.tmp" -type d -exec chmod 2775 {} +
      find "$new.tmp" -type f -exec chmod 664 {} +
    else
      chown -R root:root "$new.tmp"
      find "$new.tmp" -type d -exec chmod 755 {} +
      find "$new.tmp" -type f -exec chmod 644 {} +
    fi
    mv "$new.tmp" "$new"
    touch "$new"                                   # deploy date, not the files' date (tar keeps those)
  fi
  rm -f "/tmp/$release.tgz"

  if [ -L "$root" ]; then
    prev=$(readlink -f "$root")
  elif [ -d "$root" ]; then                        # first run: the old folder becomes a release
    prev=$releases/legacy-$(date +%Y%m%d-%H%M%S)
    mv "$root" "$prev"
  fi
  ln -sfn "$new" "$root.next" && mv -T "$root.next" "$root"   # atomic switch
  echo "Live: $root -> $new"

  # Health check on the server itself: --resolve sends the name to 127.0.0.1.
  # -k: this checks the CONTENT; the certificate is checked by the S4.3 / S4.6 proofs.
  sleep 1
  if curl -fsSk -m 5 --resolve "$name:443:127.0.0.1" "https://$name/health.json" | grep -q "\"version\": *\"$version\""; then
    echo "Health check OK: https://$name/health.json reports version $version"
  else
    echo "Health check FAILED on https://$name/health.json"
    if [ -n "$prev" ]; then
      ln -sfn "$prev" "$root.next" && mv -T "$root.next" "$root"
      echo "Rolled back to $prev"
    fi
    return 1
  fi

  # broken releases are never worth keeping (S5.1 lesson), then keep the newest, never the live one
  find "$releases" -mindepth 1 -maxdepth 1 -type d -name "*-broken" -exec rm -rf {} +
  find "$releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2- \
    | grep -vxF "$new" | tail -n +"$keep" | xargs -r rm -rf
  echo "Releases kept:"; ls -1t "$releases"
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tar -czf "$tmp/$release.tgz" -C site .
{ declare -f remote; echo 'remote "$@"'; } > "$tmp/deploy-remote.sh"
scp -q "$tmp/$release.tgz" "$tmp/deploy-remote.sh" "$host:/tmp/"
# -t: sudo can ask for a password (srv01); on vps01 sudo needs none
ssh -t "$host" "sudo bash /tmp/deploy-remote.sh '$release' '$root' '$keep' '$name' '$version' '$group' '$broken'; rc=\$?; rm -f /tmp/deploy-remote.sh; exit \$rc"
