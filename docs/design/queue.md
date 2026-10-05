# Display queue

This note explains how waiting hooks share the screen: only one approval panel may be on screen at
a time, waiting hooks get it in arrival order, and after an answer the next one shows at once.
`TicketQueue` does this with no coordinator process, using files and one kernel lock. Read it when
you change how a hook waits for, shows or hands over the panel, or when a queue gets stuck, two
panels appear or the next panel is slow.

## Why head plus flock: a panel needs both the first ticket and the lock

Every waiting hook writes a ticket named `<realtime ns, 20 digits>-<pid>.json`. Sorting the live
tickets by (timestamp, pid) gives FIFO order, and any process can compute it from a directory
listing. On macOS `CLOCK_REALTIME` ticks in microseconds, so two hooks can get equal timestamps,
and the pid then breaks the tie. The sort compares numbers, not file names. The one exception is
a request moved with **Show Now** from the menu bar, whose ticket carries its new place (see
"Answering from the menu bar" below).

A listing is a snapshot, not a lock. Two processes can act on listings taken at different
moments, and a clock step can reorder new tickets. So mutual exclusion comes from somewhere
else: `flock(LOCK_EX|LOCK_NB)` on `display.lock`. The kernel grants it to one open file
description at a time and drops it when the holder's last descriptor closes, including when the
process is killed. A process shows its panel only when its ticket is the head **and** it holds
the lock, and it keeps the lock for the panel's whole lifetime. The head check alone cannot
guarantee a single panel. The lock alone gives no order, since whoever polls first would win.

## Liveness and pid reuse

Each listing prunes the tickets of dead processes, so a crashed hook never wedges the queue.
`kill(pid, 0)` alone is not enough, because pids are recycled. A ticket left by a crashed hook
could name a pid that now belongs to an unrelated long-lived process, and that ticket would sit
at the head forever. Each ticket therefore records its process start time
(`kp_proc.p_starttime`, in microseconds since the epoch). A ticket is live when the pid exists
(`EPERM` counts, since it means the process exists under another user) and, when both values are
known, the start times match.

Tickets are written atomically (a dotfile temp in the same directory, then `rename`), so readers
only ever see complete content. Content that is still unreadable means outside damage, and
liveness then falls back to `kill` alone.

A zombie does not count as live, even though `kill(pid, 0)` succeeds until the parent reaps it.
`ProcessLiveness` reads `kp_proc.p_stat` from the same `sysctl(KERN_PROC_PID)` call that gives
the start time, and treats `SZOMB` as dead outright, before comparing start times at all. So a
zombie ticket is pruned even when its recorded `processStart` still matches: the kernel has
already dropped a zombie's lock, so there is nothing to wait for, and waiting for the host to
reap it would only wedge the queue for longer than necessary.

## Why the lock file is never deleted

`flock` locks the inode, not the path. If anything unlinked `display.lock` while a panel held it,
the next process would create a new inode at the same path, lock it, and show a second panel.
No code path deletes it. Pruning only touches names that parse as tickets, and the lock file is
opened with `O_CREAT` and left in place.

The open-and-lock itself lives in `ExclusiveFileLock`: create the parent directory if needed, open
with `O_RDWR | O_CREAT | O_CLOEXEC`, then `flock(LOCK_EX|LOCK_NB)`, returning nil when another open
file description holds the lock and throwing only when the file cannot be opened at all. After the
`flock` it checks that the path still names the file it opened (same device and inode) and returns
nil when it doesn't: a process that opened a lock file just before someone else deleted it would
otherwise hold a lock on a file nobody else can see, while the next one locks a new file at the same
path. `display.lock` is never deleted, so the check always passes there; it is what makes deleting
the context checkpoints' session locks safe (see [checkpoints.md](checkpoints.md)).
`DisplayLease` wraps one and turns every failure into "no lease". The menu-bar companion holds a
second one on `companion.lock` to stay a single instance (see "Launch and single instance" in
[app.md](app.md)); that file is never deleted either, for the same reason.

## O_CLOEXEC

