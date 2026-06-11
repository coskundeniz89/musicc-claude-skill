// Pulls YouTube/Google cookies live from a running Chromium-based browser
// (Brave/Chrome/Edge started with --remote-debugging-port=9222) and writes them
// as a Netscape cookies.txt for yt-dlp, enabling access to the user's own
// playlists (including private ones) with no API keys.
//
// The output file contains session tokens - it must stay on this machine.
// Never commit, share, or print its contents.
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const DEFAULT_DOMAINS = ['youtube.com', 'google.com'];

export function filterCookies(cookies, domains = DEFAULT_DOMAINS) {
  return cookies.filter((c) => domains.some((d) => c.domain.includes(d)));
}

export function toNetscapeLine(c) {
  return [
    c.domain,
    c.domain.startsWith('.') ? 'TRUE' : 'FALSE',
    c.path,
    c.secure ? 'TRUE' : 'FALSE',
    c.expires > 0 ? Math.floor(c.expires) : 0,
    c.name,
    c.value,
  ].join('\t');
}

export function toNetscapeFile(cookies) {
  return '# Netscape HTTP Cookie File\n' + cookies.map(toNetscapeLine).join('\n') + '\n';
}

export async function fetchCookiesViaCdp(endpoint = 'http://localhost:9222') {
  const { webSocketDebuggerUrl } = await (await fetch(`${endpoint}/json/version`)).json();
  const ws = new WebSocket(webSocketDebuggerUrl);
  return await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('CDP timeout')), 10000);
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Storage.getCookies', params: {} }));
    ws.onmessage = (e) => {
      const msg = JSON.parse(e.data);
      if (msg.id === 1) {
        clearTimeout(timer);
        resolve(msg.result.cookies);
        ws.close();
      }
    };
    ws.onerror = (e) => { clearTimeout(timer); reject(e); };
  });
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  const outFile = join(dirname(fileURLToPath(import.meta.url)), 'yt-cookies.txt');
  const wanted = filterCookies(await fetchCookiesViaCdp());
  writeFileSync(outFile, toNetscapeFile(wanted));
  console.log(`${wanted.length} cookies -> ${outFile}`);
}
