# Portal TV

A personal Apple TV app for watching an IPTV subscription from a **Stalker / MAC-address portal** (the kind that gives you a portal URL and registers a MAC address). Think of it as a small, readable iSTB: live channels, genres, favorites, now/next programme info, and a player that handles the raw MPEG-TS streams these portals hand out.

It plays only what your own subscription provides — the app contains no channels of its own.

## What's in the box

| Area | Where | What it does |
| --- | --- | --- |
| Portal protocol | `PortalTV/Stalker/` | Handshake → bearer token → profile, channel/genre catalog, `create_link` stream resolution, short EPG. Tolerant of the loose JSON real portals return. |
| State | `PortalTV/Store/` | `AppStore` (single source of truth) and `Persistence` (UserDefaults for profile/favorites, Caches for the channel list). |
| UI | `PortalTV/Views/` | Setup screen, channel browser (genres + grid + search), full-screen player with remote mapping. |
| Playback | KSPlayer (Swift Package, pinned 2.3.4) | FFmpeg-based engine; AVPlayer can't open MPEG-TS over HTTP. |

Minimum tvOS 18.0 (Apple TV HD and all Apple TV 4K models).

## Build and install — first time

You need a Mac with **Xcode 16 or newer** (free, Mac App Store) and your Apple TV on the same Wi-Fi.

1. **Clone** this repo and open `PortalTV.xcodeproj` in Xcode. The first open resolves KSPlayer and its FFmpeg binaries (a few hundred MB download) — wait for the package resolution spinner to finish.
2. **Pick your team**: select the `PortalTV` target → *Signing & Capabilities* → *Team* → choose your Apple ID. (Add it first under Xcode → Settings → Accounts if it isn't there.) If Xcode complains the bundle identifier is taken, change `com.bikkula.portaltv` to anything unique.
3. **Pair the Apple TV**: on the TV, *Settings → Remotes and Devices → Remote App and Devices*. In Xcode, *Window → Devices and Simulators*, select the Apple TV under *Discovered*, click *Pair*, and type the code the TV shows.
4. **Run**: choose the Apple TV in the destination picker next to the scheme (top of the Xcode window) and press ▶. The first build takes a few minutes.
5. On the TV, enter your **portal URL** (what your provider gave you, e.g. `http://host:8080/c/`) and the **MAC address** they registered, then *Connect*. The app checks the account with the portal before saving anything.

### Free Apple ID vs. developer program

With a free Apple ID the installed app expires after **7 days** — just press ▶ in Xcode again to reinstall (settings and favorites survive). A paid Apple Developer Program membership ($99/yr) makes installs last a year.

### Updating later

`git pull`, then ▶ in Xcode again. The project uses a synchronized folder, so new Swift files added under `PortalTV/` are picked up automatically — no project-file edits needed.

## Using it

| Remote | Channel browser | Player |
| --- | --- | --- |
| Swipe / arrows | Move focus | ▲ ▼ previous / next channel · ◀ ▶ show info |
| Click | Open channel | Toggle info overlay (retries after an error) |
| Long press | Add / remove favorite | — |
| Play/Pause | — | Pause / resume |
| Menu / Back | — | Back to the channel list |

The sidebar also has *Resume* (last channel), *Reload channels* and *Settings* (change portal, forget portal).

## Troubleshooting

- **"Couldn't connect to the portal"** — the handshake failed on every known endpoint. Check the URL (try with and without `/c/`), check the MAC is the one the provider registered, and confirm the subscription is active. The error text names what each endpoint answered.
- **"The portal blocked this device"** — the portal recognised the request but refuses this MAC (unregistered, or bound to a different device serial). Only the provider can fix that.
- **Channels load but nothing plays** — the stream URL came back but the player couldn't open it. Try another channel; if none play, the provider's stream servers may require a different user agent or may be down. Check the Xcode console for the KSPlayer error.
- **Stutter** — the Apple TV decodes in hardware when it can; stutter is usually network. Wired Ethernet helps.
- **Expired after a week** — free-account limit, see above.

## Development notes

See `CLAUDE.md` for conventions, the portal protocol reference, and the roadmap. Everything about *how* to build lives in this README; the plan lives there.

## Licenses

Portal TV is for personal use. It depends on [KSPlayer](https://github.com/kingslay/KSPlayer) (GPL) and its FFmpegKit binaries (LGPL/GPL). The Stalker client was written with the open-source [Lume](https://github.com/hamzza20/LumeIOS) client (AGPL-3.0) as a protocol reference. Distributing a build publicly would bring those licenses' obligations with it.