A lock belongs to the open file description, which every copy of the descriptor shares. Without
`O_CLOEXEC`, a child spawned while a panel is up would inherit the lock and hold it after the
hook exits or crashes, blocking every later prompt until that child exits.

## Removal order: the ticket before the lock

When a panel ends, the process removes its ticket first and releases the lease second. So
whenever the lock is free, the head ticket belongs to a process that is still trying to take it,
never to one that has already finished. A crash between the two steps is harmless: the kernel
drops the lock and the dead ticket is pruned.

## What a listing ignores and repairs

- Dotfiles (including in-flight temp files), names not ending in `.json`, `display.lock`, and
  `.json` names that do not parse as `<20 digits>-<pid>` are ignored and never deleted. The one
  other name a listing deletes is a menu answer, `<20 digits>-<pid>.answer`, once its ticket is
  gone (see "Answering from the menu bar" below).
- Pruning ignores `ENOENT`, since two processes can prune the same ticket.
- If a process's own ticket has vanished, `acquireDisplayIfHead` rewrites it under the same name,
  so the process keeps its place. It never rewrites another process's ticket.

## Termination signals

`removeOnTermination` sets SIGTERM, SIGINT and SIGHUP to `SIG_IGN` and watches them with
`DispatchSourceSignal` sources on a dedicated serial queue. kqueue still reports ignored signals.
The handler runs as ordinary code: it unlinks the ticket and calls `_exit(0)`, leaving stdout
empty, which the hook contract reads as no decision. It calls `_exit` rather than `exit` because
this handler can run while AppKit's main thread is mid-teardown elsewhere in the process; `exit`
would run atexit handlers and Foundation/AppKit cleanup concurrently with that teardown, and a
crash on the way out is a risk this process never needs to take, since the hook never writes to
stdout on a signal anyway. If the process holds the lease, the kernel releases it at exit, which
keeps the removal order. Known limits:

- A signal that arrives between `SIG_IGN` and the source's kqueue registration is dropped.
- Ignored dispositions are inherited across `exec` by any child process.

## Listing waiters, not just counting them

A count (`waitingCount(excluding:)`) is not enough for the header's waiting chip: showing the actual
list of waiting requests needs one entry per live ticket, so `waitingEntries(excluding:)` sits next
to it: same `liveTickets()` snapshot, same exclusion of the caller's own ticket, same
oldest-first order, but it returns a `WaitingEntry` for each live ticket instead of a count.
`WaitingEntry` wraps an optional `TicketSummary` rather than the summary itself, because a live
ticket's content can fail to decode (dead process, torn write, a foreign file) without the ticket
itself being any less real — the person still has a hook waiting, even if this process cannot say
what for. Dropping that ticket from the list would make the list's count disagree with the chip's
own count (which comes from the same array, `waitingEntries(excluding:).count`, not a separate
tally), so an unreadable ticket becomes a `WaitingEntry(summary: nil)` instead of being skipped;
the row it renders as is `WaitingListView`'s concern, not the queue's (see "The waiting list" in
[panel.md](panel.md)).

`waitingEntries()`, with no ticket to exclude, returns an entry for every live ticket in the same
order. It exists for the menu-bar companion's "N requests pending" submenu (see "Menu-bar
companion" in [app.md](app.md)): the companion holds no ticket of its own, so there is nothing to
leave out. Like every listing it prunes the tickets of dead processes on the way; it never writes
a ticket and never touches `display.lock`. Both listings fill `WaitingEntry.ticketID` with the
ticket's id, its file name without `.json` (`Ticket.id`), which is how a menu answer finds its
hook. "Oldest first" is the queue order, so a request moved with Show Now is listed in its new
place.

`TicketSummary`'s fourth field, `agentDescription`, is filled at enqueue time in `HookRunner` from
the requesting agent's own subagent chain (see "Walking the subagent chain" in
[hosts.md](hosts.md)) — the last crumb's task description, or nil when the request is not a
subagent or the chain does not resolve. It is declared optional and given a default of `nil` in
both initializers specifically so a ticket without that key, such as one written by another build
of Countersign, still decodes: `Codable`'s synthesized `init(from:)` treats a missing key on an
`Optional` property as `nil` rather than a decoding failure, the same tolerance every other host
file in this project depends on.

