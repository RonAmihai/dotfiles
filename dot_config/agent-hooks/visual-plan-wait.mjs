import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';

const maxBodyBytes = 1_000_000;
const cors = { 'Access-Control-Allow-Origin': '*' };

const paste = process.argv.includes('--paste');
const plan = process.argv.slice(2).find((arg) => arg !== '--paste') ?? '';
const relayPath = plan.replace(/\.(md|ya?ml)$/, '.relay.json');
const relay = JSON.parse(readFileSync(relayPath, 'utf8'));
const { port, token } = relay;

const server = createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  if (url.searchParams.get('token') !== token) {
    response.writeHead(403, cors).end();
    return;
  }
  if (request.method === 'GET' && url.pathname === '/ping') {
    response.writeHead(200, cors).end('waiting');
    return;
  }
  if (request.method !== 'POST' || url.pathname !== '/respond') {
    response.writeHead(404, cors).end();
    return;
  }
  let body = '';
  request.setEncoding('utf8');
  request.on('data', (chunk) => {
    body += chunk;
    if (body.length > maxBodyBytes) request.destroy();
  });
  request.on('end', () => {
    response.writeHead(200, cors).end('sent', () => {
      deliver(`My response from the visual plan page:\n\n${body}`);
      stop();
    });
  });
});

// The agent session is the parent of the shell that started the waiter; after it ends, no one reads the response.
const session = Number(process.env.VISUAL_PLAN_SESSION_PID) || parentOf(process.ppid);
if (session) setInterval(() => { if (!alive(session)) process.exit(0); }, 60_000).unref();
// Codex runs hooks under a daemon that outlives the session, so a Codex waiter also gets a time limit.
const maxHours = Number(process.env.VISUAL_PLAN_MAX_HOURS) || 0;
if (maxHours) setTimeout(stop, maxHours * 3_600_000).unref();

server.on('error', (error) => {
  const busy = `Port ${port} is in use. Pack the plan again, so that it gets a free port, and start the waiter again.`;
  console.log(error.code === 'EADDRINUSE' ? busy : `The waiter did not start: ${error.message}`);
  stop();
});
server.listen(port, '127.0.0.1', openPageOnce);

function openPageOnce() {
  const opener = { darwin: 'open', linux: 'xdg-open' }[process.platform];
  const page = plan.replace(/\.(md|ya?ml)$/, '.html');
  if (relay.opened || !opener || !existsSync(page)) return;
  spawnSync(opener, [page]);
  writeFileSync(relayPath, JSON.stringify({ ...relay, opened: true }));
}

function deliver(text) {
  if (paste) spawnSync('cmux', ['paste', '--surface', process.env.CMUX_SURFACE_ID ?? '', '--submit', text]);
  else console.log(text);
}

function stop() {
  server.close(() => {});
  server.closeAllConnections();
}

function parentOf(pid) {
  try {
    return Number(execFileSync('ps', ['-o', 'ppid=', '-p', String(pid)], { encoding: 'utf8' }).trim()) || null;
  } catch {
    return null;
  }
}

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === 'EPERM';
  }
}
