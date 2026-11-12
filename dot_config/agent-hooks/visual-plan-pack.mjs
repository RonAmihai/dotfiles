import { readFileSync, writeFileSync, existsSync, readdirSync, unlinkSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { randomBytes, randomInt } from 'node:crypto';
import { createRequire } from 'node:module';
import { createServer } from 'node:net';
import { dirname, join, resolve } from 'node:path';
import { devNull, homedir } from 'node:os';
import vm from 'node:vm';

const baseWords = 600;
const wordsPerDecision = 200;
// Below the temporary ports of macOS, Linux and Windows, so an outgoing connection never takes it.
const waiterPorts = { first: 20000, last: 32767 };
// The same fields that the STE lint of pack.mjs skips.
const steSkippedFields = /\.svg$|\.calls$|view\.text$|\.example$|exampleLabel|retired|\.label$/;
const steScript = `
import json, sys
sys.path.insert(0, sys.argv[1])
from ste_lint import lint
hits = []
for path, text in json.load(sys.stdin):
    found = {k: n for k, n in lint(text, "descriptive")["violations"].items() if n}
    if found:
        hits.append([path, ", ".join(f"{k} {n}" for k, n in found.items())])
print(json.dumps(hits))
`;
// A stub page that accepts every DOM call, so that only errors in the plan data throw.
const anything = new Proxy(function () {}, {
  get: (_, key) => (key === Symbol.toPrimitive ? () => '' : key === 'length' ? 0 : anything),
  set: () => true,
  apply: () => anything,
  construct: () => anything,
});

const claudeDir = process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), '.claude');
const pack = join(homedir(), '.agents/skills/visual-plan/runtime/pack.mjs');
// With no argument, Claude Code runs this as a hook after an edit of a plan file; with a YAML path, any agent runs it.
const hookMode = process.argv.length < 3;
const source = hookMode ? hookPlanFile() : resolve(process.argv[2]);
if (!source || !existsSync(source)) {
  if (hookMode) process.exit(0);
  console.log(`No plan file at ${source}.`);
  process.exit(1);
}

const planText = hookMode ? readFileSync(source, 'utf8').match(/^```ya?ml visual-plan\n([\s\S]*?)^```$/m)?.[1] : readFileSync(source, 'utf8');
if (planText == null) process.exit(0);

const base = source.replace(/\.(md|ya?ml)$/, '');
const packInput = hookMode ? `${base}.yaml` : `${base}.page.yaml`;
const htmlPath = `${base}.html`;
const delivery = deliveryMode();
const relay = delivery ? await relayFor(base) : null;
const relayData = relay ? `\nrelay:\n  url: "http://127.0.0.1:${relay.port}/respond?token=${relay.token}"\n` : '';
writeFileSync(packInput, `${planText}${relayData}`);

const plan = parse(planText);
const budget = plan ? wordBudget(plan) : { total: 0, limit: 0, report: '' };
const overBudget = budget.total > budget.limit;
const crashes = plan ? renderCrashes(plan) : [];
const failed = overBudget || crashes.length > 0;
const firstRender = !existsSync(htmlPath);
const run = spawnSync(process.execPath, [pack, packInput, '--out', failed ? devNull : htmlPath], { encoding: 'utf8' });
const lint = `${run.stdout}${run.stderr}`.trim();
if (!hookMode) unlinkSync(packInput);

if (run.status !== 0 || failed) {
  const crashReport = crashes.length > 0 && `The page crashes when it opens. Fix the plan data:\n${crashes.join('\n')}`;
  const reasons = [overBudget && budget.report, crashReport, run.status !== 0 && lint].filter(Boolean).join('\n\n');
  const report = `The visual plan in ${source} did not pack.\n${reasons}`;
  if (hookMode) console.log(JSON.stringify({ decision: 'block', reason: report }));
  else console.log(report);
  process.exit(hookMode ? 0 : 1);
}

if (delivery === 'stop') writeFileSync(`${base}.relay.json`, JSON.stringify({ port: relay.port, token: relay.token, opened: relay.opened, awaiting: true }));
const opener = { darwin: 'open', linux: 'xdg-open' }[process.platform];
// With a waiter, the waiter opens the page when it listens, so Send works from the start.
if (firstRender && opener && !relay) spawnSync(opener, [htmlPath]);
const report = [
  `The visual plan page is at ${htmlPath}, with ${budget.total} of ${budget.limit} words.`,
  waiterInstruction(),
  relay
    ? 'When you hand the page over, tell me to answer on the page and press "Send to the session". Do not tell me to copy the response.'
    : 'When you hand the page over, tell me to answer on the page, press "Copy response", and paste it here.',
  lint,
  steWarnings(plan),
].filter(Boolean).join('\n');
if (hookMode) console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: report } }));
else console.log(report);

function hookPlanFile() {
  const input = JSON.parse(readFileSync(0, 'utf8'));
  const file = resolve(input.tool_input?.file_path ?? '');
  return dirname(file) === join(claudeDir, 'plans') && file.endsWith('.md') ? file : null;
}

// Claude Code and agy wake the agent when a background command ends; Codex does not, so a Codex hook delivers instead.
function deliveryMode() {
  const codex = process.env.CODEX_THREAD_ID || process.env.CODEX_SESSION_ID;
  if (!codex) return 'wake';
  return process.env.CMUX_SURFACE_ID ? 'paste' : 'stop';
}

function waiterInstruction() {
  if (!relay) return null;
  if (relay.waiting) return 'A response waiter runs for this page.';
  if (delivery === 'paste') return 'A Codex hook starts the response waiter after this command, because the sandbox blocks it here. Do not start it yourself. End your turn: my response arrives in this pane.';
  if (delivery === 'stop') return 'When you end your turn, a Codex hook waits for my response from the page and gives it to you as the next prompt. Do not start a waiter yourself. End your turn now.';
  const command = `node ~/.config/agent-hooks/visual-plan-wait.mjs "${source}"`;
  return `No response waiter runs. Start it as a background task now: ${command}. When it ends, its output is my response from the page. Answer it as a message from me.`;
}