## Warm standby and the queue handoff

After an Approve, a Deny or an answer in chat, the next queued request shows right away, with no
idle wait and no break in the dimmed backdrop. Two processes have to cooperate for that: the head,
which exits to deliver its decision, and the next hook in line, which without warm standby would
start AppKit only once its 250 ms poll had won the lease.

**Who is next in line.** `QueuePlace(of:among:)` places a ticket in the sorted live listing: the
head, next in line (index 1), behind, or absent. Tickets are written only after the grace period,
so every live ticket is already past it. `TicketQueue.waitForTurn` replaces the plain lease wait
in the hook: it returns the lease if the ticket is the head and the lock is free, returns
`.nextInLine` as soon as the ticket is second, and otherwise polls every 250 ms. Only the next in
line warms up; the others just poll. When the head leaves, the ticket
behind the new head sees itself second on its next poll and warms up in turn. A warm hook stays
warm even if an older ticket reappears ahead of it (a head restoring its vanished ticket), which
costs nothing but an idle AppKit process.

**Warm standby.** The next in line builds `PanelApplication` and runs it, `.accessory` with no
windows, launched the same way as a head (see "Never activating" in [panel.md](panel.md); an
accessory app with no windows never activated in the probes). Once launch has finished it listens
for a handoff, prepares its panel (see "Preparing the next panel" below) and keeps trying the
lease on the 250 ms tick.

**The signal.** Darwin notifications (`notify(3)`, part of libSystem) carry the handoff.
`QueueHandoffChannel` names four per ticket, each ending in `<ticket>`, the ticket's file name
without `.json`, so a signal can only ever reach, and a state can only ever describe, the process
that owns that ticket:

- `Countersign.handoff.<ticket>`: the head sets the notification's 64-bit state to the display ID
  of the screen its backdrop covers, then posts.
- `Countersign.ready.<ticket>`: the next in line posts it once its backdrop is up.
- `Countersign.preparing.<ticket>`: the next in line sets its state to 1 while it builds a panel
  and back to 0 after (`QueueHandoffPreparation`).
- `Countersign.display.<ticket>`: a process showing a panel sets its state to that panel's display
  ID, and back to 0 when the panel closes, steps aside or is snoozed (`QueueShownDisplay`).

A notification that nobody is registered for is simply lost; nothing is stored for a later reader.
A state is different: notifyd keeps a name's state for as long as some process holds a
registration for that name, and drops it when the last one is cancelled, which includes the
holder dying. The publishing process keeps its registration for as long as the state means
something. A reader registers, reads and cancels (`isPreparing()`, `shownDisplayID()`), so reading
never needs the publisher's main thread, and a process that dies while preparing or showing reads
as neither. Its ticket is pruned anyway, and a ticket name is never reused.

**The head, on Approve, Deny or answer in chat** (Esc and a click on the backdrop included):

1. Writes the decision to stdout, so a kill during the rest cannot lose it, and logs the outcome.
2. Leaves its panel and its backdrop on screen, but the panel no longer responds: the model has
   finished, so neither a key nor a click can act on it again, its key monitor and step-aside
   triggers are removed, and the main thread stays blocked in the wait below until the process
   exits, so no event is even dispatched.
3. If a live ticket follows its own, registers for that ticket's ready notification, sets the
   state and posts the handoff, then waits for ready. The cap comes from
   `QueueHandoff.readyTimeout(successorPreparing:)`: 150 ms (`readyTimeout`), or 600 ms
   (`preparingReadyTimeout`, the measured 60 to 430 ms of a build and first layout plus margin)
   when the next in line is preparing a panel. The head reads the preparing state right after
   posting, and once more if 150 ms pass without a reply, so a successor that started preparing a
   moment after the post still gets the longer cap. It logs `queue handoff: next in line still
   preparing` when the longer cap applied, then `queue handoff: ready in N ms` or
   `queue handoff: no reply`.
