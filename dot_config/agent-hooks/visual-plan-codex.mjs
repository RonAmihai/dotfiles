import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';

const waiterScript = join(dirname(new URL(import.meta.url).pathname), 'visual-plan-wait.mjs');
const input = readFileSync(0, 'utf8');
let cwd = process.cwd();
try {
  cwd = JSON.parse(input).cwd ?? cwd;
} catch {}
if (process.argv[2] === 'stop') waitAtTurnEnd();
else startPasteWaiter();

// Inside cmux: after the pack command, start a waiter that types the response into the Codex pane.
function startPasteWaiter() {
  if (!process.env.CMUX_SURFACE_ID) return;
  const packed = input.match(/visual-plan-pack\.mjs\s+(?:\\?["'])?([^"'\\\s]+\.ya?ml)/);
  if (!packed) return;
  const plan = resolve(cwd, packed[1]);
  if (!existsSync(plan.replace(/\.ya?ml$/, '.relay.json'))) return;
  const env = { ...process.env, VISUAL_PLAN_SESSION_PID: String(codexPid() ?? ''), VISUAL_PLAN_MAX_HOURS: '8' };
  spawn(process.execPath, [waiterScript, '--paste', plan], { detached: true, stdio: 'ignore', env }).unref();
}

// Outside cmux: at the end of a turn, wait for the response and give it back as the next prompt.
function waitAtTurnEnd() {
  const relayPath = awaitingRelay(cwd, 4);
  if (!relayPath) return;
  // The waiter watches this hook, so an Esc that ends the hook also ends the waiter.
  const env = { ...process.env, VISUAL_PLAN_SESSION_PID: String(process.pid), VISUAL_PLAN_MAX_HOURS: '8' };
  const run = spawnSync(process.execPath, [waiterScript, relayPath.replace(/\.relay\.json$/, '.yaml')], { encoding: 'utf8', env });
  const relay = JSON.parse(readFileSync(relayPath, 'utf8'));
  writeFileSync(relayPath, JSON.stringify({ ...relay, awaiting: false }));
  if (!run.stdout.includes('My response from the visual plan page')) return;
  process.stderr.write(run.stdout);
  process.exit(2);
}

function awaitingRelay(dir, depth) {
  const found = [];
  const walk = (folder, level) => {
    let entries = [];
    try {
      entries = readdirSync(folder, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const path = join(folder, entry.name);
      if (entry.isDirectory() && level > 0 && !entry.name.startsWith('.') && entry.name !== 'node_modules') walk(path, level - 1);
      else if (entry.name.endsWith('.relay.json') && isAwaiting(path)) found.push(path);
    }
  };
  walk(dir, depth);
  return found.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs)[0] ?? null;
}

function isAwaiting(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8')).awaiting === true;
  } catch {
    return false;
  }
}

// The Codex process is an ancestor of this hook; the waiter watches it, because this hook can end first.
function codexPid() {
  let pid = process.ppid;
  for (let depth = 0; pid > 1 && depth < 6; depth++) {
    const [parent, ...name] = execFileSync('ps', ['-o', 'ppid=,comm=', '-p', String(pid)], { encoding: 'utf8' }).trim().split(/\s+/);
    if (name.join(' ').endsWith('codex')) return pid;
    pid = Number(parent);
  }
  return null;
}
