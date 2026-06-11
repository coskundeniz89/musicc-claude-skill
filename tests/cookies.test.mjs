import test from 'node:test';
import assert from 'node:assert/strict';
import { filterCookies, toNetscapeLine, toNetscapeFile } from '../skills/claudoremi/get-yt-cookies.mjs';

const cookie = (over = {}) => ({
  domain: '.youtube.com',
  path: '/',
  secure: true,
  expires: 1750000000,
  name: 'SID',
  value: 'abc',
  ...over,
});

test('toNetscapeLine formats a persistent secure cookie', () => {
  assert.equal(toNetscapeLine(cookie()), '.youtube.com\tTRUE\t/\tTRUE\t1750000000\tSID\tabc');
});

test('host-only cookie gets FALSE subdomain flag', () => {
  const line = toNetscapeLine(cookie({ domain: 'music.youtube.com' }));
  assert.match(line, /^music\.youtube\.com\tFALSE\t/);
});

test('session cookie (expires -1) becomes 0', () => {
  const line = toNetscapeLine(cookie({ expires: -1 }));
  assert.equal(line.split('\t')[4], '0');
});

test('non-secure cookie gets FALSE secure flag', () => {
  const line = toNetscapeLine(cookie({ secure: false }));
  assert.equal(line.split('\t')[3], 'FALSE');
});

test('fractional expiry is floored to an integer', () => {
  const line = toNetscapeLine(cookie({ expires: 1750000000.75 }));
  assert.equal(line.split('\t')[4], '1750000000');
});

test('filterCookies keeps youtube/google domains, drops the rest', () => {
  const all = [cookie(), cookie({ domain: '.google.com' }), cookie({ domain: '.example.com' })];
  const kept = filterCookies(all);
  assert.deepEqual(kept.map((c) => c.domain), ['.youtube.com', '.google.com']);
});

test('filterCookies accepts custom domain list', () => {
  const all = [cookie(), cookie({ domain: '.example.com' })];
  const kept = filterCookies(all, ['example.com']);
  assert.deepEqual(kept.map((c) => c.domain), ['.example.com']);
});

test('toNetscapeFile starts with the Netscape header and ends with a newline', () => {
  const out = toNetscapeFile([cookie(), cookie({ domain: '.google.com' })]);
  assert.ok(out.startsWith('# Netscape HTTP Cookie File\n'));
  assert.ok(out.endsWith('\n'));
  assert.equal(out.trimEnd().split('\n').length, 3); // header + 2 cookies
});