4. Orders out its panel and its backdrop, removes its ticket, releases the lease (keeping the
   removal order above) and exits. With no reply it does the same once the cap has passed,
   and with no live ticket after its own it does it at once. Neither window animates on the way
   out (see "Centered on the mouse's display, over a blurred backdrop" in [panel.md](panel.md)).

**Preparing the next panel.** As soon as a process is next in line and AppKit has launched, right
after it starts listening, it prepares its panel: it creates a `BackdropWindow` for the target
screen without showing it, builds its `PanelController` exactly as a handoff does (that backdrop,
`afterHandoff: true`, so `chainedArmDelay`) and lays it out once. Nothing is ordered front, nothing
becomes key, the app is never activated and focus does not move. It sets the preparing state for
the duration and logs `next in line: panel prepared in N ms`. The target screen is the one the
head's panel is on, read from the `Countersign.display` state of the ticket ahead of its own
(`TicketQueue.ticketAhead(of:)`), or `PanelController.resolveTargetScreen()`, the mouse's screen,
when the head has published none (it is still waiting for idle, or has stepped aside) or its
display is not a current screen. The prepared panel records its display ID and a snapshot of every
screen's display ID, frame, visible frame and backing scale.

Building the SwiftUI hosting view and its first layout passes is the slow part of showing a panel
(see "Limits"); prepared here, it happens while nobody is waiting for it. The cost is one extra
SwiftUI tree, never on screen, in the one process that is next in line. Processes further back
never start AppKit, so the queue holds at most one prepared panel. A controller can sit prepared
for minutes because its init and `layOut()` start nothing: the arm timer, the progress line,
`isArmed`, the key monitor, the step-aside observers and `makeKey` all wait for `show()`, `finish`
and `snooze` need `isArmed`, and neither Esc nor a click reaches a panel or a backdrop that is not
on screen. What it does read at build time is the file an edit, a write or a patch touches (see
"The file on disk is the before-state" in [panel.md](panel.md)), the subagent chain and the
chat-tracking health. The chain and the health do not change for a request; the file can, so it is
read again at the handoff.

While it waits, and while no handoff is pending, a prepared panel follows the screens and the head:

- On `NSApplication.didChangeScreenParametersNotification` it is discarded
  (`prepared panel discarded: screens changed`) and prepared again at once.
- On the 250 ms tick, when the head has published a display that is a current screen and is not
  the prepared one, it is discarded (`prepared panel discarded: display changed`) and prepared
  again for the head's display. This covers a head shown on another display than the mouse's at
  prepare time, and a head that comes back on another display after a step-aside.

Every prepare, these included, sets the preparing state while it runs. Nothing is prepared when the
target screen has no display ID, and nothing is prepared again after a stale handoff. Leaving the
queued state any way other than a reused handoff discards the prepared panel: winning the lease
with no handoff (`prepared panel discarded: no handoff`, then the ordinary idle path, with a fresh
controller, the 0.15 s fade and `armDelay`) and a request resolved or paused while queued
(`prepared panel discarded: resolved`, before `resolved while queued: <reason>`). The screen
observer and the preparing registration end when the lease comes.

**The next in line, on a handoff:** it records the moment (`systemUptime`) and resolves the
display: the handoff's display ID when it is a current screen, else `resolveTargetScreen()`.
`PreparedPanelReuse.decide` then picks the prepared panel or a new one, checking in this order:

1. No prepared panel: rebuild, `not prepared`.
2. The screen snapshot differs from the current screens: rebuild, `screens changed`.
3. The prepared display is not the resolved one: rebuild, `display changed`.
4. `FileDiffBuilder.load(for:)`, run again now, differs from what the prepared panel was built
   with: rebuild, `file changed`. The read happens only once the first three checks pass, and
   before the backdrop goes up and ready is posted, so the head's panel still covers it. It sets
   the preparing state while it runs, so a slow read gets the longer cap too. A request with no
   file context gets `nil` without touching the disk both times, so for it this check costs
   nothing.
5. Otherwise: reuse.

