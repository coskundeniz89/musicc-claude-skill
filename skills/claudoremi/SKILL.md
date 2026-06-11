---
name: claudoremi
description: Play and control music in the terminal while you work (mpv + yt-dlp; YouTube search, the user's own YouTube playlists, or local files). Use for requests like "play some music", "play X", "play my playlist", "list my playlists", "pause", "resume", "skip", "next song", "volume up/down", "set volume to 80", "mute", "what's playing", "stop the music".
---

# claudoremi — terminal music for Claude Code

Music plays in a **detached `mpv` process** in the background and is controlled over a
JSON IPC named pipe (`\\.\pipe\mpv-claude`). The music keeps playing after every tool
call ends — Claude only talks to it through the pipe.

Set `$mu` to this skill's base directory (printed at the top of this skill when it loads).
All helper files live there:

- `mpv-ipc.ps1` — sends one JSON command to the pipe (`-Read` for queries)
- `get-yt-cookies.mjs` — pulls YouTube cookies from the user's running Chromium browser (optional, for personal playlists)
- `yt-dlp.exe` — local copy, created on first use (system copies are often outdated)
- `yt-cookies.txt` — generated locally, **sensitive; never share, commit, or print it**

## Dependencies — bootstrap silently on first use

Never send the user off to install things; check and fix it yourself:

```powershell
$mpv = (Get-Command mpv -ErrorAction SilentlyContinue).Source
if (-not $mpv) { $mpv = @('C:\Program Files\MPV Player\mpv.exe', "$env:LOCALAPPDATA\Programs\mpv\mpv.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1 }
```

1. **mpv** missing → `winget install -e --id shinchiro.mpv --accept-source-agreements --accept-package-agreements` (lands in `C:\Program Files\MPV Player\mpv.exe`).
2. **yt-dlp**: always use `$mu\yt-dlp.exe`. If missing: `Invoke-WebRequest 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' -OutFile "$mu\yt-dlp.exe"`.
3. **Node.js**: required for YouTube (yt-dlp's "n challenge" solver) and the cookie bridge. If `node` is missing, ask the user before installing (`winget install -e --id OpenJS.NodeJS.LTS`).

When calling yt-dlp from the CLI, **always** pass `--js-runtimes node` (and `--cookies "$mu\yt-cookies.txt"` if the file exists).

## Interpreting the request

- **URL** (youtube.com / youtu.be / playlist) → play it directly
- **"my playlists" / "list my playlists"** → list the user's YouTube playlists
- **"play my <name> playlist"** → fetch the playlist list first, play the matching one
- **"liked videos"** → `list=LL`, **"watch later"** → `list=WL`
- **"stop" / "quit the music"** → quit mpv
- **"pause" / "resume"** → pause toggle
- **"mute" / "unmute"** → mute toggle (music keeps running, just silent)
- **any volume request** → state-aware: read the current state first, then decide which knob
  to turn (see Volume policy)
- **"skip" / "next"** → next track
- **"what's playing" / status questions** → `& "$mu\status.ps1"` (title, position, both volumes in one call)
- **local file/folder name** → play from the local music folder (`$env:USERPROFILE\Music` by default), shuffled
- **anything mentioning Spotify** ("play X on Spotify", "pause Spotify", "what's on Spotify") →
  use the Spotify engine (see Spotify section), not mpv
- **anything else** → treat as a YouTube search (the default engine)

## The user's YouTube account (optional)

With browser cookies, yt-dlp can list and play the user's own playlists — including
private ones — with **no API keys**. Works with any Chromium browser (Brave, Chrome, Edge)
started with `--remote-debugging-port=9222`:

```powershell
node "$mu\get-yt-cookies.mjs"        # writes $mu\yt-cookies.txt from the running browser
```

If port 9222 is closed, tell the user to start their browser with
`--remote-debugging-port=9222` (or skip account features — search still works without cookies).
As a fallback when the browser is **closed**, `--cookies-from-browser brave` (or `chrome`/`edge`)
also works; it fails with "Could not copy cookie database" while the browser is open.

List the user's playlists:

```powershell
& "$mu\yt-dlp.exe" --js-runtimes node --cookies "$mu\yt-cookies.txt" --flat-playlist --print "%(title)s :: %(url)s" "https://www.youtube.com/feed/playlists"
```

Same command with a playlist URL at the end shows its tracks. If a private playlist
returns "sign in" / "unavailable", the cookies are stale — re-run the cookie bridge.

## Playing (always a single instance)

```powershell
Stop-Process -Name mpv -ErrorAction SilentlyContinue -Confirm:$false
```

Shared mpv arguments (add to every play command):

```powershell
$mpvArgs = @('--no-video','--volume=55','--force-window=no',
  '--input-ipc-server=\\.\pipe\mpv-claude',
  '--input-media-keys=no',
  "--script-opts=ytdl_hook-ytdl_path=$mu\yt-dlp.exe",
  "--ytdl-raw-options=cookies=$mu\yt-cookies.txt,js-runtimes=node",
  '--ytdl-format=bestaudio',
  "--log-file=$mu\mpv.log")
```

(If `yt-cookies.txt` doesn't exist, drop the `cookies=` part of `--ytdl-raw-options`.)

YouTube search (single result — ideal for radio/long mixes; use `ytsearch10:` for a queue):

```powershell
Start-Process $mpv -ArgumentList ($mpvArgs + '"ytdl://ytsearch1:SEARCH QUERY"')
```

Playlist/URL (the user's own playlists work too, thanks to cookies):

```powershell
Start-Process $mpv -ArgumentList ($mpvArgs + @('--shuffle','"https://www.youtube.com/playlist?list=..."'))
```

Local folder (shuffled, endless):

```powershell
Start-Process $mpv -ArgumentList ($mpvArgs + @('--shuffle','--loop-playlist=inf',"`"$env:USERPROFILE\Music`""))
```

Single local file: pass the file path instead (no `--shuffle`/`--loop-playlist`).
Arguments containing spaces need embedded quotes: `'"..."'`.

## Verify before you claim — the golden rule

**Never tell the user something worked until you've read the state back.** Resolution can
take 10–30 s (yt-dlp + the Node challenge solver), and a started process is not the same
as audible music.

- After starting playback: poll `media-title` every 3 s (up to ~12 tries) until it answers,
  then read `playback-time` twice ~3 s apart. **Only if it increased** report "now playing".
  A raw `ytsearch1:...` title means it's still resolving — keep polling.
- After changing volume/mute/pause: read the property back and report the **actual** value.
- If `playback-time` doesn't advance or mpv exits: say so honestly, diagnose (process alive?
  yt-dlp error? stale cookies?) and retry yourself — e.g. rephrase the search. Don't make
  the user debug.

## Control (IPC)

```powershell
& "$mu\mpv-ipc.ps1" -Json '{"command":["cycle","pause"]}'                                        # pause/resume
& "$mu\mpv-ipc.ps1" -Json '{"command":["playlist-next"]}'                                       # next track
& "$mu\mpv-ipc.ps1" -Json '{"command":["set_property","volume",80]}'                            # volume 0-100 (boost up to 130)
& "$mu\mpv-ipc.ps1" -Json '{"command":["add","volume",10]}'                                     # volume up a bit (negative: down)
& "$mu\mpv-ipc.ps1" -Json '{"command":["cycle","mute"]}'                                        # mute/unmute toggle
& "$mu\mpv-ipc.ps1" -Json '{"command":["get_property","media-title"],"request_id":1}' -Read     # what's playing
& "$mu\mpv-ipc.ps1" -Json '{"command":["get_property","volume"],"request_id":2}' -Read          # current volume
& "$mu\mpv-ipc.ps1" -Json '{"command":["get_property","mute"],"request_id":3}' -Read            # mute state
& "$mu\mpv-ipc.ps1" -Json '{"command":["get_property","playback-time"],"request_id":4}' -Read   # position (for verification)
```

## Volume policy — always state-aware

The user changes volume by hand too (media keys, the mixer, headphone dials). Whatever you
set last time may no longer be true. For **every** volume request:

1. **Read fresh state first:** `& "$mu\status.ps1"` — gives master %, mpv %, both mute flags.
2. What the user hears ≈ **master% × mpv%**. Decide which knob to turn:
   - master muted or < 20% → fix master first; it's the bottleneck
   - master reasonable (≥ ~30%) → prefer adjusting mpv, so other apps' audio is untouched
   - mpv already at 100 and the user wants louder → raise master (or boost mpv up to 130 as a last resort)
3. **"louder" / "quieter"** → a clearly noticeable step (≈ ±10–15 effective points), not a token nudge.
4. **"set volume to X"** → set mpv to X; if master is outside a sane band (~30–70%), bring it
   into the band too, and say so.
5. Read back after changing and tell the user both values — including what you *found*, e.g.
   "master was down to 12% (hand-adjusted?), brought it to 40%, mpv stays at 75."

## System volume (Windows master)

What the user hears is **Windows master volume × mpv volume** — a 7% master makes mpv's 75
inaudible. When the user means the computer's volume, or complains they can't hear despite
mpv's volume being fine, use the bundled helper (precise, verifiable):

```powershell
& "$mu\master-volume.ps1"            # print current % and mute state
& "$mu\master-volume.ps1" -Set 40    # set master volume to 40%
& "$mu\master-volume.ps1" -Unmute    # or -Mute
```

Fallback without the helper: simulate media keys (each press is ±2 of 100):

```powershell
$sh = New-Object -ComObject WScript.Shell
1..10 | ForEach-Object { $sh.SendKeys([char]175) }   # up +20  ([char]174 down, [char]173 mute toggle)
```

## Stopping

```powershell
& "$mu\mpv-ipc.ps1" -Json '{"command":["quit"]}'
Stop-Process -Name mpv -ErrorAction SilentlyContinue -Confirm:$false   # if the pipe doesn't answer
```

## Troubleshooting

- **Playback advances but the user hears nothing (or barely)** → check the Windows master
  volume and mute first (`& "$mu\master-volume.ps1"`), then the default output device
  (headphones unplugged? audio routed to an HDMI monitor?). Don't keep raising mpv's volume
  past 100 — fix the master instead.
- **Pipe not found** → mpv died (or never started). Check `Get-Process mpv`, restart playback.
- **"Only images are available" / "n challenge solving failed"** → Node missing or
  `--js-runtimes node` not passed. Fix and retry.
- **Private playlist asks to sign in** → stale cookies; re-run `node "$mu\get-yt-cookies.mjs"`.
- **Two mpv processes** → kill all (`Stop-Process -Name mpv -Force`) and start one cleanly.
- **winget missing** → download mpv from https://mpv.io/installation/ and yt-dlp from GitHub releases manually.

## Spotify (no API key, no Premium needed)

For users who'd rather listen on Spotify. `spotify.ps1` reads "now playing" from Spotify's
window title and drives playback with global media keys — it **remote-controls the Spotify
desktop app**, it does not host audio itself. No Web API, no client ID, no Premium requirement.

```powershell
& "$mu\spotify.ps1"                       # status / now playing
& "$mu\spotify.ps1" -Control playpause    # playpause | next | previous | stop
& "$mu\spotify.ps1" -Open "miles davis"   # open Spotify to a search results page
& "$mu\spotify.ps1" -Uri spotify:track:.. # launch (and play) a specific track/playlist URI or link
```

**Two hard truths, verified live — state these honestly, don't over-claim:**

1. **Closing Spotify stops the music.** We control the user's app; it isn't our player. If the
   user closes Spotify, playback ends — that's by design, not a bug. For background music that
   survives with no app open, that's the **YouTube/mpv engine**, not Spotify.
2. **`-Control playpause` only resumes whatever track is already loaded** — it does NOT play a
   named search result. And `-Open "X"` opens the *search page* but does not auto-play track X.
   So "play <name> on Spotify" cannot reliably start that exact track without its URI.

Routing:
- **"pause / resume / next / previous on Spotify"** → `-Control ...` (fully reliable; verify by
  reading status back).
- **"what's playing on Spotify"** → run with no args.
- **"play a specific Spotify link/URI"** → `-Uri spotify:...` (this *does* start that track).
- **"play <name> on Spotify"** → be honest: run `-Open "<name>"` to bring up results and ask the
  user to click a track, OR offer to play it on YouTube instead (which can start a named track
  directly). Don't claim you started "<name>" on Spotify when you only opened a search.
- If `spotify.ps1` reports **not installed**, say so and offer the YouTube engine.
- Note `-Open`/`-Uri` will **relaunch Spotify if it was closed** — which can leave two sources
  playing at once (see below).

**One engine at a time (default).** mpv (YouTube/local) and Spotify are independent audio
sources and will happily play *over each other*. Before starting one, check whether the other is
already playing (`status.ps1` for mpv, `spotify.ps1` for Spotify) and pause/stop it first, unless
the user explicitly wants both. Our mpv launches with `--input-media-keys=no` so it never steals
the hardware media keys that drive Spotify.

## Notes

- After every action tell the user briefly what's playing / what changed; don't dump raw output.
- mpv opens no window (`--force-window=no`); audio shows up as "mpv" in the Windows volume mixer.
- Platform: built for Windows 10/11 (PowerShell + named pipes). On macOS/Linux the same flow
  works with `--input-ipc-server=/tmp/mpv-claude` and writing JSON to that socket
  (e.g. `echo '{"command":[...]}' | socat - /tmp/mpv-claude`).
- If this folder is ever shared/published: `yt-cookies.txt` and `yt-dlp.exe` must never be
  included (personal cookies; per-user binary).
