case ${DOTFILES_PHASE:-} in
setup)
    # The work command keeps its profile here, and a profile without a running session is one that a closed session left
    if [ -z "${AGENT_SHELL:-}" ] && [ -z "${WORK_PROFILE:-}" ]; then
        if [ -x /data/data/com.termux/files/usr/bin/pkg ]; then
            _work_profile=${PREFIX:-/data/data/com.termux/files/usr}/tmp/work-profile
        else
            _work_profile=${TMPDIR:-/tmp}
            _work_profile=${_work_profile%/}/work-profile-$UID
        fi
        if [ -d "$_work_profile" ] && ! kill -0 "$(cat "$_work_profile/pid" 2>/dev/null)" 2>/dev/null; then
            echo "work profile from $(cat "$_work_profile/started" 2>/dev/null) is still on disk: run work --end" >&2
        fi
        unset _work_profile
    fi
    return 0 ;;
esac
