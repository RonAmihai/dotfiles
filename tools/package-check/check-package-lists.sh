#!/usr/bin/env bash
# Usage: check-package-lists.sh <Brewfile, winget packages.json, Scoop packages.json or Termux packages.txt>...
set -u

for tool in curl jq gh; do
    command -v "$tool" >/dev/null 2>&1 || { echo "check-package-lists: needs $tool" >&2; exit 2; }
done
failed=0
fail() { echo "::error::$*"; failed=1; }
# Only a 404 means gone: a network, rate-limit or login error must not fail the check
unsure() { echo "::warning::could not check $*"; }
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT

fetch() {
    curl -sS --retry 2 -o "$cache/body" -w '%{http_code}' "$1" 2>/dev/null
}

gh_get() {
    local status
    gh api "$@" </dev/null > "$cache/body" 2> "$cache/err" && return 0
    status=$?
    grep -q 'HTTP 404' "$cache/err" && return 4
    return "$status"
}

check_core() {
    local kind=$1 name=$2 code state replacement
    code=$(fetch "https://formulae.brew.sh/api/$kind/$name.json")
    case $code in
        200) ;;
        404) fail "$kind $name is not in Homebrew"; return ;;
        *) unsure "$kind $name (HTTP $code)"; return ;;
    esac
    state=$(jq -r 'if .disabled then "disabled: \(.disable_reason // "no reason given")"
        elif .deprecated then "deprecated: \(.deprecation_reason // "no reason given")" else empty end' "$cache/body")
    replacement=$(jq -r '[.deprecation_replacement_formula, .deprecation_replacement_cask,
        .disable_replacement_formula, .disable_replacement_cask] | map(select(. != null)) | first // empty' "$cache/body")
    if [ -n "$state" ]; then
        fail "$kind $name is $state${replacement:+, replaced by $replacement}"
    else
        echo "ok: $kind $name"
    fi
}

# Prints the tap's file list, or "missing" or "unknown"
tap_files() {
    local user=${1%%/*} repo=${1#*/} list="$cache/tap-${1//\//_}"
    if [ ! -e "$list" ] && [ ! -e "$list.missing" ] && [ ! -e "$list.unknown" ]; then
        if gh_get "repos/$user/homebrew-$repo/git/trees/HEAD?recursive=1" --jq '.tree[].path'; then
            cp "$cache/body" "$list"
        elif [ $? = 4 ]; then
            : > "$list.missing"
        else
            : > "$list.unknown"
        fi
    fi
    if [ -e "$list" ]; then echo "$list"; elif [ -e "$list.missing" ]; then echo missing; else echo unknown; fi
}

check_tap() {
    case $(tap_files "$1") in
        missing) fail "tap $1 has no repository at github.com/${1%%/*}/homebrew-${1#*/}" ;;
        unknown) unsure "tap $1" ;;
        *) echo "ok: tap $1" ;;
    esac
}

check_tap_item() {
    local kind=$1 tap=${2%/*} item=${2##*/} files
    files=$(tap_files "$tap")
    case $files in
        missing) fail "$kind $2: the $tap tap has no repository" ;;
        unknown) unsure "$kind $2" ;;
        *) if grep -qE "(^|/)$item\.rb$" "$files"; then echo "ok: $kind $2"; else fail "$kind $2 is not in the $tap tap"; fi ;;
    esac
}

check_mas() {
    local code
    code=$(fetch "https://itunes.apple.com/lookup?id=$2")
    if [ "$code" != 200 ]; then
        unsure "mas $1 ($2) (HTTP $code)"
    elif [ "$(jq -r '.resultCount // 0' "$cache/body")" -gt 0 ]; then
        echo "ok: mas $1 ($2)"
    else
        fail "mas $1 ($2) is not in the App Store"
    fi
}

check_winget() {
    local first manifest
    first=$(printf %s "${1%%.*}" | cut -c1 | tr '[:upper:]' '[:lower:]')
    manifest="manifests/$first/$(printf %s "$1" | tr . /)"
    if gh_get "repos/microsoft/winget-pkgs/contents/$manifest" --jq '.[0].name'; then
        echo "ok: winget $1"
    elif [ $? = 4 ]; then
        fail "winget $1 is not in the winget catalog"
    else
        unsure "winget $1"
    fi
}

check_scoop() {
    local repo=$1 name=$2
    if gh_get "repos/$repo/contents/bucket/$name.json" --jq '.name'; then
        echo "ok: scoop $name ($repo)"
    elif [ $? = 4 ]; then
        fail "scoop $name is not in $repo"
    else
        unsure "scoop $name ($repo)"
    fi
}

check_scoopfile() {
    local file=$1 source name url repo
    while IFS=$'\t' read -r source name; do
        url=$(jq -r --arg source "$source" '.buckets[] | select(.Name == $source) | .Source' "$file")
        repo=${url#https://github.com/}
        repo=${repo%.git}
        if [ -z "$repo" ] || [ "$repo" = "$url" ]; then
            fail "scoop $name uses unknown bucket $source"
        else
            check_scoop "$repo" "$name"
        fi
    done < <(jq -r '.apps[] | [.Source, .Name] | @tsv' "$file")
}

check_brewfile() {
    local line kind name
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*(tap|brew|cask)[[:space:]]+\"([^\"]+)\" ]]; then
            kind=${BASH_REMATCH[1]} name=${BASH_REMATCH[2]}
            [ "$kind" = brew ] && kind=formula
            case $kind:$name in
                tap:*) check_tap "$name" ;;
                *:*/*/*) check_tap_item "$kind" "$name" ;;
                *) check_core "$kind" "$name" ;;
            esac
        elif [[ $line =~ ^[[:space:]]*mas[[:space:]]+\"([^\"]+)\",[[:space:]]*id:[[:space:]]*([0-9]+) ]]; then
            check_mas "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        fi
    done < "$1"
}

# Termux has no package API, so this reads the aarch64 package indexes of its main and glibc repositories
check_termuxfile() {
    local name code repo index="$cache/termux-index"
    : > "$index"
    for repo in termux-main/dists/stable/main termux-glibc/dists/glibc/stable; do
        code=$(fetch "https://packages-cf.termux.dev/apt/$repo/binary-aarch64/Packages")
        if [ "$code" != 200 ]; then
            unsure "the Termux index $repo (HTTP $code)"
            return
        fi
        cat "$cache/body" >> "$index"
    done
    for name in $(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$1"); do
        if grep -qx "Package: $name" "$index"; then
            echo "ok: termux $name"
        else
            fail "termux $name is not in the Termux main or glibc repository"
        fi
    done
}

for list in "$@"; do
    echo "== $list"
    case $list in
        *termux/packages.txt) check_termuxfile "$list" ;;
        *scoop/packages.json) check_scoopfile "$list" ;;
        *.json) for id in $(jq -r '.Sources[].Packages[].PackageIdentifier' "$list"); do check_winget "$id"; done ;;
        *) check_brewfile "$list" ;;
    esac
done
exit "$failed"
