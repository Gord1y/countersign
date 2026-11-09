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

The cutoff is a whole number from 5 to 95 in steps of 5, default 15. Durations are 1, 4, 8 or 12
hours, or until turned off, default 12 hours.