To reuse, it orders the prepared backdrop front at full opacity with no fade, draws it and flushes
the Core Animation transaction, then posts ready, and logs `queue handoff received` and
`queue handoff: prepared panel reused`. To rebuild, it closes the prepared panel's windows, which
were never on screen, orders a new `BackdropWindow` front on the resolved display the same way,
posts ready, logs `queue handoff received` and `queue handoff: prepared panel rebuilt (<reason>)`,
and only then
builds its `PanelController` with that backdrop and lays it out without showing it. Either way the
head removes its own panel and backdrop only after this backdrop is up, and the panel is ready to
order front the moment the lease comes. Nothing about arming starts here: the arm timer, the
progress line and `isArmed` all wait for `show()`. It then tries the lease at once, since the head
has usually exited by then, and every 10 ms after.
When it wins the lease while the handoff is still fresh (`QueueHandoff.freshness`, 1 s after it
arrived) and quiet time is off, it checks the abandon rules once more, then whether the asking app
is in front and on `handoffApps` (see "Handing off to the asking app" in [panel.md](panel.md)),
updates the prebuilt panel's waiting list (the head's ticket is gone by then) and shows it at full
opacity with no fade, logging `displayed after queue handoff in N ms`, where N runs from the
handoff arriving to the panel being ordered front. The arm lock runs from zero, for
`chainedArmDelay` (0.1 s by default) rather than `armDelay` (see "The arm lock" in
[panel.md](panel.md)). If the handoff goes stale,
quiet time is on when the lease comes, the request is resolved or paused first, or it is handed
off to the asking app, the prebuilt controller is closed without ever being shown.

**Why no fade between chained panels.** A next panel built only after the lease and faded in over
0.15 s, behind a head that hides its panel the moment it is answered, flickers between two panels
that should read as one replacing the other: the answered panel vanishes, a backdrop with no panel
stays up for the ready wait, the lease poll and the controller build, and then comes a 150 ms fade.
So the answered panel stays until the next process has its backdrop up, the next panel is usually
built before the answer and at worst right after the ready, and it appears in one frame at full
opacity. What is left between the two panels is the lease, plus the build and first layout when
the prepared panel cannot be reused (see "Limits"). Without a prepared panel the build is nearly
all of that gap, and during it key focus goes back to the person's app, so someone with nothing
else to approve could start typing there before the next panel arrives.

**What never chains.** A head only signals from the three answers above, given in the panel or,
for Deny and answer in chat, from the menu bar. A step-aside, a snooze,
quiet time, a request handed off to the asking app and a request resolved elsewhere or paused all
leave the head without signalling, so the next request waits for the idle gate as usual. The
hand-off is decided only when a panel would appear, so a request from an app on `handoffApps`
takes its place in the queue like any other and holds the lease until then. A handoff lives only in the memory of the
process that received it: it is cleared when that process wins the lease, whichever way it goes,
and dropped (the prebuilt panel and its backdrop closed, `queue handoff: stale` logged) if the
lease has not come within the freshness window. A request received while not queued, or while one
is already pending, is ignored. A panel shown after a step-aside or snooze therefore always goes
through the idle gate, and so does anything after a stale handoff.

**Limits.** The listener starts once AppKit has finished launching. A head that finishes before
that, which needs the next hook to have been enqueued within that launch time of the answer, gets
no reply, waits the full 150 ms and exits; the next request then takes the idle path. When the
ready does come, the two backdrops can both be on screen for up to one frame between this one's
first frame and the head's `orderOut`, and a frame with both is darker than one. The head orders
its panel out as soon as ready arrives. With a reused prepared panel, the backdrop then shows with
no panel only until the next process holds the lease: the head exits right after ready, and the
lease comes on the first try or one 10 ms poll later. With a rebuilt panel it also shows with no
panel for the build and first layout. `displayed after
queue handoff in N ms` bounds that gap from above. Measured offscreen with a release build over
nine fixtures, building a `PanelController` took 43 to 183 ms and its first `layOut()` 18 to
250 ms, the first build in a process being among the slowest; most of it is SwiftUI laying out
the view, in `contentViewController` and in `layOut()`. `next in line: panel prepared in N ms`
logs the same cost where it delays nothing. A chained panel also has no fade to hide
its first layout passes behind (see "The window follows the measured content, not `fittingSize`"
in [panel.md](panel.md)).

