# LanGuard — Launch & Promotion Playbook

Everything needed to publish LanGuard where it'll actually get seen. Ranked by ROI for a
free, open-source macOS menu-bar utility. Copy blocks are ready to paste.

> Honesty rules for every post: it's **brand-new** (few stars), **ad-hoc signed / not
> notarized** (first launch needs right-click → Open), **macOS 14+**, **free + MIT**, **no
> admin / no network calls**. Don't overclaim. Don't beg for upvotes. Keep tip-jar links out
> of launch posts — they live on the repo.

---

## 0. Pre-launch checklist (do these first)

- [ ] **Upload the social preview** — GitHub repo → Settings → General → Social preview → upload `docs/social-preview.png` (1280×640). Makes every shared link unfurl branded.
- [ ] **Record a demo GIF** (the #1 missing asset). Shot list: app in menu bar (Wi-Fi state) → plug in Ethernet → indicator flips to `LAN` + a "Wi-Fi off" banner → open the menu showing status → unplug → Wi-Fi comes back. ~8–10s, ~1200px wide, <5MB, looping. Tools: **Kap** or QuickTime + Gifski. Put it at the top of the README and reuse on PH/Reddit/socials.
- [ ] **Add Settings screenshots** (per-interface picker w/ the `virtual` badge, indicator styles) to the README.
- [ ] **Pre-age accounts** — Product Hunt requires the account be **2+ weeks old**; Reddit subs often need ~100+ karma. Create/warm these now if needed.
- [x] **SHA-256** is published in the v1.0.0 release body (`4070b8ee…8ddd8e`) so people can verify the download.
- [ ] **Pin the repo** on your GitHub profile; seed a **Discussions → Announcements** post for v1.0.0.

---

## 1. Channels — ranked by ROI

| Priority | Channel | URL | The one rule that matters |
|---|---|---|---|
| 🔥 CRITICAL | **MacPowerUsers Talk** (warmest, most technical) | https://talk.macpowerusers.com/c/apple/mac/6 | Search first, reply in existing threads; engage 48h, don't drive-by. |
| 🔥 CRITICAL | **Hacker News — Show HN** | https://news.ycombinator.com/submit | Plain title, no hype/emoji; you post it; never ask for upvotes; no tip link. |
| ⭐ HIGH | **Reddit r/macapps** | https://www.reddit.com/r/macapps/ | Disclose you're the dev + lead with a screenshot. |
| ⭐ HIGH | **Product Hunt** | https://www.producthunt.com/products/new | Need media (GIF) + 2-wk-old account; launch 12:01am PT Tue–Thu. |
| ⭐ HIGH | **MacRumors** — forum post *and* news tip | Forum: https://forums.macrumors.com/forums/macos.50/ · Tip: tips@macrumors.com | Frame as "a tool that solves X", not "I made an app". |
| ◾ MED | Reddit r/macos | https://www.reddit.com/r/macos/ | Self-promo disclaimer + screenshot; don't same-day cross-post w/ r/macapps. |
| ◾ MED | Reddit r/swift | https://www.reddit.com/r/swift/ | Frame as "how I built it" (CoreWLAN/SystemConfiguration), not a product pitch. |
| ◾ MED | Reddit r/opensource | https://www.reddit.com/r/opensource/ | Lead with MIT + motivation; don't lead with Ko-fi. |
| ◾ MED | **AlternativeTo** (list under both) | https://alternativeto.net/software/bridgechecker/ · https://alternativeto.net/software/togglewifi/ | Factual comparison only, no "BEST/MUST-HAVE". |
| ◾ MED | **Automators forum** (automation crowd) | https://talk.automators.fm/ | Frame around the automation/edge-based design. |
| ◽ LOW-MED | Lobsters | https://lobste.rs/ | Needs invite; `show` tag; genuinely technical only. |
| ◽ LOW-MED | Mastodon / Fosstodon | https://fosstodon.org | Lead with privacy (no tracking/network); add image alt text. |
| ◽ LOW-MED | Bluesky | https://bsky.app | `#macOS #opensource`; let the link card preview. |
| ◽ LOW | r/apple | https://www.reddit.com/r/apple/ | Heavily moderated; frame as user benefit, not "I made". |
| ◽ LOW | Swift/macOS Slack & Discord (#showcase) | MacAdmins Slack, indie/Swift Discords | 1 post/week; better to answer a question then mention it. |

> **Don't** post to **iOS Dev Weekly** — it's iOS/app-dev focused, wrong fit for a macOS utility.
> Consider **Macworld** (tips) and **Setapp** (if you ever want paid distribution) as extras.

---

## 2. Warm threads (reply, don't cold-promo)

Search these, find people who already asked for exactly this, and reply with LanGuard:

- MacPowerUsers: https://talk.macpowerusers.com/search?q=wifi%20ethernet%20automatically%20disable
- MacRumors: https://forums.macrumors.com/search/?search=disable+wifi+when+ethernet+connected
- r/macos: https://www.reddit.com/r/macos/search/?q=disable%20wifi%20ethernet&type=link&sort=new
- r/macapps: https://www.reddit.com/r/macapps/search/?q=wifi%20ethernet%20toggle&type=link
- r/swift (API credibility): https://www.reddit.com/r/swift/search/?q=CoreWLAN&type=link

---

## 3. "Awesome list" PRs (passive long-tail discovery)

Open one PR per list. Search for duplicates first; keep entries alphabetical; descriptions end with a period.

**iCHAIT/awesome-macOS** → section *Utilities* — https://github.com/iCHAIT/awesome-macOS
<sub>(The `[OSS Icon]` / `[Freeware Icon]` refs below are defined in that list's README — they render there, not when previewing this file.)</sub>
```
- [LanGuard](https://github.com/roypadina/LanGuard) - Turns Wi-Fi off when a wired Ethernet link is active, back on when unplugged. Edge-based, wake-aware, no admin rights. [![Open-Source Software][OSS Icon]](https://github.com/roypadina/LanGuard) ![Freeware][Freeware Icon]
```

**jaywcjlove/awesome-swift-macos-apps** → *Menubar* (very active) — https://github.com/jaywcjlove/awesome-swift-macos-apps
```
- [LanGuard](https://github.com/roypadina/LanGuard) <img align="bottom" height="13" src="https://badgen.net/github/stars/roypadina/LanGuard?style=flat&label=" /> - Turns Wi-Fi off when a wired Ethernet link is active, back on when unplugged. Edge-based, wake-aware, no admin rights.
```

**serhii-londar/open-source-mac-os-apps** → edit `applications.json`, *Menubar* — https://github.com/serhii-londar/open-source-mac-os-apps
```json
{ "title": "LanGuard", "short_description": "Wi-Fi off when wired LAN active, back on when unplugged. Edge-based, wake-aware, no admin.", "repo_url": "https://github.com/roypadina/LanGuard", "official_site": "https://github.com/roypadina/LanGuard", "categories": ["Menubar"], "languages": ["Swift"] }
```

**matteocrippa/awesome-swift** → macOS subsection (secondary) — https://github.com/matteocrippa/awesome-swift
```
- [LanGuard](https://github.com/roypadina/LanGuard) - Menu-bar utility that toggles Wi-Fi on wired Ethernet plug/unplug.
```

---

## 4. Newsletters / roundups

| Outlet | Submit | Pitch |
|---|---|---|
| Indie Dev Monday | newsletter@indiedevmonday.com | Open-source macOS utility: auto-manages Wi-Fi when docking to Ethernet, zero sudo/scripts, built by a solo dev. |
| Console.dev | https://console.dev/ | OSS macOS menu-bar tool: toggles Wi-Fi on wired link changes via CoreWLAN + SystemConfiguration, no privileges. |
| MacStories | https://www.macstories.net/contact | Native SwiftUI app: turns Wi-Fi off when docked to Ethernet, on when unplugged; edge-triggered, respects manual overrides. |
| Swift Weekly Brief | https://github.com/SwiftWeekly/swiftweekly.github.io/issues | Pure Swift/CoreWLAN Wi-Fi toggling — wake-aware, edge-based, fully unit-tested, MIT. |
| Macworld (tip) | tips@macworld.com | Free open-source alternative to manual Wi-Fi toggling when docking; no admin; MIT. |

---

## 5. Ready-to-paste copy

### Hacker News — Show HN
**Title** (goes in the title field; no period, no emoji):
```
Show HN: LanGuard – turn Wi-Fi off when Ethernet is plugged in (macOS menu bar)
```
**URL field:** `https://github.com/roypadina/LanGuard`
**Text:**
```
I built a small macOS menu-bar app that turns Wi-Fi off when a wired Ethernet link goes up, and back on when you unplug. It scratches my own itch: docking the laptop and not having it quietly stay on Wi-Fi while a wired connection is sitting right there.

The design choices that make it less annoying than the naive version:

Edge-based. It acts only on plug/unplug transitions, not by continuously enforcing a state. If I plug in (Wi-Fi goes off) and then deliberately turn Wi-Fi back on, it leaves it alone until the next unplug/replug. The last wired state is persisted, so a transition that happened during sleep is treated as an edge on wake and corrected then.

Per-interface config. You pick which wired adapters count as a trigger and which Wi-Fi adapters it's allowed to control. Virtual/VPN/VM adapters (VMware vmnet and the like) are listed but off by default, so a VM bridge doesn't get mistaken for "I'm on Ethernet now." Real adapters are on by default; new ones are auto-included.

There's also the usual small stuff: optional toggle notifications, a configurable menu-bar indicator (LAN/Wi-Fi/Off), a master pause switch, and start-at-login via a self-healing login item.

On the technical side: native Swift 5 / SwiftUI using MenuBarExtra. Wi-Fi power goes through CoreWLAN, link state comes from SystemConfiguration (SCDynamicStore callbacks), with an ifconfig read as a fallback. No sudo, no admin rights, no privileged helper, and it never uses networksetup. It's un-sandboxed (CoreWLAN power + login-item management need it). It makes no network calls of its own, no ads, no tracking. The edge decision logic is dependency-injected and unit-tested.

Honest limitations:
- It's brand new. Very few stars, not much real-world mileage yet, so expect rough edges and please file issues.
- macOS 14+ (Sonoma) only.
- Ad-hoc signed and NOT notarized. First launch needs right-click -> Open, or `xattr -dr com.apple.quarantine` on the app. If that tradeoff bothers you, build from source.

Install: `brew install --cask roypadina/tap/languard` (my own tap) or build from source. MIT.

Prior art: BridgeChecker (commercial, ~$50) and ToggleWifi (open source, but from its public docs it requires admin and doesn't expose per-interface selection or document wake handling — happy to be corrected). LanGuard's niche is the combination of per-interface control, wake handling, and no admin requirement, for free.

Happy to answer questions about the CoreWLAN/SystemConfiguration approach or the edge-triggering logic.
```

### Reddit — r/macapps
**Title:**
```
[Open Source] LanGuard — menu-bar app that turns Wi-Fi off when you plug in Ethernet, back on when you unplug (macOS 14+)
```
**Body:** (attach screenshot/GIF — required)
```
Disclosure: I'm the developer.

I built this to fix one thing: when I dock and plug in Ethernet, macOS leaves Wi-Fi on too. LanGuard turns Wi-Fi off when a wired LAN link goes active and back on when you unplug.

How it works:
- Edge-based — acts only on plug/unplug transitions. If you manually turn Wi-Fi back on while still wired, it leaves it alone until the next unplug.
- Wake-aware — re-checks and corrects state after sleep.
- Per-interface config — pick which wired adapters count as a trigger and which Wi-Fi adapter it controls.
- Ignores virtual/VPN/VM adapters (e.g. VMware vmnet) so they don't falsely trigger it.
- No sudo, no admin rights. Uses CoreWLAN + SystemConfiguration. Native Swift / SwiftUI.
- Optional notifications, configurable indicator (LAN / Wi-Fi / Off), master pause switch, start-at-login.
- No ads, no tracking, makes no network calls of its own.

Install: `brew install --cask roypadina/tap/languard` (my own tap), or build from source.
Gatekeeper: ad-hoc signed but not notarized yet — first launch is right-click → Open, or `xattr -dr com.apple.quarantine /Applications/LanGuard.app`.
Status: brand new, very few stars, requires macOS 14 (Sonoma)+. Bug reports and PRs welcome.

Alternatives I knew about: BridgeChecker (commercial, ~$50) and ToggleWifi (open source, but from its docs needs admin and has no per-interface selection — happy to be corrected). LanGuard's niche: per-interface + wake-aware + no-admin + free.

Repo (MIT): https://github.com/roypadina/LanGuard
```

### Reddit — r/macos
**Title:** `I made a free menu-bar app that turns Wi-Fi off when Ethernet is plugged in, and back on when you unplug`
**Body:**
```
Self-promotion disclaimer: I'm the developer, it's free and open source (MIT), I'm not selling anything.

If you dock your Mac to wired Ethernet, macOS leaves Wi-Fi on anyway. LanGuard turns Wi-Fi off when a wired link goes up and back on when you unplug.

- Edge-based: it only acts on the plug/unplug moment. Turn Wi-Fi back on manually while docked and it leaves that alone until your next unplug.
- Reconciles state after sleep.
- You pick which wired adapters trigger it and which Wi-Fi adapters it controls; virtual/VPN/VM adapters are ignored by default.
- No admin rights (CoreWLAN + SystemConfiguration). No network calls of its own, no ads, no tracking.

Honest: brand new (few stars), ad-hoc signed/not notarized (first launch: right-click → Open, or xattr -dr com.apple.quarantine), macOS 14+.

Install: brew install --cask roypadina/tap/languard, or build from source.
Source: https://github.com/roypadina/LanGuard
```

### Reddit — r/swift
**Title:** `LanGuard: a SwiftUI MenuBarExtra app (CoreWLAN + SystemConfiguration) that toggles Wi-Fi on Ethernet plug/unplug — source MIT`
**Body:**
```
I'm the author; sharing the source since the CoreWLAN / SystemConfiguration bits might be useful.

- Wi-Fi power via CoreWLAN setPower; link/IPv4 state via SCDynamicStore callbacks (ifconfig fallback).
- Wake handling via NSWorkspace.didWakeNotification; last wired state persisted so a sleep transition is seen as an edge on wake.
- SwiftUI MenuBarExtra + a Settings window.
- Decision logic is a separate, edge-triggered ToggleEngine with injected dependencies — unit-tested without hardware (swift test, no NIC needed).
- Login item via SMAppService, re-registers if the bundle path changes.

Un-sandboxed (CoreWLAN power needs it), ad-hoc signed/not notarized, macOS 14+, Swift 5 mode.
Source (MIT): https://github.com/roypadina/LanGuard
Feedback on link-state/wake edge cases welcome.
```

### Product Hunt
- **Name:** `LanGuard`
- **Tagline (≤60):** `Wi-Fi off when you plug in Ethernet, on when you don't`
- **Description (≤260):**
```
Free, open-source macOS menu-bar app. Turns Wi-Fi off when a wired Ethernet link goes up, back on when you unplug. Edge-based so it respects manual changes, wake-aware, per-interface. No admin rights. macOS 14+. MIT.
```
- **First (maker) comment:**
```
I'm the maker. I built LanGuard to stop my docked laptop from quietly staying on Wi-Fi when a wired connection was right there. It only acts on plug/unplug transitions, so if you turn Wi-Fi back on manually it leaves it alone until you next unplug. Native Swift/SwiftUI, talks to CoreWLAN and SystemConfiguration directly — no sudo, no admin rights. It's brand new, so expect rough edges and please file issues. Heads up: it's ad-hoc signed, not notarized, so first launch needs right-click → Open (or build from source). Free and MIT. Repo: https://github.com/roypadina/LanGuard
```

### X / Twitter — single post
```
Made a tiny free macOS menu-bar app: LanGuard. Plug in Ethernet -> Wi-Fi turns off. Unplug -> Wi-Fi comes back. Edge-based so it respects manual changes, wake-aware, per-interface. No admin rights. macOS 14+. MIT, open source. https://github.com/roypadina/LanGuard
```

### X / Twitter — 3-post thread
```
1/ I built LanGuard: a small macOS menu-bar app that turns Wi-Fi off when a wired LAN link is active and back on when you unplug. Free, open source (MIT). No admin rights needed. macOS 14+ — https://github.com/roypadina/LanGuard

2/ What I tried to get right:
- Edge-based: acts only on plug/unplug, so a manual Wi-Fi toggle is respected until the next unplug
- Wake-aware: corrects state after sleep
- Per-interface: pick which adapters trigger / get controlled
- Auto-ignores virtual/VPN/VM adapters

3/ Honest status: brand-new, few stars, ad-hoc signed and not notarized yet — first launch needs right-click -> Open.
brew install --cask roypadina/tap/languard (or build from source)
No ads, no tracking, no network calls of its own.
```

### Mastodon / Bluesky
```
Made a tiny free macOS menu-bar app: LanGuard. Plug in Ethernet -> Wi-Fi turns off. Unplug -> Wi-Fi comes back. Edge-based (respects manual changes), wake-aware, per-interface. No admin rights. macOS 14+. Open source (MIT). https://github.com/roypadina/LanGuard #macOS #opensource
```
(Mastodon: attach a screenshot + add image alt text.)

### LinkedIn
```
I open-sourced LanGuard — a small, free macOS menu-bar app (MIT).

When you plug into wired Ethernet, it turns Wi-Fi off automatically; when you unplug, it turns Wi-Fi back on.

- Edge-based: acts only on plug/unplug transitions, so a manual Wi-Fi toggle is respected until the next unplug.
- Wake-aware: re-checks and corrects state after sleep.
- Per-interface: choose which wired adapters trigger it and which Wi-Fi adapters it controls; virtual/VPN/VM adapters are auto-ignored.
- No admin rights: built on CoreWLAN + SystemConfiguration, native Swift/SwiftUI. No ads, no tracking, no network calls of its own.

Brand-new and ad-hoc signed (not notarized) — first launch needs right-click → Open. macOS 14+.

Install: brew install --cask roypadina/tap/languard, or build from source.
Repo: https://github.com/roypadina/LanGuard
```

### dev.to / blog post (outline)
**Title:** `I built a tiny macOS app that turns off Wi-Fi when you plug in Ethernet`
**Hook (first 2 paragraphs):** the dual-homing annoyance after docking; macOS only changes
routing priority, never powers the radio off; existing tools want admin or are paid.
**Outline:** the problem → why "always off when wired" is the wrong model (manual override) →
edge-based design → CoreWLAN for power, SCDynamicStore for link state, NSWorkspace for wake →
keeping the engine testable with dependency injection → ignoring virtual NICs → install + the
notarization tradeoff → what's next. Link the repo; cross-post to Hashnode/Medium.

---

## 6. Suggested sequence

1. **Day 0:** finish pre-launch checklist (GIF + social preview + screenshots + SHA-256). Reply in the **warm threads**.
2. **Day 1 (Tue–Thu, ~9am ET):** **Show HN** + **r/macapps** (different days from r/macos). Stay in comments all day.
3. **Day 2:** **MacPowerUsers** thread + **MacRumors** forum post; submit the **awesome-list PRs**.
4. **Day 3:** **Product Hunt** (12:01am PT, account ≥2 weeks). Post **X / Mastodon / Bluesky / LinkedIn** the same morning.
5. **Week 2+:** newsletters, AlternativeTo listings, r/swift "how I built it" write-up + dev.to article.
6. **Ongoing:** at ~75★, PR the cask into **homebrew-cask** so it's `brew install --cask languard` with no tap.
