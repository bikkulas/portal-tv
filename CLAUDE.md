# Portal TV — working notes for Claude (and humans)

Build/install instructions are in `README.md`; this file is the plan, the conventions and the protocol reference.

## Project shape

- tvOS 18+, Swift 5 language mode, SwiftUI, `@Observable` store, Swift concurrency. No SwiftData, no third-party UI.
- One synchronized folder (`PortalTV/`) — add a Swift file to the right subfolder and Xcode picks it up; **never hand-edit `project.pbxproj` to add files**. Build settings changes do go in the pbxproj (it is hand-written and validated with a plist parser; keep object IDs 24 hex chars).
- `Config/Info.plist` holds only what build settings can't express (App Transport Security). Other Info.plist keys are `INFOPLIST_KEY_*` build settings.
- Dependencies: KSPlayer pinned to **exact 2.3.4** (the version Lume ships with on current Xcode). Don't bump casually; its SwiftUI/Coordinator API moves between versions.
- The developer's Mac may be linked to the Claude session; when it is, build with `xcodebuild -project PortalTV.xcodeproj -scheme PortalTV -destination 'generic/platform=tvOS' build` and read errors from there instead of guessing. No Swift toolchain exists in the cloud workspace.

## Conventions

- Portal credentials (URL, MAC) are typed on the TV and live in UserDefaults; they never appear in the repo, logs with `privacy: .public`, or chat.
- Every portal field is optional and decoded through `LenientString`. Never assume a type; portals send `"12"` and `12` interchangeably.
- Stream URLs from `create_link` are resolved at play time and never cached.
- Errors surface as `StalkerError` with user-readable `errorDescription`; the UI shows those strings verbatim.
- Keep the app small. A feature that needs a second screen of settings probably doesn't belong.

## Stalker (Ministra) protocol reference

Endpoint is one of `/portal.php`, `/server/load.php`, `/stalker_portal/server/load.php`; the handshake probes in that order (stalker_portal first if the pasted URL mentions it) and pins the first that returns JSON.

Headers on every call:

```
User-Agent: Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Std Beta. Lib: 2.6.16-15
X-User-Agent: Model: MAG250; Link: WiFi
Referer: http://host/c/            (or /stalker_portal/c/)
Cookie: mac=00:1A:79:XX:XX:XX; stb_lang=en; timezone=America/Los_Angeles
Authorization: Bearer <token>      (after handshake)
```

Calls (all `GET …?type=&action=&…&JsHttpRequest=1-xml`, answers wrapped in `{"js": …}`):

| Call | Notes |
| --- | --- |
| `stb/handshake&token=` | → `js.token`. Then `stb/get_profile` once to activate it. |
| `stb/get_profile` | `status`, `exp_date`, `msg`, `block_msg`. Non-zero status **plus** a message = device blocked. |
| `itv/get_genres` | `[{id,title}]`, skip id `*`. |
| `itv/get_all_channels` | `js.data` (or bare array): `id,name,number,cmd,logo,tv_genre_id,xmltv_id`. |
| `itv/create_link&cmd=<cmd>` | → `js.cmd` = `ffmpeg http://…`; playable URL is the first `http(s)://` token. Forward query params embedded in a URL-shaped cmd (except mac/play_token) for Xtream-UI emulations. Empty `stream=` in the answer means unplayable. |
| `itv/get_short_epg&ch_id=` | `[{name,descr,time,time_to,start_timestamp,stop_timestamp}]`; best effort. |
| `epg/get_simple_data_table&ch_id=&date=` | Full-day EPG (not used yet). |
| `vod/*`, `series/*` | Categories + `get_ordered_list` pages of ~14 (not used yet). |

Token expiry shows up as a small body `Authorization failed.` → re-handshake once and retry. The query string is built by hand with strict percent-encoding because PHP reads `+` as a space.

## Roadmap

1. ✅ Settings → handshake → channel list
2. ✅ Playback with ▲▼ channel switching, favorites, search, resume
3. ⬜ First real-device test: confirm handshake, logo URLs and TS playback with the user's portal; fix what breaks
4. ⬜ App icon / top-shelf asset catalog
5. ⬜ Full programme guide (`get_simple_data_table`) and catch-up where the portal supports it
6. ⬜ VOD / series browsing
7. ⬜ Multiple portal profiles