The longer ready cap has a price, paid only when the head is answered while its successor
prepares: right after the successor became next in line, after a screen change, right after the
head itself appeared on another display than the one prepared for, or while the file is read again
at the handoff. A prepare holds the successor's main thread, where the handoff is answered, so the
head waits for the rest of it instead of giving up at 150 ms. Its answered panel stays up and inert
meanwhile, and since the host reads the decision when the hook exits, the host's tool run waits up
to that long too, 600 ms at most. Past the cap the head gives up, as it does at the 150 ms cap,
and the next request takes the idle path. A successor that is not preparing gets the 150 ms cap.

Measured with `ticket-probe` over 20 rounds: the handoff request to the ready signal took 80 to
159 µs, and the head starting to finish to the next process holding the lease took 1.5 to 8.3 ms,
most of it the probe's 5 ms lease poll. The window work on screen, AppKit's launch time, the frame
timing and the time a prepared panel saves on screen have not been measured, since builders never
put a window on screen.

## Answering from the menu bar

Each row of the companion's "N requests pending" submenu opens a submenu of its own: "Show Now",
"Deny" and "Answer in Chat", or "Show Now" alone for a context checkpoint and for a ticket whose
content cannot be read (`MenuAnswer.offered(for:)`). There is no Approve. A menu row shows the
host, project, tool and agent, never the command, the diff or the question, and an approval is
the one answer that lets something run, so it is given only where the whole request is on screen.
Deny blocks the call, and Answer in Chat hands it to the agent's own prompt, as Esc does in the
panel. A checkpoint's choices are about the session and need the panel's explanation, so it gets
Show Now only; an unreadable ticket gets Show Now only because the menu cannot tell whether it is
a checkpoint.

**The answer file.** The companion never talks to a hook directly; it leaves a file next to the
ticket, the same file-signal pattern as the pause switch. A ticket's id is its file name without
`.json` (`Ticket.id`), and `WaitingEntry.ticketID` carries it to the menu. Choosing an action
writes `queue/<id>.answer` (`TicketQueue.sendMenuAnswer`) holding `show`, `deny` or `chat` and a
newline, atomically like a ticket (a dotfile temp in the same directory, then `rename`), and only
while `<id>.json` exists; an answer for a request that has already gone writes nothing and logs
`companion: request <id> was already gone`. A second choice before the hook reads the first
replaces it. The hook that owns the ticket checks for the file in the 250 ms polls it already
runs wherever it has a ticket: each `waitForTurn` poll, and each `DisplayWatch` tick while queued,
waiting for idle or shown (`takeMenuAnswer`). It reads the file and deletes it, so an answer acts
once. Content that is not exactly one of the three words (surrounding whitespace aside) is deleted
and ignored, and so is an answer the request is not offered, logged
`answered from the menu: <answer>, not offered for this request`. Before `enqueue` there is
nothing to answer: the grace period and a checkpoint's wait for approvals run before the ticket
exists, and the menu lists only tickets. The abandon checks run first on every poll, so a request
resolved in the chat, paused or due for its timeout hand-back in the same tick ends that way.

**Deny and Answer in Chat** finish the request exactly as the panel's buttons do. `deny` is
`ApprovalOutcome.deny(reason: "", interrupt: false)`, so the agent gets `"Denied in the approval
panel."` and never Deny & stop; `chat` is `.noDecision`. The hook logs
`answered from the menu: deny` (or `chat`), then the usual `outcome: …` line, records the decision
in the history as the panel would (`DecisionAnswer.answer(for:checkpointChoice:isCheckpoint:)`),
removes its ticket and exits. A panel on screen hands off to the next in line first, like any
answer, then closes; its main thread is blocked in the ready wait meanwhile, so no key or click
reaches it, as with a timeout hand-back. A request still queued or waiting for idle never shows.

**Show Now** moves the request to the front, but never ahead of a panel already on screen:

