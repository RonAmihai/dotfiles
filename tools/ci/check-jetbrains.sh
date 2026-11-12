#!/usr/bin/env bash
# Usage: bash tools/ci/check-jetbrains.sh CHEZMOI CONFIG — builds fake JetBrains IDE folders in an empty HOME, runs the JetBrains scripts and agent templates on them, and fails on a wrong result
set -euo pipefail

cm=$1
config=$2
repo=$(cd "$(dirname "$0")/../.." && pwd)
fixtures="$repo/tools/ci/fixtures"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"

fail() { echo "check-jetbrains: $*" >&2; exit 1; }

case "$(uname -s)" in
    Darwin) cache="$home/Library/Caches/JetBrains" conf="$home/Library/Application Support/JetBrains" ;;
    *) cache="$home/.cache/JetBrains" conf="$home/.config/JetBrains" ;;
esac
resources=ai-agent-extensions/bundledSkillsResources

skill() {
    mkdir -p "$1"
    printf -- '---\nname: %s\ndescription: A fake skill\n---\n' "${1##*/}" > "$1/SKILL.md"
}
skill "$cache/Rider2026.2/$resources/rider.provider/old-only"
skill "$cache/Rider2026.3/$resources/rider.provider/debugging-code"
skill "$cache/Rider2026.3/$resources/rider.provider/bundledSkills/rider-database-connection-management"
skill "$cache/Rider2026.3/$resources/cmake.provider/bundledSkills/cmake-project-configuration"
skill "$cache/GoLand2026.3/$resources/goland.provider/go-debug"
mkdir -p "$conf/Rider2026.3" "$conf/GoLand2026.3"
printf 'keep.me=1\nidea.mcp.server.force.port=1' > "$conf/Rider2026.3/idea.properties"
mkdir -p "$home/.claude/skills/my-skill" "$home/.agents/skills/goland-go-debug"
ln -s "$tmp" "$home/.claude/skills/my-link"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'EOF'
#!/bin/sh
echo "$*" >> "$CLAUDE_LOG"
[ "$2" = get ] && exit 1
exit 0
EOF
chmod +x "$tmp/bin/claude"

in_home() {
    env -u CI -u XDG_CACHE_HOME -u XDG_CONFIG_HOME HOME="$home" PATH="$tmp/bin:$PATH" CLAUDE_LOG="$tmp/claude.log" "$@"
}
render() { in_home "$cm" --config "$config" --source "$repo" execute-template "${@:2}" < "$repo/$1"; }
modify() {
    in_home "$cm" --config "$config" --source "$repo" execute-template --with-stdin "$(cat "$repo/$1")" < "$2"
}
run_script() {
    render ".chezmoiscripts/run_onchange_after_$1.sh.tmpl" > "$tmp/$1.sh"
    in_home sh "$tmp/$1.sh"
}
links_to() {
    [ -L "$1" ] || return 1
    case "$(readlink "$1")" in *"$2") return 0 ;; *) return 1 ;; esac
}
real_folder() { [ -d "$1" ] && [ ! -L "$1" ]; }

run_script jetbrains-skills 2> "$tmp/skills.err"
for dir in "$home/.claude/skills" "$home/.agents/skills"; do
    links_to "$dir/rider-debugging-code" "Rider2026.3/$resources/rider.provider/debugging-code" ||
        fail "$dir/rider-debugging-code does not link to the newest Rider"
    links_to "$dir/rider-database-connection-management" "bundledSkills/rider-database-connection-management" ||
        fail "$dir has no rider-database-connection-management link with one prefix"
    links_to "$dir/rider-cmake-project-configuration" "cmake.provider/bundledSkills/cmake-project-configuration" ||
        fail "$dir has no link for a skill of a second provider"
    if [ -e "$dir/rider-old-only" ]; then fail "$dir links a skill of an old Rider version"; fi
done
links_to "$home/.claude/skills/goland-go-debug" "GoLand2026.3/$resources/goland.provider/go-debug" || fail "no GoLand skill link"
real_folder "$home/.agents/skills/goland-go-debug" || fail "the skills script replaced a real folder"
grep -q 'goland-go-debug is not a link' "$tmp/skills.err" || fail "the skills script did not warn about the real folder"
real_folder "$home/.claude/skills/my-skill" || fail "the skills script changed a real skill folder"
links_to "$home/.claude/skills/my-link" "$tmp" || fail "the skills script changed a link that is not a JetBrains link"