function parse(text) {
  try {
    const yaml = createRequire(import.meta.url)(join(dirname(pack), 'vendor/js-yaml.js'));
    const data = yaml.load(text);
    return data && typeof data === 'object' ? data : null;
  } catch {
    return null;
  }
}

function words(value) {
  if (typeof value === 'string') return value.replace(/<[^>]+>/g, ' ').split(/\s+/).filter(Boolean).length;
  if (Array.isArray(value)) return value.reduce((sum, item) => sum + words(item), 0);
  if (value && typeof value === 'object') return Object.values(value).reduce((sum, item) => sum + words(item), 0);
  return 0;
}

function wordBudget(plan) {
  const { blocks, ...header } = plan;
  const list = Array.isArray(blocks) ? blocks : [];
  const openDecisions = list.filter((b) => b?.kind === 'decisions' && Array.isArray(b.open)).reduce((sum, b) => sum + b.open.length, 0);
  const limit = baseWords + wordsPerDecision * openDecisions;
  const counts = [['header', words(header)], ...list.map((b) => [b?.kind ?? '?', words(b)])];
  const total = counts.reduce((sum, [, count]) => sum + count, 0);
  const perBlock = counts.map(([kind, count]) => `${kind} ${count}`).join(', ');
  return {
    total,
    limit,
    report: `The page has ${total} words, and the limit is ${limit}: ${baseWords}, plus ${wordsPerDecision} for each of the ${openDecisions} open decisions. Cut at least ${total - limit} words in one edit. Words per block: ${perBlock}. Keep the open decisions whole, and cut the map and the other blocks first.`,
  };
}

async function relayFor(base) {
  const path = `${base}.relay.json`;
  const saved = existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : null;
  const state = saved ? await waiterState(saved) : 'none';
  if (state === 'waiting' || state === 'free') return { ...saved, waiting: state === 'waiting' };
  const fresh = { port: await freePort(), token: randomBytes(16).toString('hex') };
  writeFileSync(path, JSON.stringify(fresh));
  return { ...fresh, waiting: false };
}

async function waiterState({ port, token }) {
  try {
    const response = await fetch(`http://127.0.0.1:${port}/ping?token=${token}`, { signal: AbortSignal.timeout(500) });
    return response.ok && (await response.text()) === 'waiting' ? 'waiting' : 'taken';
  } catch (error) {
    return error.cause?.code === 'ECONNREFUSED' ? 'free' : 'taken';
  }
}

async function freePort() {
  for (;;) {
    const port = randomInt(waiterPorts.first, waiterPorts.last + 1);
    if (await canListen(port)) return port;
  }
}

function canListen(port) {
  return new Promise((resolve) => {
    const probe = createServer();
    probe.once('error', () => resolve(false));
    probe.listen(port, '127.0.0.1', () => probe.close(() => resolve(true)));
  });
}

function renderCrashes(plan) {
  const runtime = readFileSync(join(dirname(pack), 'visualplan.js'), 'utf8');
  const map = Array.isArray(plan.blocks) ? plan.blocks.find((b) => b?.kind === 'map') : null;
  const failures = new Map();
  for (const view of ['', ...Object.keys(map?.nodes ?? {})]) {
    try {
      vm.runInNewContext(runtime, browserStub(plan, view), { filename: 'runtime/visualplan.js' });
    } catch (error) {
      const line = String(error.stack).match(/runtime\/visualplan\.js:(\d+)/)?.[1];
      const message = line ? `${error.message}, at runtime/visualplan.js:${line}` : error.message;
      failures.set(message, [...(failures.get(message) ?? []), view || 'main page']);
    }
  }
  return [...failures].map(([message, views]) => `${message}, in ${views.join(', ')}`);
}

function browserStub(plan, view) {
  return {
    window: { PLAN: structuredClone(plan), addEventListener() {} },
    document: anything,
    history: anything,
    navigator: anything,
    CSS: anything,
    localStorage: anything,
    location: { hash: view ? `#${view}` : '' },
  };
}

function steWarnings(plan) {
  const linter = findSteLinter();
  if (!linter) return 'STE check skipped: the simple-english plugin is not installed.';
  const texts = [];
  collectProse(plan, 'plan', texts);
  const run = spawnSync('python3', ['-I', '-c', steScript, dirname(linter)], { input: JSON.stringify(texts), encoding: 'utf8' });
  if (run.error || run.status !== 0) return `STE check failed: ${run.error?.message ?? run.stderr.trim()}`;
  const hits = JSON.parse(run.stdout);
  return hits.map(([path, found]) => `warn  STE ${found} at ${path}`).join('\n');
}

function findSteLinter() {
  const root = join(claudeDir, 'plugins/cache/simple-english/simple-english');
  if (!existsSync(root)) return null;
  const [newest] = readdirSync(root).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
  const linter = newest && join(root, newest, 'evals/ste_lint.py');
  return linter && existsSync(linter) ? linter : null;
}

function collectProse(value, path, texts) {
  if (typeof value === 'string') {
    const text = plainText(value);
    if (text && !steSkippedFields.test(path)) texts.push([path, text]);
  } else if (Array.isArray(value)) {
    value.forEach((item, i) => collectProse(item, `${path}[${i}]`, texts));
  } else if (value && typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) collectProse(item, `${path}.${key}`, texts);
  }
}

function plainText(html) {
  return html
    .replace(/<code>[\s\S]*?<\/code>|`[^`]*`/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&')
    .trim();
}