- The hook reads the other tickets' `Countersign.display` state, the check the test panel uses
  (`TicketQueue.showNow(_:isOnScreen:)`). If one of them has a panel on screen, the request goes
  right behind it and becomes next in line (`show now: next after the panel on screen`), and
  chains through warm standby when that panel is answered. Otherwise it goes to the very front
  (`show now: moved to the front`) and skips the idle gate the next time it would wait for it.
  Quiet time does not hold it, at either place: the person asked to see it (see "Asking for a
  panel beats quiet time" in [panel.md](panel.md#quiet-time)). A request already on screen ignores `show`
  (`answered from the menu: show, already on screen`).
- The new place is stored in the ticket, `TicketContent.menuPosition`, which the owning process
  rewrites atomically as ever, so every process computes the same order from a listing. A place
  (`Ticket.position`, a `QueuePosition`) is a list of numbers compared element by element:
  `[timestamp, pid]` in arrival order, `[0, max − t]` at the front, and the on-screen ticket's
  place followed by `max − t` right behind it, where `t` is the realtime nanoseconds of the Show
  Now. The listing sorts by place, then timestamp and pid. So the newest Show Now wins, at the
  front and right behind a panel on screen alike. A ticket without the key, such as one written by
  another build, keeps its arrival place.
- A process that holds the lease while waiting for idle has no panel on screen, and must not keep
  a request shown from the menu waiting. On each tick in that state it checks
  `isOvertakenFromMenu`: the head of the listing is another ticket with a menu place. If so it
  releases the lease, keeps its ticket, goes back to queued with warm standby, and logs
  `gave way to a request shown from the menu`. Only a menu place triggers this, so an older
  ticket that reappears ahead (see "What a listing ignores and repairs") still takes no lease
  away. The removal-order invariant still holds: the lock is free only while the head, the ticket
  shown from the menu, is trying to take it.
- Skipping the idle gate happens once: it ends when the panel is displayed, so after a step-aside
  or a snooze the request goes through the gate like any panel. `Show` on the approval card sets
  the same skip for the request holding the lease (see "The approval card" in
  [panel.md](panel.md)), and giving way to a request shown from the menu closes that card. A request placed behind a panel on
  screen never skips it: when that panel steps aside instead of being answered, the request waits
  for the gate, as "What never chains" above describes.

**Clean-up.** `remove(_:)` deletes the answer file with the ticket. A listing deletes every
`<id>.answer` whose `<id>.json` is gone, including the tickets of dead processes it has just
pruned. It checks for the ticket file itself rather than trusting the listing's snapshot, since
`readdir` may miss a file created while it runs, so the answer of a live ticket is never deleted.
A hook killed by a signal, or an answer written just after its hook finished, leaves nothing
behind past the next listing.

## Parked tickets

A parked ticket is a live request that has stepped back from the screen. Its one use is Cursor's
"Later": the person dismisses the panel, the request keeps waiting, and the panel returns only on
Show or Show Now, so the request must not hold the head of the queue for up to an hour while
other agents' requests wait behind it. The only caller of `park(_:)` is `DisplayWatch`, when a
Cursor request whose run mode would run it unasked gets Esc, a click outside or the Later link
(see "Esc under Auto-review and Run Everything" in [hosts.md](hosts.md)).

**File field.** `park(_:)` rewrites the ticket file with `"parked": true`. The key is written only
when true, so the file of an ordinary ticket is byte-identical to what it was before parking
existed, and a file without the key reads as not parked.

**Contenders.** The tickets that compete for the screen are the live tickets that are not parked,
in the usual order. `isHead`, `isOvertakenFromMenu`, `place(of:)`, `nextInLine(after:)` and
`ticketAhead(of:)` all work on contenders, so `acquireDisplayIfHead` and `waitForTurn` refuse a
parked ticket and hand the screen to the next one. A parked ticket has no place of its own:
`place(of:)` reports `.absent` for it.

**What still counts it.** `liveTickets()`, `waitingCount`, `waitingEntries()` and
`waitingEntries(excluding:)` keep parked tickets: the request still waits for an answer, and the
menu lists it. `realRequestCount` and `approvalCount` skip them, because a parked request is not
asking for the screen: a test panel has no reason to yield to it, and a context checkpoint has no
reason to wait for it.

**Unparking.** `showNow(_:isOnScreen:)` writes and returns an unparked ticket whatever it was, so
Show Now from the menu or a card's Show puts it at the front, or behind the panel on screen, and
it becomes a contender again. There is no separate unpark.

**Answers.** A parked ticket's process keeps polling its menu answers like any other, so Deny and
Answer in Chat from the menu reach it while it is parked.

## Checkpoint tickets

A context checkpoint (see "The hook path" in [checkpoints.md](checkpoints.md)) queues like a
request, with no grace period and no timeout hand-back, and it writes its ticket only once no
approval is queued: before `enqueue` it polls every 250 ms, checking its abandon reasons each time,
until `approvalCount(excluding: nil)` is 0. That count leaves out test panels and checkpoints
(`TicketSummary.isContextCheckpoint`), so checkpoints from several sessions queue behind one
another and chain through warm standby as usual, but a checkpoint is never next in line behind an
approval when it is written, and so never chains after an approval's answer in place of the
idle gate. An approval that arrives after the checkpoint's ticket waits behind it, FIFO like any
other ticket. Only an approval written in the same instant as the last check can slip ahead; the
checkpoint then waits its turn behind it.

## Test panels

`countersign test-panel` (see "The test panel" in [panel.md](panel.md)) writes a ticket and holds
the lease while its panel is up like any head, but it never queues. It writes its ticket with no
grace period and, instead of `waitForTurn`, shows only when no other live ticket exists: a panel on
screen, read from the other tickets' `Countersign.display` state, or any other ticket refuses it,
and it exits 1 with the reason on stderr (see "One at a time, never ahead of a real request" in
[panel.md](panel.md)). Once up, it counts the other live tickets on every tick and gives up at the
first one: it closes, removes its ticket, releases the lease and exits without a handoff, so a real
request never waits behind it. Its ticket names Claude Code, the project "Countersign test" and the
sample's tool, so the companion's pending list shows it like any request. It ignores the pause
switch and quiet time, and a snooze from its panel ends the process without a handoff, like any
snooze.

## Pause switch

While the pause file exists, the hook does nothing. `PauseSwitch` only creates and removes the
file. `countersign pause`/`resume`, the menu-bar companion's "Pause Countersign"/"Resume
Countersign" item and the settings window's Pause and Resume buttons are its three writers; all go
through `PauseSwitch`.

## Testing the queue across processes

`ticket-probe` is a test-only executable that drives the queue from separate processes, so the
tests exercise real `flock` conflicts, kernel lock release on `SIGKILL`, pid pruning and signal
cleanup. The test target depends on it, so `swift test` builds it next to the test bundle. Its
`chain` mode plays a hook with warm standby: it waits with `waitForTurn`, listens for a handoff
when next in line, reports whether the lease came with a fresh handoff, and on a line from stdin
hands off to its successor with the same `QueueHandoffChannel` the hook uses. It prints
`systemUptime` in microseconds at the moments that matter, which is comparable across processes.

If the test runner dies, its probes must not linger or keep the lock. So a waiting probe gives up
when its parent changes, a probe blocked on stdin finishes at EOF, and every probe ignores
`SIGPIPE`, so a closed stdout cannot kill it while it still owns a ticket. The test harness reads
a probe's exit status only after the probe has exited, because `Process` raises an Objective-C
exception otherwise, and that exception would abort the runner and orphan every probe.

`eventually` and `holds(for:)` measure their deadline with `SuspendingClock`, not
`ContinuousClock`, so time the Mac spends asleep mid-test does not count against the probes'
budget to reach their next state.

Cleanup never waits on `Process.waitUntilExit()` without a deadline either: a `SIGKILL`ed probe's
exit has been seen to go unreported to a still-running test runner, which hangs the whole suite, so
`ProbeProcess.forceStop()` and `ChildProcess.deadPid()` poll `isRunning` through `waitBriefly`
instead and give up after 5 seconds rather than block forever.
