#!/bin/zsh
set -e
cd "$(dirname "$0")/.."

usage() {
    echo "Usage: ./scripts/release.sh <TAG>    e.g. v1.2.0 or 1.2.0"
    echo
    git fetch -q --tags origin 2>/dev/null || true
    local tags=$(git tag -l 'v*' --sort=-v:refname)
    if [[ -z "$tags" ]]; then
        echo "No versions released yet"
    else
        echo "Versions:"
        echo "$tags" | sed 's/^/  /'
    fi
}

if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

TAG="v${1#v}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid tag: $1 (expected X.Y.Z)"; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Not on main"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree is not clean"; exit 1; }

git fetch -q --tags origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main is not in sync with origin/main"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "Tag $TAG already exists"; exit 1; }

git tag -a "$TAG" -m "Recordy ${TAG#v}"
git push origin "$TAG"
echo "Pushed $TAG: https://github.com/funivan/recordy/actions"
