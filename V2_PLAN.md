# Perch 0.2: design direction

## The idea
Perch is a small black object that lives behind a lime camera cover. When it is quiet it stays out of the
way. When something happens it shows it in two small wings beside the cover. When you reach for it, it
opens into a dense, calm control deck. It should feel like something a person sanded by hand: Alcove's
polish, NotchNook's range, and none of the clutter.

## Rules for the look
- Ink black body, soft white type in three weights of grey, one accent. The accent is either the lime of
  the cover or a color taken from the album art. Two more themes: Graphite and Paper (a warm light one).
- New York serif only for things you wrote (notes, tasks) and for empty states. SF for everything else,
  with tabular numbers for clocks and countdowns.
- Nothing at rest moves on its own. Wings are still. Motion only answers you or tells you something
  changed: springs when it opens, a bloom when a job finishes, a fill when you plug in.
- Real data only. Where something cannot be done without Apple's paid developer program (Focus mode,
  real audio-reactive bars) Perch says so instead of faking it.
- Every permission is asked for once, by you pressing a button, with one plain sentence about why.

## Resting wings (glanceable, priority order)
Camera or microphone in use > running timer > next event within 10 minutes > agents working >
music playing > charging. Left wing: the icon or album art. Right wing: the value (12:04, in 8m, dots, %).

## Moments (the island widens for a few seconds)
Agent finished or failed (bloom + chime), timer done, volume and brightness HUD, charger connected
(battery fills), headphones connected, camera turned on, new mail, event starting.

## The open deck (tabs you can hide)
- Today: music, up next on your calendar, timer, weather, agents, homework due, unread mail.
- Music: big art over a blurred art backdrop, scrub bar, shuffle and repeat, volume, synced lyrics
  (LRCLIB), player picker when Spotify and Music are both open, art-tinted visualizer (not audio-reactive).
- Notes: quick notes with light markdown and checklists, pinned note, tasks and a homework tracker by class.
- Agents: every Grok Bot as an avatar with its own color, live elapsed time, task line, bloom on finish,
  and a local history of finished jobs.
- Shelf: drop files on the island to keep them handy, drag them back out, AirDrop or reveal them.
  Clipboard history (skips passwords and anything marked private).
- Mail: Gmail through your own Google OAuth client (loopback sign-in, tokens in the Keychain), unread
  count, the top threads, archive and mark read.
- Launch: pinned apps and your Shortcuts, one click each.

## Customization
Theme, accent, which tabs show, which Today cards show, hover delay, a global shortcut to open (no
permission needed), trackpad swipe down on the island to open, chime, wings, weather city and units.

## Kept from 0.1
Stable signing, Sparkle updates, the curl installer to ~/Applications, launch-safe move prompt,
hover hysteresis, fixed window frame, helper cleanup.