run_script jetbrains-ports > /dev/null
rider_properties="$conf/Rider2026.3/idea.properties"
grep -qx 'keep.me=1' "$rider_properties" || fail "the ports script lost another property"
if [ "$(grep -c '^idea\.mcp\.server\.force\.port=' "$rider_properties")" != 1 ]; then
    fail "the Rider idea.properties has more than one port line"
fi
grep -qx 'idea.mcp.server.force.port=64342' "$rider_properties" || fail "Rider did not get port 64342"
grep -qx 'idea.mcp.server.force.port=64343' "$conf/GoLand2026.3/idea.properties" || fail "GoLand did not get port 64343"
cp "$rider_properties" "$tmp/rider.properties"
if [ -n "$(run_script jetbrains-ports)" ] || ! cmp -s "$tmp/rider.properties" "$rider_properties"; then
    fail "a second run of the ports script changed a file"
fi

run_script claude-jetbrains-mcp
for server in 'jetbrains-rider http://127.0.0.1:64342/stream' 'jetbrains-goland http://127.0.0.1:64343/stream'; do
    grep -qx "mcp add --scope user --transport http $server" "$tmp/claude.log" || fail "Claude Code did not get $server"
done

modify dot_codex/modify_private_config.toml "$fixtures/codex-config.toml" > "$tmp/codex.toml"
python3 - "$tmp/codex.toml" <<'PY' || fail "Codex did not get the JetBrains servers"
import sys, tomllib
servers = tomllib.load(open(sys.argv[1], "rb"))["mcp_servers"]
assert servers["jetbrains-rider"]["url"] == "http://127.0.0.1:64342/stream"
assert servers["jetbrains-goland"]["url"] == "http://127.0.0.1:64343/stream"
PY
modify dot_gemini/config/modify_mcp_config.json /dev/null > "$tmp/agy.json"
jq -e '.mcpServers["jetbrains-rider"].serverUrl == "http://127.0.0.1:64342/stream"
    and .mcpServers["jetbrains-goland"].serverUrl == "http://127.0.0.1:64343/stream"' "$tmp/agy.json" > /dev/null ||
    fail "agy did not get the JetBrains servers"
modify dot_config/opencode/modify_opencode.json "$fixtures/opencode.json" > "$tmp/opencode.json"
jq -e '.mcp.servers["jetbrains-rider"].url == "http://127.0.0.1:64342/stream"
    and .mcp.servers["jetbrains-goland"].url == "http://127.0.0.1:64343/stream"' "$tmp/opencode.json" > /dev/null ||
    fail "opencode did not get the JetBrains servers"

for rules in "dot_claude/CLAUDE.md.tmpl:run \`/mcp\`" "dot_codex/AGENTS.md.tmpl:run \`/reload\`" \
    "dot_gemini/GEMINI.md.tmpl:run \`/reload\`" "dot_config/opencode/AGENTS.md.tmpl:restart opencode"; do
    render "${rules%%:*}" > "$tmp/rules.md"
    grep -q '^## JetBrains IDE tools$' "$tmp/rules.md" || fail "${rules%%:*} has no JetBrains rule"
    grep -qF "4. Ask me to ${rules#*:}." "$tmp/rules.md" || fail "${rules%%:*} has a wrong reconnect step"
done
render dot_claude/CLAUDE.md.tmpl --override-data '{"chezmoi":{"os":"android"}}' > "$tmp/android.md"
if grep -q '^## JetBrains IDE tools$' "$tmp/android.md"; then fail "Android got the JetBrains rule"; fi

rm -rf "$cache/GoLand2026.3"
run_script jetbrains-skills 2> /dev/null
if [ -e "$home/.claude/skills/goland-go-debug" ] || [ -L "$home/.claude/skills/goland-go-debug" ]; then
    fail "the skills script kept the link of a removed IDE"
fi
real_folder "$home/.agents/skills/goland-go-debug" || fail "the skills script removed a real folder"
links_to "$home/.claude/skills/rider-debugging-code" "debugging-code" || fail "the skills script removed a Rider link"

echo "check-jetbrains: skills, ports, MCP servers and rules are right for fake Rider and GoLand"
