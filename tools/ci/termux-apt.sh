# Usage: . tools/ci/termux-apt.sh; termux_apt_install PACKAGE ... — installs Termux packages in termux/termux-docker, and moves to another official mirror when the package server fails
termux_mirrors="https://packages.termux.dev/apt/termux-main https://grimler.se/termux/termux-main https://mirror.mwt.me/termux/main"

termux_apt_install() {
    local mirror
    apt-get update -qq >/dev/null && apt-get install -y -qq "$@" >/dev/null && return 0
    for mirror in $termux_mirrors; do
        echo "termux-apt: the package server failed, so apt tries $mirror" >&2
        # apt verifies every mirror against the Termux signing key, so a mirror cannot change a package
        rm -f "$PREFIX"/etc/apt/sources.list.d/*.list
        echo "deb $mirror stable main" > "$PREFIX/etc/apt/sources.list"
        apt-get update -qq >/dev/null && apt-get install -y -qq "$@" >/dev/null && return 0
    done
    return 1
}
