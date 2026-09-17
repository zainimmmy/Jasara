# Jasara

A native iPhone app that puts a challenge alarm, a to-do list, a visual day planner,
a focus timer and an Islamic prayer tracker in one place, with XP and streaks on top.
Built from the PRD (`Wake up, plan the day, and keep each other on time`).

SwiftUI + SwiftData + AlarmKit, iOS 26. Everything solo works offline; accounts
and friends use Supabase when it's configured.

## Running it

```bash
open Jasara.xcodeproj
```

Pick an iPhone simulator and hit run. Xcode fetches the one package
(`supabase-swift`) on first open. Without `Config/Secrets.xcconfig` the app builds
and runs normally with accounts and friends switched off — see
[Accounts and friends](#accounts-and-friends) to turn them on.

## What's built

| Area | State |
|---|---|
| Onboarding, guest mode, age check, username rules | Done |
| To do: priority sections, subtasks + progress, notes, duration, repeat, reminders, suggested tasks, emoji picker with keyword suggestions | Done |
| Calendar: week strip, month jump, Anytime/Morning/Afternoon/Evening sections, EventKit read-only events, prayers inline | Done (list view) |
| Alarms: regular + challenge, 7 tiers, 1–100 rounds, snooze caps, silent "Try it" preview, first-run explainer | Done |
| AlarmKit: rings through silent mode and Focus, snooze from the lock screen, challenge re-arms until solved | Done |
| Accounts (email + password), friends by exact username, requests, block, report, account deletion | Done, needs Supabase set up |
| Group alarms: invites, per-member challenge, cutoff lock, offline ringing, check-ins, group streak, +10 group bonus, wake photos | Done, needs Supabase set up |
| Challenges: Math, Shake (Core Motion), Typing, Colour tiles | Done, all tier-driven |
| Overstimulated mode: 4 image CAPTCHAs, joke checkboxes ×2, joke terms, 2 typed CAPTCHAs, 15s auth bar, 3 fake calls | Done |
| Emergency stop (10s hold, always works, breaks the wake streak) | Done |
| Focus timer: ring, presets, task linking, XP with daily cap | Done |
| Prayers: on-device calculation, 6 methods, Hanafi Asr, masjid offsets, Jumu'ah, nudges with caps, qada | Done |
| XP, levels to 365, streaks, milestones, anti-farming rules | Done |
| Settings, local data wipe, notification budget readout | Done |

## What isn't built yet

- **Server-side photo moderation.** Wake photos are screened on the device when
  the person has Sensitive Content Warning or Communication Safety on, are
  reportable, vanish after 24 hours and are hidden between blocked people. An
  automated server-side image check is still needed before a public App Store
  release (guideline 1.2); a friends-only TestFlight is fine without it.
- **Friend streaks** (per pair of friends in a group) and **calendar sharing**.
- **Live Activity** for group alarm status.
- **Sign in with Apple and Google.** Email and password work now. Apple's rules
  say that once Google sign-in ships, Sign in with Apple must ship with it.
- **Moderation tooling.** Reports land in the `reports` table; for now a
  moderator reviews them in the Supabase dashboard. Photo screening arrives with
  wake photos.
- **Server-verified XP.** Level is synced to your profile so friends see it, but
  it isn't re-derived on the server yet.
- **NFC and Photo challenges** (need hardware registration flows).
- **Widgets, Live Activities, Apple Watch app.**
- **StoreKit**: Pro and cosmetic packs.
- **Calendar timeline view** (the setting exists and says so).
- Task reminders set to *Alarm* ring through AlarmKit but don't take a challenge.
- The in-app alarm tone is a system sound on a repeat. A licensed clip under 30
  seconds replaces it before release.

## Alarms

Alarms are scheduled with **AlarmKit**, so they ring through silent mode and
Focus, keep working after the app is quit or the phone restarts, and appear on
the lock screen with the system's own alarm UI.

- **Regular alarm**: stopping it logs the wake and its XP, even if the app never
  opens. Snooze sits on the alarm itself until the snooze cap runs out.
- **Challenge alarm**: the system always offers a stop control, so stopping one
  opens the app straight into the challenge and arms a follow-up alarm a minute
  out. Stopping that one does the same again. Only solving the challenge — or the
  10-second emergency stop — ends it.
- AlarmKit asks for permission the first time an alarm is saved. If it's denied,
  alarms can't ring; the app still works otherwise.
- The flow lives in `Core/Scheduling/`: `AlarmKitScheduler` (scheduling),
  `AlarmIntents` (what stop and snooze do), `AlarmRuntime` (the small state they
  share with the app, since intents can run before the UI exists).

Silent mode can't be tested on the simulator, which has no ringer switch.
Check it on a real iPhone: flip the switch to silent, turn on a Focus, and run
`-JasaraFireIn 30` (below) or set an alarm two minutes out.

## Group alarms

Schema and rules: [`supabase/migrations/20260917000000_group_alarms.sql`](supabase/migrations/20260917000000_group_alarms.sql),
run after the friends migration.

- **Creating**: the creator sets a label, time, days (or a single date) and the
  cutoff, then invites friends. Only accepted friends can be invited; groups hold
  up to 20.
- **Per member**: everyone picks their own challenge, difficulty and rounds, and
  flips their own on/off toggle. Times are each member's local time.
- **Cutoff**: toggles lock at the cutoff the night before (default 9pm). A change
  after that applies from the following occurrence. Turning off after the cutoff
  means tomorrow still rings and still counts. Who was in for each morning is
  frozen at its cutoff, so history stays right however often people toggle.
- **Ringing**: each joined group becomes a normal local alarm tagged with the
  group, scheduled through AlarmKit — it rings with no signal, with the same
  challenges, snooze caps and emergency stop.
- **Waking**: finishing the alarm queues a check-in that syncs when there's a
  connection. On time means solved without the emergency stop, from 10 minutes
  before to 30 minutes after the alarm, and synced within 6 hours. The server
  judges it against its own clock and computed alarm time.
- **Group streak**: consecutive mornings where everyone who was in woke on time.
  **Group bonus**: +10 XP each on those mornings (groups of two or more).
- **Wake photos**: optional, after solving. Stored privately, visible only to
  group members for 24 hours, never between blocked people, reportable.

Signing out, or deleting the account, removes group alarms from the phone.
Nothing else does — being offline, or a slow session restore at launch, never
touches them.

## Accounts and friends

The backend is Supabase. Everything is in
[`supabase/migrations/20260916000000_friends.sql`](supabase/migrations/20260916000000_friends.sql):
tables, row level security, and the functions the app calls.

- **Reads** go through row level security: you can see your own profile, and
  people you share a request or friendship with, unless either of you blocked
  the other.
- **Writes** only go through database functions (`send_friend_request`,
  `block_user`, …), so the rules hold even against a modified app.
- **Usernames** are 3–20 characters, unique ignoring case, checked for reserved
  words and slurs on the server, changeable once every 30 days (the first change
  is free, for typos).
- **Search** is exact username only. There's no partial search to trawl people.
- **Blocking** removes the friendship and hides both people from each other's
  searches. **Reports** keep the reported username even if that account is later
  deleted.
- **Deleting your account** removes it on the server, then wipes the phone.

The migration was run against real Postgres with a Supabase-shaped `auth` schema
and 46 checks covering sign-up, requests, blocking, reports, renames and account
deletion. It has not yet been run on a live Supabase project.

Keys go in `Config/Secrets.xcconfig` (git-ignored); see
`Config/Secrets.example.xcconfig`. Only ever the **anon** key — never the
`service_role` key, which bypasses every rule above.

## How it's laid out

```
Core/
  Design/      colours (light + dark per token), type scale, shared components, emoji catalogue
  Model/       SwiftData models and the persisted enums
  Store/       AppStore — owns the singletons and every write that touches XP
  Progress/    the level curve and the XP rules table
  Scheduling/  AlarmKit scheduler and intents, notification budget, notification routing
  Prayer/      on-device prayer time astronomy, location, settings resolution
  Social/      the Supabase client: accounts, friends, block, report
Features/      one folder per tab, plus onboarding, profile, settings, social, overstimulated
Config/        Base.xcconfig, the optional git-ignored Secrets.xcconfig, extra Info.plist keys
supabase/      database migrations
```

A few decisions worth knowing:

- **`AppStore` owns progress.** Views read models with `@Query` but come to the
  store to *change* anything that awards XP, so the rules can't drift per screen.
- **Colours are stored by name** (`"mint"`), never as hex, so a task saved in
  light mode reads correctly in dark mode.
- **Prayer times are calculated on device** in `PrayerTimeCalculator`, so they
  work offline and the location never leaves the phone. Swapping in the Adhan
  Swift package later only needs `times(on:...)` to keep its signature.
- **Notification budget.** iOS keeps 64 pending local notifications. Everything
  is scheduled about a day ahead, prayer nudges are capped at 6, and the whole
  set is topped up whenever the app comes forward.
- **Anti-farming is deliberate**: subtasks earn nothing, a task created and
  ticked within two minutes earns nothing, priority doesn't change task XP, and
  rounds never change challenge XP.

## TestFlight

Ready for a beta upload: app icon, privacy manifest (`Jasara/PrivacyInfo.xcprivacy`),
export compliance set (`ITSAppUsesNonExemptEncryption = NO`), background refresh
registered, and entitlements in `Config/Jasara.entitlements` (time-sensitive
notifications, on-device photo screening). The Release build compiles for
devices with no warnings.

Before each upload, bump **Build** (`CURRENT_PROJECT_VERSION`) in the target's
General tab. External testers need Beta App Review, which will want a demo
account: create two accounts that are friends and share a group alarm, and put
the login in the Test Information section.

## Before it goes anywhere near App Review

The PRD's compliance checklist still applies in full. The parts already honoured
in code: guest mode with no forced login, permissions asked at first use with a
reason, the emergency stop, no silent audio loop, no volume or silent-switch
overrides, the joke-terms banner, the clearly labelled fake call that avoids
CallKit and the iOS call screen, and no third-party CAPTCHA branding.

## Debug launch flags

`DEBUG` builds only, stripped from release by `#if DEBUG`:

| Flag | Effect |
|---|---|
| `-JasaraDemo` | Seeds a believable day: seven tasks with subtasks, three alarms, prayers on, a 12-day streak and level 10. Only fills an empty store. |
| `-JasaraTab todo\|calendar\|alarm\|timer` | Lands on that tab. |
| `-JasaraRing math\|shake\|typing\|tiles\|overstimulated` | Opens the alarm ring screen straight into that challenge, instead of waiting for 6:30am. |
| `-JasaraToast` | Shows the "Alarm set for … from now" note for the first alarm, a couple of seconds after launch. |
| `-JasaraFireIn <seconds>` | Asks AlarmKit to ring the first challenge alarm that many seconds from now — a real system alarm, with its snooze and stop intents. |

```bash
xcrun simctl launch booted com.Zoon.Jasara -JasaraDemo -JasaraRing overstimulated
```

The same seed is what App Review's demo notes will want.

## Verified

- Whole module compiles clean: no errors, no warnings, iOS 26 simulator SDK.
- AlarmKit permission prompt appears with the app's usage string, and the three
  alarm intents are registered in the app's App Intents metadata.
- Supabase migrations: 103/103 checks against real Postgres with Supabase-shaped
  `auth` and `storage` schemas — 46 for friends, 57 for group alarms (cutoff
  locking, check-ins, streaks, photo storage policies, ownership handover,
  account deletion).
- All four tabs, onboarding, the alarm ring screen, the math and colour-tile
  challenges and the Overstimulated gauntlet render and run on an iPhone 17 Pro
  simulator.
- Prayer maths checked against published timetables (London 2026-09-16: Dhuhr
  12:55, Maghrib 19:12, Asr 16:21 standard / 17:12 Hanafi; Makkah 12:15 / 18:22;
  Karachi 12:26 / 18:35).
