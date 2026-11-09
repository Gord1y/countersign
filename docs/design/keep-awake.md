# Keep Mac awake

Keep Mac awake stops the Mac from idle-sleeping while agents work. It is opt-in, lives in the
menu-bar app, and installs nothing.

## Why the hold lives in the menu-bar app

The menu-bar app is the one long-lived process Countersign already runs. A power assertion belongs
to the process that created it and ends with it, so the app is the right owner: quitting the app
releases the hold, and no helper, daemon or launch agent has to be installed, kept in sync or
removed. Every other starter (the Settings switch, the menu, the `countersign keep-awake` command)
asks the app to hold; none holds by itself.

## What the assertion does

Measured on macOS with `pmset -g assertions`:

- `PreventUserIdleSystemSleep` is raised while the hold is active.
- `PreventUserIdleDisplaySleep` stays 0, so the display still turns off after its own timeout and
  the screen locks as configured. The hold keeps the Mac running, not the screen lit.
- After the holding process is killed with SIGKILL, macOS releases the assertion. A crash cannot
  leave the Mac awake.

Lid-closed sleep is out of scope: closing the lid sleeps a laptop regardless of this assertion, and
Countersign does not try to override that.

## Why nothing is installed

Nothing is written outside Countersign's own support folder and `config.json`: no login item beyond
the existing one, no `caffeinate` process, no `pmset` change, no privileged helper. Turning the
feature off, or removing the app, leaves nothing to clean up.

## Why every launch starts off

A hold is a decision made for one stretch of work. After a restart, a crash or a relaunch, the user
has not made that decision again, so the app clears the session file at launch and starts with no
hold. The opt-in (`keepAwake`) is separate and persists: it only decides whether the menu offers
the item.

## The session file

`keep-awake-session` in the support folder is the one channel every starter writes and the app
reads. It holds whole epoch seconds for a timed hold, or the word `forever`. It is written to a
temporary file in the same folder and renamed into place, like `quiet-until`, so a reader never
sees half a write. The reader treats a missing, unreadable or malformed file, and a date that is not
after now, as no session.

## The policy

`KeepAwakePolicy.state` turns four inputs into one state:

| Opted in | Session | Power | State |
| --- | --- | --- | --- |
| no | any | any | not running |
| yes | none | any | not running |
| yes | set | plugged in | holding |
| yes | set | no battery | holding |
| yes | set | battery above the cutoff | holding |
| yes | set | battery at or below the cutoff | released at cutoff |

The cutoff applies on battery power only. At or below it the hold is released and resumes when the
Mac is plugged in; on power it holds at any charge. A Mac with no battery holds. A charge that
cannot be read (an unknown power state, a missing capacity or a maximum capacity of zero) counts
as no battery; a capacity of 0 is a real reading, 0%, and an over-full reading is clamped to 100%.
So a broken reading never stops a hold that the user asked for.

## The tick

`KeepAwakeController.tick` runs on every `refreshIcon()` of the menu-bar app: the 2-second timer,
each menu opening and after every menu action. It is the only place that creates or releases the
power assertion; the menu and the session file only change what the next tick sees.

1. It reads the session file. With no session it releases any assertion, removes a leftover file
   only when an assertion was held or an earlier tick saw a session, logs the end once, and returns
   `not running`. This path loads no config: the idle tick, which is nearly every tick, stays a
   single small file read.
2. With a session it loads the config for `keepAwake` and `keepAwakeBatteryCutoff`. Switched off in
   Settings clears the session, releases the hold and logs `keep awake ended, switched off in
   Settings`.
3. `KeepAwakePolicy.state` decides from the opt-in, the session, the power source and the cutoff.
   `holding` creates the assertion if none is held; any other state releases it.
4. It logs only a change of state: `holding until 22:34`, `holding until turned off`, `released at
   15% battery`, `ended`.
5. A failed `IOPMAssertionCreateWithName` is logged once per streak of failures, with its
   `IOReturn` code, and retried on the next tick. The tick still returns the policy's state, so the
   menu keeps showing what the user asked for.

Starting and stopping from the menu only write or clear the session file, and `menuItemChosen`
refreshes the icon right after, so the hold follows within the same run-loop turn. Quitting clears
the session and releases the hold.

### A config that cannot be read keeps a hold

`KeepAwakeConfigRead.current` reads only `keepAwake` and `keepAwakeBatteryCutoff`, and tells an
unusable `config.json` (unreadable, not valid JSON, or not an object) apart from a usable one. An
unusable file keeps a running hold, applying the last cutoff the tick saw (the default before any),
because a typo is not the user switching it off; the log says `keep awake kept running, config.json
has a problem`, once per streak, and the menu keeps **Stop Keeping Awake** reachable. An absent file
or `{}` is usable and opted out, so it ends the hold, which is how Restore Defaults works.

### A released hold still blocks a relaunch

Releasing at the cutoff keeps the session file, because the hold resumes when the Mac is plugged
in. So the copy refresh, which relaunches the app and would end the session at the next launch,
waits for as long as the file exists, released or not. The window between the relaunch guard and
the termination is narrow and accepted: a hold started inside it ends with the old process, the
same way [app.md](app.md) accepts a menu opened in that gap.

### The dot

The icon gets a small dot in its top-left corner, drawn in the template colour, only while the hold
is actually in force (`KeepAwakeState.holdsIdleSleep`). A hold released at the cutoff shows no dot,
because the Mac is no longer being kept awake; the menu says why. The dot sits where neither the
pause bars nor the moon do, so it combines with every icon state, and the icon's spoken label gains
`, keeping this Mac awake`.

## Limits

The cutoff is a whole number from 5 to 95 in steps of 5, default 15. Durations are 1, 4, 8 or 12
hours, or until turned off, default 12 hours.
