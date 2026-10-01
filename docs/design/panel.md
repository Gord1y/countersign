# The panel

This note explains how the approval panel behaves and why: how it takes the keyboard without
taking focus from the person's app, when it waits before appearing and when it steps aside, the
arm lock against stray clicks and keys, quiet time, the test panel, what the header, question, plan
and permission views show, how a change is diffed against the real file and drawn, how the window
sizes itself, and how `countersign snapshot` renders it offscreen. Read it before you change
anything the person sees or types into, or when the panel does something you did not expect.

## Keyboard alert without activation

The panel behaves like an alert: while it is on screen it owns the keyboard. Return approves, Esc
answers in chat, and nothing typed reaches the app underneath while the panel is up. When the
person turns to something else, switching apps or typing a key the panel has no use for, the panel
steps aside and comes back after the next pause (see "Stepping aside"). The opposite, a panel that
never becomes key until clicked, leaves the keyboard with the person's app: a Return meant for the
panel goes out as a message in the Cursor chat underneath, and ⌘-Tab works as if no prompt were
up.

### Key without activating

`ApprovalPanel` is `[.borderless, .nonactivatingPanel]`. `show()` orders the backdrop and then the
panel front with `orderFrontRegardless()` and then calls `panel.makeKey()`. It never calls
`NSApp.activate`. `orderFrontRegardless` rather than `makeKeyAndOrderFront`, because plain
`orderFront` only guarantees the front of the level for an active app, and ours never is. A
non-activating panel can be the key window while another app stays the active app, so keystrokes
come to the panel and the person's app stays frontmost.

Measured with a probe app (a regular app with a focused text field, standing in for Cursor) that
launched `preview` and watched from the outside:

- The panel is key right away, in the same `show()` call.
- `NSRunningApplication(processIdentifier:).isActive` for our pid stayed `false` throughout, sampled
  every 20 ms.
- `NSWorkspace.didActivateApplicationNotification` never fired for our pid.
- `frontmostApplication` stayed the probe (or Cursor, when run without the probe), and the probe
  app never resigned active.
- `applicationDidBecomeActive` was never called, so the activation guard below never fired.

Inside our process, `NSApp.isActive` reads `true` while the panel is key and `false` once it
resigns. That is AppKit's own view of key focus. It flips without posting either activation
notification, and nothing in countersign reads it.

`makeFirstResponder(nil)` runs right after `makeKey()`, so the panel itself holds first responder,
not a text field (see "Why no text field starts focused"). The backdrop never becomes key or main,
so clicking the dimmed area cannot take the keyboard either.

### Stepping aside

The panel keeps the keyboard only while the person is dealing with it. When they turn to something
else, it gets out of the way instead of pulling the keyboard back. Three things make it step aside:

- **App switch.** `NSWorkspace.didActivateApplicationNotification` names an app other than ours:
  ⌘-Tab, AltTab, a click into another app's window, or an app activating itself. Our own pid never
  counts.
- **Focus lost.** Any window of ours posts `NSWindow.didResignKeyNotification`, and on the next
  turn of the run loop none of our windows is key. That covers a click into a window on a second
  display and the lock screen. The check waits a turn in a `Task` on the main actor, because
  AppKit is still mid key change when it posts the resignation. Key moving to another window of
  our own process, such as a popover, a menu or a child window, is not a trigger, and a later
  resignation of that window is checked the same way.
- **Typing.** A plain key the panel doesn't use (see "Return, Esc and the other keys"). The key
  monitor swallows the key that triggered it, so it never reaches the app underneath.

A ⌘-Tab usually fires both of the first two. Whichever AppKit delivers first names the reason in
the log, and the second finds the panel already gone.

Stepping aside is the snooze path without quiet time. `PanelController` calls its `onStepAside`
closure, and `DisplayWatch` closes the controller, logs `stepped aside: app switch`,
`stepped aside: focus lost` or `stepped aside: typing` and then `waiting for idle`, and returns to
`waitingForIdle` with the same ticket and lease. The request keeps its place at the head of the
queue and comes back as a new `PanelController`, armed from zero, after the next idle pause. The
idle gate counts the ⌘ still held on the switcher, the typing that caused the step-aside, and the
pointer moving in the other app (see "Waiting for a pause before showing"), so the panel comes back
only once the person has stopped. `preview` prints `stepped aside: <reason>` and exits instead.

Nothing re-grabs the keyboard: `makeKey()` runs once, in `show()`. Calling it again on every
resignation while the panel's `occlusionState` is visible hands the keyboard straight back to the
panel after ⌘-Tab or a click into another app; the occlusion condition would only keep a locked
screen, expected to report the panel as occluded, from having the panel pull the keyboard away from
the password field. Instead, the lock screen taking key is a focus loss like any other: the panel
steps aside, and the request waits for the next idle pause. None of this has been observed on the
lock screen itself. The idle gate can pass while the screen is locked, since a locked screen has no
input, so the request can show again behind the lock screen, and `show()` calls `makeKey()` there
as it does anywhere. Whether a key window behind the lock screen receives any of the keys typed on
it has not been checked either. A request that reaches the head of the queue while the screen is
locked takes the same path.

`close()` clears the presented flag and removes both observers and the key monitor before
ordering the windows out. `stepAside` checks the presented flag too. Every exit goes through
`close()`: a finished decision, a step-aside, a quiet-time step-aside, a snooze, and an abandoned
request. A finished decision runs that same teardown (`stopResponding()`) the moment it finishes,
while its windows stay up for the queue handoff, and `close()` after it. So the panel's own
resignation on the way out never triggers a step-aside, and neither does anything after the
request has finished.

### Handing the keyboard back

`close()` orders out both windows and does nothing else. The person's app was the active app the
whole time, so the window server gives key back to its key window on its own. In the probe, the
probe window was key again 8 ms after the panel resigned. It kept its text field as first
responder, so the caret and selection came back. This happened on `close()` itself, before the
process exited, so the step-aside and quiet-time paths, which keep the process alive, get the same
result. After a typing step-aside that matters most: the keys after the swallowed one go straight
to the person's app.

### Return, Esc and the other keys

A single local `keyDown` monitor in `PanelController` handles the keyboard. No button carries a
`.keyboardShortcut`, and there is no `.defaultAction` anywhere. With both footer states of a view
permanently in the tree (see "Keeping the layout still when the content changes"), a shortcut on a
hidden button could still fire.
Instead, the monitor turns Return into `PanelKey.primary`, ⌘Return into `PanelKey.alternate`, and
⌫ (`kVK_Delete`, the backspace key — forward delete is not included) into `PanelKey.secondary`, and
asks the view's `keyHandler` to perform it. `PanelController` performs `.alternate` only when the
visible state's `keyHandler.uses(.alternate)` answers true; otherwise it performs `.primary`
instead, so ⌘Return does whatever Return does everywhere `.alternate` has no meaning. The view
knows which state is visible, so exactly one action fires:

| View | State | Return | ⌘Return |
| --- | --- | --- | --- |
| Permission | default, with suggestions | Approve (allow once) | Opens Approve ▾ |
| Permission | default, no suggestions | Approve (allow once) | Same as Return |
| Permission | deny | Deny, with the reason typed so far | Deny & stop, with the reason typed so far (only when `host.supportsInterrupt`; otherwise same as Return) |
| Questions | all answered | Submit | Same as Return |
| Questions | otherwise | Move to the next unanswered tab, wrapping around | Same as Return |
| Plan | default | Approve with the selected mode | Opens then: ▾ |
| Plan | feedback | Send feedback | Same as Return |
| Any | a dropdown is open | Picks the highlighted row | Closes the dropdown |

| View | State | ⌫ |
| --- | --- | --- |
| Permission | default | Opens the reason step, exactly like clicking "Deny" |
| Permission | deny | Not used by the view; edits the reason field when it is focused |
| Questions | any | Not used by the view, same as before this key existed |
| Plan | default | Opens the feedback step, exactly like clicking "Keep planning" |
| Plan | feedback | Not used by the view; edits the feedback field when it is focused |

The decision for every key is `ApprovalCore.KeyRouter.route`, a pure function of the key's kind
(Esc, Return, ⌫ and whether the visible view uses it, a navigation key and whether the visible view
uses it, anything else), its ⌘ ⌃ ⌥ ⇧ modifiers, whether a text field is being edited, whether it has
marked text, whether the panel is armed, and whether a dropdown is open. It answers pass through,
swallow, dismiss, primary, alternate, secondary, navigate, insert a newline, step aside, or close
the dropdown, and `PanelController` carries that out. While a dropdown is open, the controller asks
the dropdown's `PanelDropdownState.keyHandler` instead of the view's `keyHandler` which keys are
used and performs them there, so nothing reaches the view behind it. The rules:

- **Keypad Enter** counts as Return.
- **⌘Return** routes to `.alternate` instead of `.primary`. `PermissionView` uses it in the
  `.default` step to open Approve ▾ when the request has suggestions, and in the `.deny` step with
  `host.supportsInterrupt`, where it fires "Deny & stop" with the reason typed so far instead.
  `PlanView` uses it in `.default` to open the "then:" mode menu. Everywhere `.alternate` isn't
  used, `PanelController` falls back to `.primary`, so ⌘Return keeps doing whatever plain Return
  does. While a dropdown is open, ⌘Return closes it instead — see the dropdown bullet below.
- **Esc** calls `finish(.noDecision)` in every state, even while a text field is being edited.
  Otherwise `NSTextView` would take Esc as `cancelOperation:` and run completion instead.
  `cancelOperation` on the panel still covers ⌘. the same way.
- **Shift+Return and Option+Return** call `insertNewlineIgnoringFieldEditor` on the field editor, so
  the multi-line reason, feedback, Other and note fields take a line break. With no field being
  edited they are plain keys the panel doesn't use, so they step aside.
- **Other Return combinations** with ⌘ or ⌃ pass through, and so does ⇧⌥-Return in a field.
- **A text field being edited** gets every key except Esc and Return. "Being edited" means the
  first responder is an editable `NSTextView`, the field editor. A selectable, read-only text view
  that becomes first responder after a click does not count, so the panel's keys keep working
  there and a plain key still steps aside.
- **Marked text.** While the field editor has marked text (an input method mid-composition), every
  key passes through untouched, so Return commits the composition instead of approving.
- **⌫ deletes text when a field is being edited**, the same as any other key, never opening
  anything: `KeyRouter.route` returns `.passThrough` for a bare or modified `.delete` whenever
  `isEditingText`, checked before the view is asked whether it uses the key. Outside a field, a bare
  ⌫ (no modifiers) that the visible state's `keyHandler.uses(.secondary)` answers true for becomes
  `PanelKey.secondary`, which does exactly what clicking that state's "Deny" or "Keep planning"
  button does: `PermissionView` answers true only in `.default`, `PlanView` only before
  `showingFeedback`, and `QuestionView` never, so ⌫ there is a plain unused key. ⌫ with any modifier,
  or in a state that doesn't use it, routes exactly like `.other` today: it steps aside, swallowed,
  unless ⌘ or ⌃ makes it a shortcut that passes through. Before the panel is armed a used ⌫ is
  swallowed rather than opening the step, the same lock as Return.
- **Navigation keys** go to the view only while no field is being edited, and only when the view
  uses them. `keyHandler` is a `PanelKeyHandler`: `uses(_:)` answers whether the visible view acts
  on a key without acting, and `perform(_:)` acts. Only `QuestionView` uses any: the digits 1 to n
  for the visible question's n options, and ← and → (at the first or last tab they are consumed
  and do nothing). ⇧ is allowed, since on some layouts the digits need it. With ⌥ they are plain
  unused keys. `PermissionView` and `PlanView` use `.primary` always and `.secondary`
  conditionally, per the ⌫ table above; `QuestionView` never uses `.secondary`.
- **An open dropdown** (see "Countersign's own dropdown") takes ↑, ↓, the digits for its rows,
  Return, ⌘Return and Esc, even while a text field is being edited, since the header's Snooze can
  be opened with the reason or feedback field focused. ↑ and ↓ move the highlight, wrapping
  around; a bare Return picks the highlighted row; 1 to 9 pick that row directly; Esc closes only
  the dropdown, never the panel. ⇧ is allowed on the arrows and digits as elsewhere. ⌘Return closes
  the dropdown, the same as Esc, so it never reaches the panel behind it; a Return combination with
  any other modifier is still swallowed. A digit past the last row, ←, →, ⌫ and every other key
  route exactly as unused keys do with no dropdown open, whatever the view behind it would do with
  them: ⌫ never opens the deny or feedback step then. Before the panel is armed the dropdown's
  arrows, digits and Return are swallowed, but ⌘Return and Esc still close it. Marked text still
  wins over all of it.
- **⌘ and ⌃ combinations** pass through, so ⌘C copies a selection in the panel.
- **Every other key** without ⌘ or ⌃ steps aside and is swallowed: letters, punctuation, Space,
  Tab, ↑ and ↓ with no dropdown open, Page Up and Down, a digit the visible question has no option
  for, the function keys, and anything with only ⇧ or ⌥. Scrolling a long request works with the
  trackpad or mouse, not with the keyboard.
- **Before the panel is armed**, the keys the panel uses (Return, Esc, a bare ⌫ the visible state
  uses, and the navigation keys the view uses) are consumed and do nothing, as are the Return
  combinations with ⌘ or ⌃. A plain key the panel doesn't use steps aside during the lock too: a
  person who keeps typing into the app underneath gets the panel out of the way at once.
- **A repeated Return, Esc or used ⌫ never dismisses, acts or steps aside.** `KeyRouter.route`
  takes `isRepeat` from `NSEvent.isARepeat` and turns what would have been `.dismiss`, `.primary`,
  `.secondary` or `.stepAside` into `.swallow` when the key is a repeat, whether the panel is armed
  or not. A repeat that would pass through or insert a newline is unaffected, and so is a repeated
  navigation key or a ⌫ that steps aside (unused or modified): only Return, Esc and a used ⌫ carry
  an action worth guarding against a hold. See "The arm lock" for why a held key needed this on
  top of the lock itself.

Because the panel is key, anything the monitor passes through goes to the panel's own responder
chain, never to the app underneath.

Because the panel takes the keyboard instead of never becoming key, three guards keep it from
taking keys meant for something else. The idle gate (5 s by default, see "Waiting for a pause
before showing" and [configuration.md](../configuration.md)) keeps the panel from appearing while
the person is busy. The arm lock (see "The arm lock") swallows a key that was already on its way
when the panel appeared. Stepping aside hands the keyboard back as soon as the person turns to
something else.

## Never activating

Being key is by design. Being active is not. If the countersign process ever becomes the active
app, the person's app stops being the active app and loses its caret and selection.

**Cause.** Ordering the backdrop and panel front before `NSApplication.run()` means ordering them
before `finishLaunching`, and when launch finishes with windows already on screen, the app is
activated. We observed this and did not trace the internal path. Under macOS 14's cooperative
activation, that request is granted only while the process's responsible app is frontmost. For a
hook, that is the editor or terminal that spawned Claude Code or Codex. So the activation looks
intermittent: measured with `hook` and `preview` ordering their windows front that early, the
process became the active app about 0.1 s after launch and stayed active while Cursor was
frontmost, and the request was denied while any other app was. Probes isolated it:

- An accessory app with no windows never activated.
- The same app with a non-activating panel ordered front before `run()` activated right after
  `applicationDidFinishLaunching`.
- The same panel ordered front from `applicationDidFinishLaunching` never activated.

Neither `setActivationPolicy(.accessory)` nor any `activate` call was involved.

**Fix.** `PanelApplication` owns the launch for both commands. It creates `NSApplication`, sets
`.accessory`, becomes the delegate, and calls `PanelController.show()` only from
`applicationDidFinishLaunching` (or right away, if launch has already finished).

**Guard.** Before `NSApplication` exists, `PanelApplication` captures
`NSWorkspace.shared.frontmostApplication`. It updates that on every other app's activation. If
`applicationDidBecomeActive` ever fires before the person has clicked into the panel, it logs
`activation guard fired` (to the event log in `hook`, to stderr in `preview`), yields activation to
that app, and reactivates it with `activate(from:options:)`, falling back to `deactivate()`. A
local mouse-down monitor on `ApprovalPanel` records the click. Key status can't serve as that
signal. The panel is key by design from the moment it appears, so being key says nothing about
what the person meant; only a click does. The programmatic `makeKey()` in `show()` leaves the
click flag alone, and it never trips the guard, because it does not call
`applicationDidBecomeActive` (measured, see "Key without activating"). The guard undoes activation,
never key status. If it ever does fire, handing activation back to the other app activates that
app, so the panel steps aside as for any app switch and returns after the next idle pause. The
guard is a safety net, not the fix. With the windows ordered front before `run()`, it handed focus
back to Cursor 24 ms after the stray activation. With `show()` called from
`applicationDidFinishLaunching`, it never fires.

## Borderless: no titled window means no dead strip

`ApprovalPanel` is `[.borderless, .nonactivatingPanel]`, not `.titled` with a transparent, hidden
title bar: a titled window reserves its own ~22 pt strip above the content even with every
title-bar control hidden. Borderless, no title bar exists to reserve that space, so the SwiftUI
content fills the window edge to edge, and the window itself is `isOpaque = false` with a `.clear`
background so only the rounded, materialed root view is visible against the backdrop.

## Centered on the mouse's display, over a blurred backdrop

`PanelController` targets the `NSScreen` containing `NSEvent.mouseLocation` (falling back to
`NSScreen.main`, then the first available screen), and centers the panel — both axes — in that
screen's `visibleFrame`, 640 pt wide with height fit to content and clamped to 80% of the visible
height. It re-centers whenever the content's height changes rather than sitting in a fixed corner
such as the top right: a floating popup that already draws the eye toward the display it must be pulled from
doesn't also need a fixed corner to stay findable, and centering keeps it readable regardless of
which screen or how tall the request is.

A `BackdropWindow` covers that same screen's full frame, one `NSWindow.Level` below the panel,
with an `NSVisualEffectView` (`.fullScreenUI`, `.behindWindow`) plus a dark overlay to blur and dim
whatever is behind without hiding it, so attention goes to the popup instead of a plain dark
rectangle. `show()` fades both windows in together over 0.15 s; `close()` orders both out
immediately, with no fade needed on the way out. A finished decision leaves both windows on screen,
no longer responding to anything, until the hook has handed off to the next request or found none,
and then closes them. A panel shown after a queue handoff gets the backdrop the next hook already
put up and appears at full opacity with no fade, so one panel replaces the other without a flicker
(see "Why no fade between chained panels" in [queue.md](queue.md)). Only the target screen gets a
backdrop — a second display, if any, is untouched.

A panel on screen follows the displays when they change. The screen used to be fixed when the
panel was built, and the hook watched `NSApplication.didChangeScreenParametersNotification` only
while it was queued, so a panel whose display was unplugged, rearranged or changed resolution kept
a stale `NSScreen`: its width, its 80% height cap and its centre came from a visible frame that no
longer existed, and its backdrop covered empty space or the wrong part of a display. `DisplayWatch`
now observes that notification in every state. Queued, it rebuilds the prepared panel as before
(see "Warm standby and the queue handoff" in [queue.md](queue.md)). Shown, it calls
`PanelController.followScreenChange()`, which gives the panel's current frame to `ScreenPlacement`
in `ApprovalCore`: the screen to use is the one holding the frame's centre, else the one the frame
overlaps most, else the first screen, the one with the menu bar. The controller then re-applies
the width and the height cap against that screen, re-centers the panel in its `visibleFrame` at
its current height (lower if the new screen is shorter), and moves the backdrop onto that screen's
full frame, and the hook publishes the display again so a request next in line prepares for the
display the panel is on now. The frame is the input, not the display the panel was built for,
because a display that is gone cannot be looked up and AppKit may already have moved the window
onto a remaining one. After a rearrangement the panel lands on whichever display now holds its
centre; whether AppKit carries a borderless panel along with its display when the arrangement
changes has not been checked on screen. Re-centering drops the settled top edge that keeps the
panel still while its content changes (see "Keeping the layout still when the content changes"):
that edge is in coordinates the new arrangement may not have. Which display a new panel picks is
unchanged: the mouse's.

Neither window uses AppKit's own ordering animations: both set `animationBehavior = .none`. That
changes nothing today. AppKit's private `_effectiveAnimationBehaviorIfModal:`, called offscreen on
a borderless `.nonactivatingPanel` `NSPanel` configured like each window, already answers `.none`,
where a plain borderless `NSWindow` gets the document-window animation and a titled utility panel
the utility-window one. Setting it explicitly keeps a later macOS from animating the head's
`orderOut` or the next panel's `orderFront` between two chained panels.

## Sound when a panel appears

`show()` plays the `panelSound` config value once, through `NSSound(named:)`, right after the panel
is ordered front and before the fade starts. The name is `none` or a file name without extension in
`/System/Library/Sounds`; `none`, the default, plays nothing. Only `PanelController` plays it, so
the result card and notices, which are not panels, stay silent, while real requests, context
checkpoints and test panels all sound: a test panel is how someone hears their choice, next to the
play button in Settings' Panels tab.

A panel shown after a queue handoff (`isAfterHandoff`) does not play it. That panel is the next
question in a run of answers the user is already working through, arriving at full opacity with no
fade for the same reason: one panel replaces the other, and a chime per panel across a burst of
requests would turn into noise. The sound marks the start of a chain, when the user's attention is
elsewhere.

The config parser validates the name against a list it is handed, never the disk. The app passes
the names it finds in `/System/Library/Sounds` (falling back to the fourteen macOS ships when the
folder cannot be read), so an unknown name logs one line and falls back to `none`. Haptics are not
an option: macOS plays them only on a Force Touch trackpad during a touch, so they cannot serve as
an alert.

## Click outside answers in chat, once armed

The backdrop's content view forwards `mouseDown` to `onClickOutside`, which `PanelController` wires
to `model.finish(.noDecision)` — the same "leave it for chat" path as the Escape key and the
"Answer in chat" button. `finish` still gates on `isArmed`, so a click meant for whatever was under
the previous panel during the arm lock (see "The arm lock") is swallowed rather than dismissing the
one that just appeared. While one of the panel's dropdowns is open, the click closes only the
dropdown, as Esc does then (see "Countersign's own dropdown"); the next click answers in chat.

## Waiting for a pause before showing

A panel must never appear while the person is doing something, so `DisplayWatch` in `HookRunner`
holds off in a `waitingForIdle` state after the lease is acquired instead of showing the panel
right away. Each 250 ms tick asks `ActivityGate.isIdle(secondsSinceLastInput:modifiersHeld:)`,
fed by the `SystemActivity` that `DisplayWatch` owns. Only once idle does a `PanelController` get
created and shown, moving the state to `shown(controller:)`. Every other queued request waits for
the same idle gate once it reaches the head in turn. The one exception is a request moved to the
front with Show Now from the menu bar while no panel is on screen: the person has just asked for
it, so it skips the gate once, until it is displayed, and quiet time still holds it (see
"Answering from the menu bar" in [queue.md](queue.md)).

Every kind of input counts as activity:

- **Events.** `secondsSinceLastInput()` is the minimum of
  `CGEventSource.secondsSinceLastEventType(.combinedSessionState, …)` over key down, key up,
  modifier changes (`flagsChanged`), the three mouse-down types, mouse movement, the three drag
  types and the scroll wheel. Mouse movement counts like any other input. Leaving it out, so that
  a hand resting on the mouse cannot hold a panel back, gains nothing: a resting hand sends no
  events, and a moving pointer is the person working: aiming at a button, dragging a selection,
  following text while reading. A panel that opens under a moving pointer takes the click that was
  aimed at something else.
- **Held modifiers.** `modifiersHeld()` reads `CGEventSource.flagsState(.combinedSessionState)`.
  While ⌘, ⌥, ⌃, ⇧ or Fn is held, the gate is not idle, however long ago the last event was. The
  ⌘-Tab switcher and AltTab stay open for as long as their modifier is held, and a person can hold
  it past the idle threshold while picking a window. Event timestamps alone would call that idle
  and open the panel over the switcher. Caps Lock is left out: `maskAlphaShift` is the lock's
  toggle state, not a held key, so counting it would hold back every panel for as long as Caps Lock
  is on. The numeric-pad and non-coalesced flags describe an event, not a key, and are left out
  too. With no key held, `flagsState` read `0x0` for both the combined and the HID state. A
  modifier that some other software leaves stuck down in the session state would hold panels back
  until it is released. Measured on 2026-09-24 with a probe process spawned from Claude Code inside
  Cursor, whose Input Monitoring access was denied (`IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`
  not granted): during a 10 s hold of ⌘ on the ⌘-Tab switcher, `CGEventSource.flagsState
  (.combinedSessionState)`, `CGEventSource.flagsState(.hidSystemState)` and `NSEvent.modifierFlags`
  all reported ⌘ held on every 50 ms sample, and `secondsSinceLastEventType` saw the key and
  modifier events throughout. So the gate's inputs need no Input Monitoring permission, which a
  hook never has anyway — it inherits whatever permissions the terminal or editor running Claude
  Code or Codex was granted. Also on screen that day, a real hook panel appeared about 5 s after ⌘
  was released, never while it was still held.
- **Input source changes.** `SystemActivity` observes the
  `com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged` distributed notification (the
  value of HIToolbox's `kTISNotifySelectedKeyboardInputSourceChanged`, spelled out because the
  constant imports as an implicitly unwrapped optional) and treats its arrival as input. A switch
  from the keyboard or the menu bar already comes with a key or a click; the notification covers
  the ones that don't, such as another app changing the input source. The observer is registered
  with `.deliverImmediately`. The `DistributedNotificationCenter.suspended` documentation says
  AppKit suspends delivery while an app is not active, and ours never is (see "Never
  activating"), so a coalescing observer might not hear the change until the hook has exited.
  Delivery can come on any thread, so the handler takes `systemUptime` right away and
  hands it to the main actor. The observer exists from the moment `DisplayWatch` is created,
  right before the hook's run loop starts. A change during the grace period or in the queue is not
  seen, which matters only for a change that came with no input event of its own within the idle
  threshold before the lease was won.

Once shown, the panel owns the keyboard (see "Keyboard alert without activation"), so a key typed
while it is up lands in the panel, not elsewhere, and there is no key-down somewhere else to watch
for. The panel itself decides when to step aside: a plain key it doesn't use, another app
activating, or the keyboard leaving our windows sends it back to `waitingForIdle` (see "Stepping
aside"), and this gate decides when it returns. A shown panel leaves the screen when it is answered
or dismissed, when it steps aside, when quiet time starts, or when its request is resolved
elsewhere.

One path skips this gate: the queue handoff. When a panel is answered (Approve, Deny, or answer in
chat by button, Esc or a click on the backdrop), the next request in the queue shows at once,
because the person is already looking at the dimmed screen and reading prompts; making them sit
still for 5 s between two prompts they are working through would only slow them down. The next
hook keeps AppKit running while it waits and builds its panel then, without showing it, for the
display the answered panel is on. It puts its own backdrop up at full opacity on that display
before the answered panel's backdrop goes, and shows its panel as soon as it has the lease, so the
dim never breaks between the two panels. The arm lock still runs from zero on the new panel, for
the shorter `chainedArmDelay` (0.1 s by default, see "The arm lock"), so a second Return meant for
the first panel does nothing. Nothing else chains:
after a step-aside, a snooze, quiet time, or a request resolved elsewhere, the next panel waits
for this gate. The protocol, and why a stale handoff can never skip the gate, is in "Warm standby
and the queue handoff" in [queue.md](queue.md). A handed-off panel centers on the display the
previous backdrop covered, not the one under the mouse.

### Handing off to the asking app

Whether a request goes to its own app's prompt instead (`handoffApps`, see
[configuration.md](../configuration.md)) is decided at the moment its panel would appear, not
when the request arrives: right after this gate passes, which includes a panel coming back after
a step-aside, a snooze or quiet time, and right before a panel is shown after a queue handoff.
`HandoffCheck.shouldHandOff(frontmostBundleID:frontmostPID:handoffApps:hostAppPID:)` applies the
rule from "Why the handoff rule is per-app" in [hosts.md](hosts.md) to
`NSWorkspace.shared.frontmostApplication` as it is at that moment and to the host app `hook`
resolved when the request arrived. When it holds, `DisplayWatch` logs
`handoff: <bundle id> frontmost`, writes `Host.handoffOutcome` when the host has one (Cursor and
Antigravity), closes any prebuilt panel, removes its ticket, releases the lease and exits 0. The
next request then takes the lease and waits for this gate as usual.

Deciding at arrival read a frontmost app that is often gone by the time a panel could show: a
request that arrived while the asking app was in front exited at once, and a person who then
switched to another app never got a panel for it, because nothing was left waiting. The cost of
deciding later falls on the person who stays in the asking app: its own prompt comes only after
the grace period, the queue and this idle pause, not at once, and Codex shows "Waiting for the
approval panel" in the meantime. A test panel never hands off (see "The test panel"), and neither
does a context checkpoint, which Claude Code has no prompt of its own for (see "The hook path" in
[checkpoints.md](checkpoints.md)).

### The approval card

The gate has a cost for a person who never stops: while they keep typing or moving the mouse,
`ActivityGate.isIdle` never turns true, and a request sits in `waitingForIdle` until
`TimeoutHandBack` gives it back (3540 s for Cursor and Antigravity, never for Claude Code and
Codex). Cursor shows no prompt of its own while its hook runs, so the agent simply stops and the
person does not know it is waiting. The approval card tells them without taking anything from
them: a corner card, `<Host.displayName> needs your approval · <projectName>`, with a `Show`
button and the close button. It is the waiting notice's card with its own content (see "The card"
and "The shared corner card" in [notice.md](notice.md)): non-activating and never key, so it takes
no keystroke, at the top right of `PanelController.resolveTargetScreen()` in the lowest free
notice slot, and it posts an accessibility announcement with its line and plays no sound.

`DisplayWatch` records `waitingForIdleSince` (`systemUptime`) on every entry into
`waitingForIdle`: on arrival with the lease, after `takeDisplayIfFree` wins the lease without a
fresh handoff, and after a shown panel steps aside, for quiet time, a snooze or the panel's own
reasons. A tick in `waitingForIdle` that does not show the panel asks
`ApprovalCardTiming.shouldShow(enabled:mode:secondsWaiting:delay:quiet:paused:stage:)`. It is true
only when `approvalCard` is on for the request's agent, the run is `.hook` (never a test panel or a
context checkpoint), quiet time does not hold panels, the pause switch is off, no card has been
shown or dismissed for this request (`ApprovalCardStage.notShown`), and `approvalCardDelay`
seconds (5 by default) have passed since `waitingForIdleSince`. With all four slots taken the card
stays unshown and the next tick tries again. The panel check runs first in the tick, so a request
that turns idle in the same tick shows its panel and never flashes a card.

`Show` does what the menu's Show Now does for a request at the front: it sets `showsWithoutIdle`,
closes the card, and the next tick shows the panel with the usual `armDelay`, quiet time still
holding it. The close button (`Dismiss`) closes the card and leaves the request waiting for a
pause; it gets no second card. Neither does a request whose card was shown and that comes back to
`waitingForIdle` after a step-aside, so a person sees the card at most once per request. The
card also closes, and releases its slot, whenever the request leaves `waitingForIdle`: its panel
shows (Show Now from the menu bar included), it is answered from the menu bar, it gives way to a
request shown from the menu,
it is resolved elsewhere or paused, handed back, handed off to the asking app, or yields to a real
request. Quiet time that starts while the card is up leaves it up: the request is still waiting,
and `Show` then shows the panel once quiet time ends. Log lines: `approval card: shown`,
`approval card: show`, `approval card: dismissed`.

The card is per agent (`approvalCard` and `approvalCardDelay`, top level and under
`hosts.<agent>`, see [configuration.md](../configuration.md)) because the hosts differ in what a
waiting request costs. Cursor, Codex and Antigravity are on by default: Cursor and Antigravity
show nothing of their own while the hook runs, and Codex only says "Waiting for the approval
panel". Claude Code is off by default, a product decision: its request also sits in the chat,
where the person can answer it while they work and Countersign notices the answer (see
`ResolutionWatcher` and "Why "Answer in chat" returns no decision"), so it is not stuck the way
the others are. Turning it on is one key, `hosts.claude.approvalCard` or the top-level
`approvalCard`.

## Quiet time

`QuietTime` stores a single epoch-seconds deadline at `AppPaths.quietFile`, written atomically
(temp file, then `rename`) the same way `TicketQueue` writes a ticket. `activeUntil(now:)` is the
only read path: nil when the file is absent, unparseable, or names a moment already in the past,
so a stale file left behind by a crash never wedges the queue shut. Nothing ever deletes the file
on expiry; the next `activeUntil` call after the deadline just returns nil.

`DisplayWatch`'s `waitingForIdle` case checks `quietTime.activeUntil() == nil` before the idle
check, so quiet time holds a panel back even once the person goes idle. A test panel skips this
check, the shown panel's and the queue handoff's, and its Snooze menu never starts quiet time (see
"The test panel"). The abandon check —
`ResolutionWatcher` or the pause switch — still runs first on every tick regardless of state, so a
request answered in another chat during quiet time exits silently rather than waiting the full
duration out: quiet time only ever delays a panel's appearance, it never keeps a hook alive past
the point its request was already resolved elsewhere.

Quiet time can start three ways, and all are handled where a panel could otherwise appear:

- **From the panel's own Snooze menu**, while a panel is on screen. Its items come from
  `PanelModel.snoozeMinutes` — `[1, 5, 15, 30]` by default, config-driven (see
  [configuration.md](../configuration.md)) — reading "Quiet for `<duration>`" for the first entry and just
  "`<duration>`" for the rest (`ApprovalCore.SnoozeTitle.describe`), and each calls `PanelModel.snooze(_:)` with that many minutes in
  seconds. `snooze(_:)` mirrors `finish`: gated on `isArmed`, and only the first call counts. The
  runtime's `onSnooze` closure writes the deadline, calls `controller.close()` itself —
  `PanelController` does not auto-hide on snooze the way it does on `finish`, since closing here
  is one step in a state transition the caller owns, not a terminal outcome — and returns
  `DisplayWatch` to `waitingForIdle` with the same ticket and lease, so this request keeps its
  place at the head of the queue and reappears through the ordinary idle rule once quiet time
  ends. A write failure is logged and treated as a no-op: the panel stays up as if the click never
  happened.
- **From `countersign snooze` on the command line**, while a panel is already on screen for an
  unrelated hook. Nothing polls for this directly; `shown`'s branch of `tick()` checks
  `quietTime.activeUntil()` on every tick. Finding quiet time active closes the panel, logs
  `stepped aside: quiet time`, and returns to `waitingForIdle` with the same ticket and lease, so
  this request stays at the head of the queue and shows again, armed from zero, after quiet time
  ends and the next idle pause. The CLI does not need to know a panel exists, only the tick loop
  does.
- **From the menu-bar companion's Snooze submenu**, which writes the same file through the same
  `QuietTime`, with the same titles from `SnoozeTitle.describe`, and so takes exactly the CLI's
  path above; its "End quiet time" is `countersign snooze off` (see "Menu-bar companion" in
  [app.md](app.md)).

Every waiting hook — whether it is mid-grace, queued, or holding the display lease — keeps
running its own `ResolutionWatcher` poll throughout quiet time; none of this is special-cased for
quiet time, since abandonment was already checked before any panel decision on every tick. That is
what makes quiet time "no gaps": the one thing quiet time changes is whether `waitingForIdle` is
allowed to show a panel, never whether a hook keeps watching for its own resolution.

## The test panel

`countersign test-panel [command|question|plan|context]` (`command` when no kind is given) shows a real
panel for a built-in sample request, so a person can see what their settings do and try the keys
without any agent asking for anything. The menu-bar companion's "Show a Test Panel" starts it with
`command` as a process of its own (see "Show a Test Panel" in [app.md](app.md)). It is an
ordinary CLI, not the hook: bad arguments print the usage line to stderr and exit 1, and so does a
refusal (see "One at a time, never ahead of a real request"). Everything else goes to the event
log, and stdout stays empty.

### Where the samples come from

`ApprovalCore.TestPanelSample.payload(for:)` builds one Claude Code `PermissionRequest` payload per
kind, and `request(for:)` parses it with `ClaudeAdapter.parse`, the adapter a hook uses, so the
panel shows exactly what a real request of that shape shows:

- **command**: `Bash` running `git push origin main`, described as "Push the main branch to
  origin", with one "Always allow" suggestion, so Approve has its ▾ menu.
- **question**: `AskUserQuestion` with two questions, a single-select one with option descriptions
  and a multi-select one.
- **plan**: `ExitPlanMode` with a short Markdown plan and `permission_mode` `plan`, as a real plan
  arrives.
- **context**: not a `PermissionRequest`. `TestPanelSample.request(for:settings:)` builds the
  context checkpoint request directly (see "The context checkpoint panel"). The Panels tab offers
  only `TestPanelKind.panelsTabKinds` (command, question, plan); `context` is reached from the CLI
  and from snapshots.

Each payload uses only key paths the matching captured fixture has, `claude-bash.json`,
`claude-questions.json` and `claude-plan.json`, which `TestPanelTests` checks path by path, so no
sample invents a shape. None carries `transcript_path`, `agent_id` or the plan's optional
`planFilePath`: there is no chat to watch, no subagent chain and no plan file. The `cwd` is
`/Countersign test`, which is never read; it only makes the header's project name, and the
ticket's, read "Countersign test". `PanelRootView` adds a "Test" `Chip` right after the project
name when `PanelModel.isTestPanel` is set, with a hover card saying nothing reaches an agent.

### What runs

`TestPanelCommand` reads the config file the way a hook for `claude` does
(`Settings.resolve(file:host: .claude)`, so `hosts.claude` applies), logs
`test panel: start kind=<kind>`, and hands the request to
`HookRunner.showPanel(for:mode:settings:paths:log:startedAt:hostApp:)` with
`PanelRunMode.test(kind)` and no host app. The hook hands its own request to the same function
with `.hook` and the host app it resolved, once its preamble (stdin, pause, parsing, the sandbox,
asked-about and headless-session checks) has passed, so both share one code path: a ticket and the
display lease, `armDelay`, the Snooze presets, `questionNotes`, stepping aside and coming back
after the next pause, and handing the display on after an answer. The pipeline's own log lines,
such as `displayed` and `stepped aside: typing`, are the hook's, under the test process's pid.

### One at a time, never ahead of a real request

A person clicking the test buttons a few times once queued eleven test panels, each waiting for
its own idle pause, while real requests waited behind them. So a test panel shows at once or not
at all. It writes its ticket with no grace period, and `TestPanelCommand.takeDisplay` asks
`TestPanelAdmission.decide(panelOnScreen:otherTickets:)` instead of calling `waitForTurn`.
`panelOnScreen` is whether any other live ticket has a `Countersign.display` state (see "Warm
standby and the queue handoff" in [queue.md](queue.md)), and `otherTickets` counts the other live
tickets. A panel on screen refuses with `a panel is already on screen; answer it first`, any other
ticket, a request waiting for idle, in quiet time or as next in line, refuses with
`a request is waiting for a panel; answer it first`, and only an empty queue shows. The display
lease is then taken with `acquireDisplayIfHead`. A ticket written after the test panel's is behind
it, so failing that means a panel removed its ticket but still holds the lock on its way out (see
"Removal order" in [queue.md](queue.md)), which refuses as a panel on screen. A refusal removes the ticket, logs
`test panel: refused (<reason>)`, prints `countersign: <reason>` to stderr and exits 1, which is
how `TestPanelLauncher` learns the reason (see "Show a Test Panel" in [app.md](app.md)).

`DisplayWatch` logs `showing at once` instead of `waiting for idle` and shows the panel as soon as
the app has launched, without the idle gate. The gate still applies after the test panel steps
aside, so it comes back only once the person has stopped, like a real panel.

On every tick, and once more right before it first shows, a test panel counts the other live
tickets that are not themselves test panels (`TicketQueue.realRequestCount(excluding:)`). Any at
all, a real request past its grace period, closes the test panel, removes its ticket, releases the
lease, logs `test panel: closed for a real request` and exits 0, without a queue handoff: the
request then takes the display and waits for idle as usual. A real request therefore never waits
behind a test panel, and a test panel never appears in a real request's waiting list for longer
than one tick. A test panel gives way only to a real request; a second `countersign test-panel`
run is refused instead (see "One at a time, never ahead of a real request" above), so two test
panels never close each other.

### What is skipped, and why

`PanelRunMode` names each difference, so the hook path reads the same as before with `.hook`:

- `honorsGracePeriod`, `waitsItsTurn` and `waitsForIdleOnArrival` are false, and
  `yieldsToOtherRequests` is true. See "One at a time, never ahead of a real request".
- `honorsPause` and `honorsQuietTime` are false. A test is an explicit request made that moment,
  so it shows while Countersign is paused and during quiet time. A real request held back by quiet
  time still holds a ticket, so the test panel refuses while one waits.
- `followsChat` is false. There is no chat, so no `ResolutionWatcher`, parent-exit check included,
  and no chat-tracking health check, so never a warning triangle.
- `handsBackBeforeTimeout` is false. The hand-back before a Cursor or Antigravity timeout (see
  "Handing back before Cursor's timeout") never applies to a Claude request anyway, and nothing
  times a test panel out.
- The preamble never runs. There is no stdin to read.
- `isTest` turns off the `handoffApps` check before showing (see "Handing off to the asking app"):
  the person has just asked for the panel, and handing it off would only mean no panel.

No reply is written anywhere and nothing reaches an agent. Every answer, Approve with or without a
suggestion, Deny, Deny & stop, Answer in chat by button, Esc or a click on the backdrop, a
question's Submit, a plan's Approve or Keep planning, closes the panel and logs one line from
`TestPanelLog.outcome`: `test panel: approved`, `approved with a suggestion`, `denied`,
`denied and stopped`, `answered in chat`, `submitted` or `kept planning`. Stdout stays empty. The
answer still offers the display to a next request in line, like a real answer, though one that
arrived would already have closed the test panel. The Snooze menu lists the person's presets, but
choosing
one logs `test panel: snoozed for <duration>, quiet time not started`, closes the panel and ends
the process without writing the quiet-time file, and without a queue handoff, since a snooze never
chains.

### The result card

A test panel that ends in an answer does not simply vanish: the person could not tell what Approve
with a suggestion or Deny & stop would have done, or how "Compact after this step" differs from
"Hand off & start fresh", without reading `docs/agents.md`. So `DisplayWatch.finish` closes the
panel, does what it always did (offers the display on, removes the ticket, releases the lease) and
then shows a result card in the panel's place instead of exiting.

`TestPanelResult.describe(_:kind:checkpointChoice:)` in `ApprovalCore` returns the card's title,
what was picked (`Approved`, `Approved with a suggestion`, `Denied`, `Denied and stopped`,
`Answered in chat`, `Submitted`, `Kept planning`, `Continued`, `Compact after this step`,
`Hand off & start fresh` or `Not this session`), and its detail: one or two sentences on what
Claude Code would do, taken from [agents.md](../agents.md) and always ending with `Nothing reached
an agent.` For the two context notes the detail is the note Claude would receive, filled in with
the sample's tokens and handoff file, in quotes. The outcome alone cannot tell Continue from Not
this session (both are no decision), so a test panel passes `onCheckpointChoice` too, as a
checkpoint does, and `DisplayWatch` keeps the choice. In test mode the callback only records it: no
mute, no state write, no `context choice:` line.

The card is `TestPanelResultCard`, an `ApprovalPanel` (borderless, non-activating, floating) with
the panel's material, corner radius, border and typography: the title, then the detail, which
scrolls past eight lines, and nothing else. It is 420 pt wide and centred on the frame the test
panel had when it closed (`PanelController.frame`), and it takes the height its content reports,
the same way the panel does. Every frame it takes goes through `ScreenPlacement` first, so it is
clamped into the visible frame of the screen that holds it, and on a display change `DisplayWatch`
moves it the same way it moves a shown panel (see "Centered on the mouse's display, over a blurred
backdrop"): the card never waits out its 8 seconds on a display that is gone. It closes on a click, on Esc or after 8 seconds, and the process exits
when it closes, so the card never outlives its use. It is key like the panel was, which is what
lets Esc reach it, but as a non-activating panel it takes no focus from the app the person is in
beyond what the test panel already had.

A real request that queues while the card shows closes it at once, by the rule that closes the
test panel (see "One at a time, never ahead of a real request"): `DisplayWatch` keeps ticking in
the `showingResult` state, and `test panel: closed for a real request` is logged. The card is not
shown after Snooze (there is no answer), after a real request closed the test panel, or after a
refusal. It logs `test panel: result shown` once, and never the note's text.

## Countersign's mark and one accent

Every panel looks the same whichever agent is asking. The header starts with Countersign's own
mark, `CountersignMark` (`CountersignMark.swift`), the app icon's small-size art drawn in code at
20 × 20 pt (see "The mark in the panel header" in [icon.md](icon.md)), followed by the agent's name
in text, `Host.displayName`. The agent is named in words only: no badge or button takes an agent's
color, and no symbol stands in for an agent's logo. There is one accent, on every panel and in the
Settings window: amber by default, or the color a person picks as "Accent colour" in Settings' App
group (`accentColor`). Three reasons for one accent rather than one per agent:

- **It must be clear which program is asking you to decide.** The panel is Countersign's, not the
  agent's. A tile or a button in the agent's own color reads as the agent's own prompt; the mark
  says the decision is taken in Countersign, and the name beside it says which agent it is for.
- **One Approve color everywhere.** Approve, Submit and the plan's Approve are the same accent on
  every panel, so the primary action is found by one color rather than by whichever agent asked.
- **No look-alikes of other companies' brands.** An agent's brand color on the tile, or a symbol
  picked to evoke its product, imitates another company's identity. Amber, the default, is
  Countersign's own color, the ink of its icon (see "The accent" in [icon.md](icon.md)).

The mark keeps amber whatever accent is chosen: it is the app icon, drawn in code, and its ink is
part of the icon, so `CountersignMark` holds its own `signatureInk` rather than reading
`CountersignPalette`. A blue Approve beside an amber mark still says "Countersign's panel, your
color".

### The three accent colors

`CountersignPalette` in `PanelStyle.swift` holds three colors, all derived from the one configured
accent by `ApprovalCore.AccentPalette`:

- `accent`, the chosen color itself (`fill`), fills: `PrimaryButtonStyle`'s default fill (Approve,
  Submit, the plan's Approve, and the Settings window's Wire and Update) and the Approve split button's `chevron.down` segment.
- `onAccent` (`label`), the label and glyph on an accent fill, including the `⏎` hint (`KeyHint`
  placement `.onAccent`, at 80%): `#1D1B18` or white, whichever has the higher contrast ratio with
  the fill. On amber `#1D1B18` has about 8.7:1 and white about 2:1, too low to read; on each of the
  six presets the near-black label wins too, while a dark custom color such as navy gets white.
- `accentText`, for text, glyphs, thin strokes and small marks: the selected question tab, an
  option card's selected stroke and indicator, a plan's bullet dots and numbered-item digits, a
  diff's "Show … unchanged lines" row, the waiting chip, the arm lock's progress line and a
  dropdown's checkmark. It is a dynamic `NSColor` (`NSColor(name:dynamicProvider:)`) holding two
  colors, `lightText` and `darkText`, so it resolves against the view's appearance, on screen and in
  snapshots. A tint behind such text, the selected tab's capsule, a selected option card's fill, a
  dropdown's highlighted row and the waiting chip's capsule, is `accentText` at low opacity, the way
  `Chip` derives its fill from its one `tint`.

`lightText` is the accent darkened until it reads at 4.5:1 or more on white, and `darkText` the
accent lightened until it reads at 4.5:1 or more on `#1E1E1E`, the dark panel's background. 4.5:1
is WCAG's contrast minimum for normal text, and these colors are small text and hairlines, so they
need it more than a fill does. Contrast is WCAG's: relative luminance from linearized sRGB, and
(lighter + 0.05) / (darker + 0.05). Darkening and lightening move the color's HSL lightness in
steps of 0.005 toward black or white, keeping its hue and saturation, and test each step as the
8-bit color it will be drawn in; the first step that passes is kept, so the text is as close to the
chosen color as the contrast allows, and a color that already passes is used as it is. Deriving the
colors, instead of asking for three, keeps the choice to one click and keeps any color, a custom
one included, readable in both appearances.

The default reproduces the colors from before the choice existed exactly: `#E6B04A` fill,
`#1D1B18` label, `#E6B04A` dark text, and `#9A6B12` light text. The rule itself would give
`#9B6D15` for amber's light text (about 4.6:1); `#9A6B12` was picked by hand earlier, reads at
about 4.7:1, so it meets the same bar, and `AccentPalette` keeps it for amber so the default look
does not move.

### Where the accent and the appearance come from

`CountersignPalette`'s three members are computed from `AccentTheme.shared.palette`, an
`@Observable` main-actor holder, and `CountersignPalette.use(_:)` replaces it. SwiftUI records the
read of that observable property in every `body` that reads a palette member, so replacing it
redraws each view that uses the accent. A panel's `PanelController` calls `use` with
`Settings.accentColor` when it is created, so a panel reads the accent once per request, like its
other settings. The Settings window's model calls it whenever it loads `config.json`, when it
opens, after each write, and when the window becomes key and the file has changed, so the window
follows a change at once, including one made in the file by hand. While a custom color is being
picked, the model calls it with each color the color panel sends, before that color is written (see
"Writing a change" in [settings.md](settings.md)).

`appearance` sets `NSWindow.appearance` on the panel (`ApprovalPanel`, when `PanelController` is
created) and on the Settings window (whenever its model loads `config.json`):
`NSAppearance(named: .aqua)` for Light, `.darkAqua` for Dark, and `nil` for System, so the window
follows macOS again. Everything inside, `accentText` and every system color included, resolves
against that appearance. The handoff backdrop draws only a black dimming layer, the same in either
appearance, so it is left alone.

Deny stays red (`DestructiveButtonStyle`) whatever the accent. Every other filled button uses `PrimaryButtonStyle`'s accent
fill: none of them takes the system accent, which is no agent's color either. The menu-bar icon is
a monochrome template image and takes neither the accent nor the appearance choice.

## The permission mode chip

`default` is what every Codex request and most Claude requests already carry in
`permission_mode`, so a chip that showed it on every panel would just be noise. `PanelRootView`'s
header only renders the mode chip when `ApprovalCore.PermissionModeDisplay.forMode(_:host:)`
returns non-nil: `default`, an empty string, and a missing field all return nil. The five modes
Claude Code is known to send besides `default` — `plan`, `acceptEdits`, `bypassPermissions`,
`dontAsk`, `auto` — each get a short plain-words label and a hover card that explains what the mode
actually does, since "acceptEdits" or "dontAsk" mean nothing to someone who hasn't read Claude
Code's own docs. Any other value falls back to showing the raw string with a hover card naming the
reporting host, so a future or unknown mode still surfaces instead of being silently dropped.

The chip explains itself with `.hoverCard` (`HoverCard.swift`), not `.help`. `.help` is AppKit's
own tooltip mechanism, and AppKit only shows a tooltip for the active app, which the panel never is
(see "Never activating"): on screen on 2026-09-24, hovering a mode chip that used `.help` showed
nothing, ever. `.hoverCard` uses the same `.onHover` state plus `.overlay` pattern as "The waiting
list" uses for the "+N" chip's dropdown — plain, non-focusable `Text` in a `VStack`, never a
`Menu`, `Button`, popover or second `NSWindow` — so the explanation actually renders.

## The subagent chain in the header

A single `subagent · <agentType>` chip says a subagent is asking, but not what it or its ancestors
are actually doing, which matters most for a subagent spawned by another subagent. `PanelModel`
receives the `ApprovalCore.SubagentChainReader.chain(transcriptPath:agentID:)` result from its
caller (see "Walking the subagent chain" in [hosts.md](hosts.md)): `HookRunner`, `preview` and
`snapshot` each compute it once per request and hand the same chain to the panel header and to
the ticket summary's task description, so nothing walks the files twice. The walk is meta-first:
`parentAgentId` in each `agent-<id>.meta.json` names the next hop, a meta without it and with
`spawnDepth` 1 ends the chain at the main session, and only an older or inconsistent meta falls
back to searching transcripts. The cost is one small meta read per level, not a full transcript
read per level and sibling.

The header shows only the agent that is asking, the one whose answer this panel actually records;
its parents are context, and context is a hover away. One crumb per agent, from the depth-1 root
down to the one asking, does not fit: on screen on 2026-09-24, with a two-level chain, a project
name and the chips all present at once, that read `Claude Code › sho… › Mo… › Ver…` — the project
name and both crumbs squeezed to about three characters each, unreadable. `PanelRootView`'s 640 pt
single-row header cannot hold a whole chain plus the mark, the project name and the
mode/Snooze/waiting chips at any useful width.

When the chain resolves, the header reads `Claude Code › <project> › … › <asking label>`: the
`…` appears only when the chain has more than one link, and a depth-1 agent (asking directly, no
parent) shows `<project> › <asking label>` with no ellipsis at all. `<asking label>` is the
chain's last link — its task description, falling back to its agent type when the description is
empty. Losing the chain — a missing file, a missing field, a parse failure anywhere from the
requesting agent up to the root — still falls back to the `subagent · <agentType>` chip instead of
showing a broken or partial chain, and a non-subagent request still shows no crumb at all.

Sizing follows an overflow order rather than one flat rule. The mark, host name, chevrons, `…`,
the mode chip, Snooze and the waiting chip keep their natural width always (`.fixedSize()`) and
never give up room. Of the two remaining texts, the asking label shrinks first — `.frame(minWidth:
60)`, `.lineLimit(1)`, `.truncationMode(.tail)`, left at the default `.layoutPriority` — and only
once it is already at that 60 pt floor does the project name start giving up its own width, from
a `.layoutPriority(1)` (higher than the asking label's default 0, so `HStack` protects it longer)
down to a floor of `min(naturalWidth, 80)`, where `naturalWidth` is
`(text as NSString).size(withAttributes: [.font: …])` at the header's 13 pt medium
(`PanelRootView.naturalWidth(of:)` and `projectNameFont`, whose one caller is this floor). The
floor has to be a `min`, not a flat 80 pt: `shop-api` is 54 pt natural, and a flat
`.frame(minWidth: 80)` pads it out to 80 pt anyway, opening a ~26 pt blank gap between the name and
the next `›`. The order comes entirely from those two `.layoutPriority` values and the two
`.frame(minWidth:)` floors; nothing in `PanelRootView` measures a header row's total width by hand.
The project name has no fixed width cap. It does truncate, but only as the last resort once the
asking label has already given up everything its floor allows.

The waiting chip is compact (`+2`, not `+2 waiting`), and so is Snooze (the `moon.zzz` symbol
alone, with a `.hoverCard` reading "Snooze", since the word itself has nowhere to go), so the asking
agent gets that width in the one-row header instead. Measured on the real fixture (`shop-api`, a
two-link chain ending in "Verify checkout totals", `acceptEdits`, Snooze, "+2") at the panel's
640 pt width: the mark sits flush at 20 pt from the leading edge and the waiting chip's trailing
edge lands at 620 pt (40 px and 1239–1240 px in a 2× snapshot, measured with a pixel scan), so the
full 20 pt of padding survives on both sides. The fixed elements, the 11 × 8 pt gaps, and the
project name at its natural 54 pt (well under its 80 pt floor, so `min(naturalWidth, 80)` renders
it at its own 54 pt with no padding) leave the asking label 122 pt to work with, rendered from the
snapshot as "Verify checkout to…" — short of the label's full 135.44 pt. With both chips spelled
out, the same fixture eats into that padding and pushes the asking label down to its 60 pt floor,
and with a flat 80 pt floor padding `shop-api` the label gets 101.5 pt. A depth-1 request ("Move
discounts to tiered pricing", no `…`) does not reach its floor either. Only a project name far past
any reasonable length —
`an-extremely-long-project-folder-name-for-this-header` — still exhausts the asking label down to
its 60 pt floor; `min(naturalWidth, 80)` there is 80 (its several-hundred-point natural width is
nowhere near the floor), yet the project name renders at about 117 pt, not 80. The 80 pt is the
least it keeps, not a width it is pushed to: with the asking label already at its 60 pt floor and
the `Spacer` between the mode chip and Snooze at its own 8 pt minimum, the project name simply
takes the roughly 117 pt of the row that is left over once everything else has claimed its share —
the `Spacer` is not holding any of that back.

### The chain card

Hovering the asking label, or the `…` when the chain has more than one link, opens a single chain
card listing every link from the root (depth 1) down to the one asking, numbered by depth, rather
than a hover card with only the asking agent's own `<agentType> · <description>`. The card is drawn
with the same `HoverCardBody` as `.hoverCard` (see "The permission mode chip" above for why hover
cards replace tooltips). Rows wrap and never truncate, since the whole point of the card is to show
what a truncated or omitted crumb in the header cannot.

This card hangs below the header aligned to the header's own leading content edge — the same x
position "Claude Code" starts at — not to whichever element was hovered, so it never runs off the
panel regardless of how far right the asking label or the `…` sits. `PanelRootView` tracks one
`isChainCardHovering` flag for the whole header (set from either hoverable element's `.onHover`)
and renders the card in an `.overlay(alignment: .bottomLeading)` on the header's own `HStack`,
before its horizontal padding is applied — the padding then shifts card and content by the same
20 pt, so the card's leading edge lands exactly where the content's does.

## The waiting list

The waiting chip reads just "+N", not "+N waiting" — the one-row header needs the width more than
the word does — and what is actually waiting is listed in its dropdown. `WaitingChipView` (`WaitingListView.swift`) wraps the same `Chip` and adds a
read-only dropdown that lists it: host, project, tool, and the subagent (its task description,
falling back to its agent type, `TicketSummary.agentLabel`, which the menu-bar companion's pending
list reuses) when the ticket has one, in queue order (oldest first unless a Show Now from the menu
bar moved one) — one row per `WaitingEntry`
in `PanelModel.waitingEntries`, the same array the chip's own count comes from (see "Listing
waiters, not just counting them" in [queue.md](queue.md)). An entry whose ticket could not be
decoded still gets a row, "Unknown request", rather than vanishing from the list: the count and the
row count must always agree, since a person seeing "+3" and counting two rows in the dropdown would
reasonably wonder where the third request went. `DisplayWatch` refreshes that array on every tick,
and `SnapshotCommand`/`PreviewCommand`'s `--waiting N`
build `N` synthetic entries from the request itself so the chip keeps rendering the same way
offscreen.

The dropdown opens on hover and closes the instant the pointer leaves the chip; a click while
hovering toggles it shut without having to move the mouse, and the next hover reopens it. It is
plain `Text` rows inside a `VStack`, not a `Menu`, a `Button`, or a second `NSWindow`: nothing in
it is focusable and nothing about showing it can make it, or anything in it, the key window, which
matters because the panel already owns the keyboard for the request itself (see "Keyboard alert
without activation" above) and a popover that grabbed key status would fight it. `.allowsHitTesting
(false)` on the list itself keeps it inert to clicks.

Two things about the list's own SwiftUI layout are easy to get wrong and worth naming. First,
`PanelRootView`'s outer `VStack` puts `header` before `content`, and later siblings paint over
earlier ones wherever they overlap; a `.zIndex` on the dropdown itself only orders it among the
chip's own overlay layer, not against `content`, which sits in a different part of the tree
entirely. What actually keeps the dropdown from being painted over by the request body underneath
it is `.zIndex(1)` on `header` itself, in `PanelRootView`'s `VStack` — that lifts the whole header,
overlay included, above `content` regardless of declaration order. Second, an `.overlay` is
proposed its base view's size, not its own ideal size, so a `.frame(maxWidth:)` on the dropdown
only ever caps it — squeezed to the width of the chip it hangs off, every row would truncate to a
character or two. `WaitingListView`
uses `.frame(width: 300, alignment: .leading)` instead, an explicit width the view reports
regardless of what its parent proposed, so its rows get the space they need and the dropdown's
trailing edge still lines up with the chip's own trailing edge (`.overlay(alignment: .topTrailing)`
on the chip, offset down by 30 pt to clear it).

None of this — hover, the click toggle, whether the popover ever steals focus, or the dropdown
actually opening — shows up in an offscreen `countersign snapshot`, which has no pointer to hover
with; only the chip's rendered count is checked that way normally. Checking the dropdown's layout
offscreen means temporarily forcing `WaitingChipView`'s `isHovering` to start `true`, rendering,
and reverting the forcing before committing — not a path this codebase wires up permanently, since
`isHovering` driven by a real `onHover` is what keeps the list from ever appearing without a real
pointer over the chip.

## The arm lock

Panels answer one queued request at a time, and the previous panel's rects can sit exactly where
the next one appears. Without a lock, a click or a keystroke timed for the panel that just closed
can land on the panel that just opened, approving or denying something the person never read.
`PanelController` disables every action for `armDuration` after `show()` and `PanelModel.finish`
re-checks `isArmed` itself, so even a key or `cancelOperation` that somehow gets through early is a
no-op.

`armDuration` is a `PanelController` init parameter, clamped to `0...3` seconds and defaulting to
0.8. `hook`, `test-panel` and `preview` feed it the `armDelay` resolved from the config file (see
[configuration.md](../configuration.md)), except that `hook` feeds a panel shown after a queue handoff the
`chainedArmDelay` instead, 0.1 s by default; `countersign snapshot` never reads that file, so it
always renders at the built-in default. `0` means the panel arms the instant `show()` runs, with no
lock and no line.

A chained panel needs less because the lock guards against a different mistake there. A panel that
appears after the idle gate lands in front of someone whose attention may be anywhere: a click
aimed at the app underneath, or a Return on its way to it, must not answer a request nobody has
read, so the lock is long enough to see the panel arrive. A chained panel appears because the
person just answered the previous one, with a key or a click on that panel: their eyes and hands
are already on the panel, and it replaces the one they were reading, in the same place. What is
left to stop is the answer itself carrying over: a Return pressed twice, or a second click on the
same spot, within a fraction of a second of the answer. The shorter lock swallows whatever of that
reaches the new panel while it lasts, and every key and click in the lock is consumed without
effect, as on any panel. A lock of the full `armDelay` on every panel in a run of queued requests
would make each one wait for no reason.

A key held down from the answer is not covered by the lock itself. Its auto-repeat starts after the
system's "Delay until repeat" and goes on for as long as the key is held, and the key monitor does
not tell a repeat from a fresh press by timing alone, so a Return held past the end of the shorter
lock could otherwise act on the new panel with its own repeats, where the full `armDelay` would
have swallowed a hold of up to that long. `KeyRouter.route` closes that gap directly instead of
widening the lock: it swallows a repeated Return or Esc outright (see "Return, Esc and the other
keys"), on every panel and at either delay, so a hold never carries an action across the handoff.
`PanelModel` carries the clamped value and its `isArmed` flag so the view layer can react to both
without knowing about `PanelController`'s timer.

While the lock holds, `PanelScaffold` draws a thin progress line that fills over `armDuration`
with a linear animation. `PanelController.show()` starts it by calling `model.startArming()`, in
the same call that starts its own timer for the same duration, and the scaffold starts the
animation from `onChange` of `model.hasStartedArming`, not from its own `onAppear`. `onAppear`
fires on the view's first layout pass, and a panel shown after a queue handoff is built and laid
out before it is shown, usually while its hook waits in line, which can be minutes earlier (see
"Warm standby and the queue handoff" in [queue.md](queue.md)), so a line started there would be
partly filled, or full, by the time the panel appears. Nothing about arming starts
before `show()`: not the timer, not the line, not `isArmed`. The line disappears once
`model.isArmed` flips to `true`; if `armDuration` is `0` it never shows at all, since the animation
never starts and the model arms within the same `show()` call. `countersign snapshot --unarmed`
renders the dimmed, locked footer with the line empty, since the snapshot never calls `show()`.

Because the panel is key the moment it appears, the lock is also what stops a stray keystroke. A
Return already on its way to the person's app when the panel took the keyboard lands in the panel
instead. The key monitor consumes it, and it does nothing. It neither approves nor passes through
to the app underneath. A letter on its way the same way makes the panel step aside, and is
swallowed too.

## No default button

No button carries `.keyboardShortcut(.defaultAction)` or any other shortcut. Return is handled
explicitly: the key monitor asks the visible view state for its primary action (see "Return, Esc
and the other keys"). A shortcut attached to a button can fire from a state that is in the tree
but hidden, and it can race a second binding for the same key. Asking the one view that knows
which state is visible fires exactly one action, and only once the panel is armed.

## Why "Answer in chat" returns no decision

Claude and Codex both keep their own chat surface live while a hook is pending. "Answer in chat"
lets the person switch to that surface instead of using the panel, so the panel must get out of the
way without recording an opinion: it calls `finish(.noDecision)`, which encodes to no output at
all, leaving the underlying tool-call `PermissionRequest` unanswered for whichever surface resolves
it next.

Cursor reads empty output as "carry on as usual", which under its auto-run runs the command without
asking. For Cursor, `.noDecision` therefore encodes to `{"permission":"ask"}`, which makes Cursor
show its own approval prompt: still no opinion, and the same outcome the other hosts get from an
empty reply (see "What each answer prints" under "The Cursor adapter" in [hosts.md](hosts.md)).
Antigravity gets `{"decision":"ask"}` for the same reason (see "What each answer prints" under
"The Antigravity adapter" in [hosts.md](hosts.md)).

## Handing back before Cursor's timeout

Nothing is decided by a timeout, and that holds for Cursor too, but Cursor makes it take one more
step. Cursor lets a command run when its hook times out, so a Cursor panel left unanswered until
the entry's 3600-second timeout would approve by silence. The Cursor hook hands back instead: 60
seconds before that timeout, 3540 seconds after the hook started, `HookRunner` prints the same
`{"permission":"ask"}` that "Answer in chat" prints, logs `handed back: cursor timeout near`, and
exits 0. `TimeoutHandBack.isDue(host:elapsed:)` is checked in the grace loop, in the queue's
`shouldAbandon` closure and on every `DisplayWatch` tick, after the abandon check, so a request
that was answered in the meantime still ends silently. On screen, the hand-back closes the panel
and hands the display to the next request in line, as an answer would. Antigravity does not
document what a hook timeout does, so its hook hands back the same way, printing
`{"decision":"ask"}` and logging `handed back: antigravity timeout near`. Claude Code and Codex
never hand back: a hook timeout already gives them their own prompt. The constants and the
reasoning are in "Handing back before Cursor's timeout" in [hosts.md](hosts.md).

## Questions and plans

### Why tabs

`AskUserQuestion` can carry up to four questions in one request, and showing them all at once
inside a 640 pt panel would force either tiny option rows or a scroll well past what fits on
screen. `QuestionView` shows one question at a time behind header chips, so each question gets the
full width and height budget the panel allows, and the chip's checkmark gives an at-a-glance answer
count without needing to visit every tab.

### Why the key monitor skips the field editor

`PanelController`'s local key monitor maps bare digits and the arrow keys to option picks and tab
moves so a reviewer working through several questions never has to leave the keyboard. But "Other"
and "Notes" are free-text fields, and a person typing a digit or an arrow key into either one means
exactly that character, not a shortcut. The monitor checks whether `panel.firstResponder` is an
`NSTextView` whose `isEditable` is true, which holds while the field editor owns first responder,
i.e. while a text field is being edited. When it does, every key but Return and Esc passes through
untouched, digits, arrows and letters alike, and nothing steps aside. A read-only, selectable
text view can also become first responder when clicked; it is not a field being edited, so the
digit and arrow shortcuts and the step-aside rule still apply there. Return and Esc are the
exceptions.
They keep their panel meaning inside a field, so Return in the deny reason sends the denial, and
Return in Other or a note submits or moves to the next unanswered question.

Any tab switch, whether by Return, Next, a chip or an arrow, clears `QuestionView`'s `focusedField`.
Otherwise the Other or note field of the question just left would stay first responder while
hidden, and the next question's digit shortcuts would go to it.

### Why no text field starts focused

`show()` calls `panel.makeFirstResponder(nil)` right after `makeKey()`. Without it, AppKit would
hand first-responder status to the first key-view-loop-eligible control, almost always a text
field, which would swallow every digit and arrow key meant for answering questions, and would
turn every plain key into typing in that field instead of a step-aside. With it, the panel itself
holds first responder: the probe read `ApprovalPanel` at show, one second later, and again after a
forced second `makeKey()`, for both a permission and a question panel. The key monitor's keys work as soon as the panel is armed, and a text field gets
focus only when the person clicks into it or when the deny or feedback state opens.

### Other is selected by focus, not by typing

`OtherCard` labels its field "Your own answer" and a placeholder that names the choice it stands
in for — "Type an answer instead of picking one" for a single-select question, "Type an answer to
add to your picks" for a multi-select one — since a bare "Other…" placeholder gives no hint that
this is a free-text alternative to the option cards above it, or what typing into it would do to
an already-picked option.

Selection follows focus, not keystrokes. `QuestionView.markOtherFocused(index:question:)` runs
the moment `OtherCard`'s field gains focus (watched via `.onChange(of: focus.wrappedValue ==
field)`): it sets `otherSelected` immediately, and for a single-select question also clears
`selectedOptions`, so clicking into Other visibly deselects whichever option card was picked before
a single character is typed. `QuestionView.clearOtherIfBlank(index:)` runs the moment focus leaves,
including a tab switch (`focusedField` is cleared on every switch, see "Why the key monitor skips
the field editor" above): if the field's text is blank after trimming, `otherSelected` goes back to
`false`. A single-select option cleared on focus is not restored by this; leaving Other empty
clears the free-text choice without silently reinstating the old pick. `otherTextBinding` still
sets `otherSelected` and, for a single-select question, clears `selectedOptions` on every non-blank
keystroke — the field keeps focus while an `OptionCard` button is clicked (`pickOption` runs and
re-picks an option without moving focus out of Other), so relying on the focus handler alone would
let both an option and Other read as selected at once. `otherTextBinding` does not deselect Other
on an empty string, though: that is the blur handler's job, since selection follows focus. None of
this touches `QuestionResponse.isAnswered`: an `Other` that is selected but blank does not count as
answered, since that check requires non-blank trimmed text on top of `otherSelected`.

### How a multi-select answer is joined

`QuestionResponse.answerText` joins a multi-select answer's labels, in option order, with a chosen
Other answer last, using `", "`. This mirrors how `AskUserQuestion`'s own multi-select answers read
in the transcript today, so the panel's answer looks like something the person typed by hand rather
than a machine-joined list — to be confirmed against a live multi-select turn, since this is
inferred from the single-select shape rather than observed directly.

### Why the approve mode is sent as `setMode`

`ExitPlanMode`'s allow decision does not carry a dedicated "which mode afterward" field; the only
channel Claude Code reads for that is `updatedPermissions`, the same array `permission_suggestions`
already populates for other tools (see `PermissionView`'s "Allow and switch to acceptEdits"
suggestion, which is exactly a `setMode` entry). `PlanResponse.approve` sends one `setMode` entry
with `destination: "session"` so the mode change applies only for the rest of this session, not
written into a settings file the person didn't ask to change.

## The permission view

### Two footer states, not a wall of buttons

`PermissionView`'s footer holds only two states, switched by a local `PermissionFooterState`
rather than any request field: `.default` holds "Answer in chat", "Deny" and Approve; clicking
"Deny", or pressing ⌫, swaps the whole footer for `.deny`, a reason field plus "Deny", "Deny & stop"
(only when `host.supportsInterrupt`) and "← Back". Nothing about the
request or the outcome changes between the two states — only what's visible — so "← Back" is a
free, lossless move that keeps whatever reason text was already typed. The reason field,
`TextField(axis: .vertical)`, takes focus the moment the footer switches to `.deny` and gives it
up on "← Back" (see "Keeping the layout still when the content changes" for why this is
`onChange` rather than `onAppear`).
`PlanView`'s feedback field does the same when "Keep planning" opens it, whether by click or by ⌫,
so Return there sends the feedback and Shift+Return starts a new line.

No button carries a keyboard shortcut. Return commits the visible state: Approve (allow once) in
`.default`, Deny with the typed reason in `.deny`. ⌘Return does the same in `.deny` when
`host.supportsInterrupt` is false; otherwise it fires Deny & stop instead. In `.default`, ⌘Return
opens Approve ▾ when the request has suggestions (see "The Approve button and its ▾" below), and
otherwise does the same as Return. ⌫ opens the reason or feedback step from `.default` — see
"Return, Esc and the other keys" for the full key. `PermissionView`'s `keyHandler` reads
`footerState` when the key arrives, so the hidden state can never be the one that fires.

### The Approve button and its ▾

Approve is a `PrimaryButtonStyle` button that allows once, its own full rounded pill. When
`permission_suggestions` is non-empty, a second control sits beside it: a `chevron.down` and a
"⌘⏎" keycap in `LinkButtonStyle`, no fill, the same pattern as "Answer in chat"'s "esc" keycap.
Clicking it, or ⌘Return while `.default` is visible, opens Countersign's dropdown (see
"Countersign's own dropdown" below) with "Allow once" plus one row per suggestion. Codex, Cursor
and Antigravity requests never populate `permission_suggestions`, so the ▾ control simply never
appears — no host check needed, the suggestions array already carries that distinction.

A suggestion's row shows the exact rule and where it is saved, from
`ApprovalCore.PermissionSuggestionText`: an `addRules` entry's title is `<toolName>(<ruleContent>)`,
or just the tool name when the content is missing or empty, several rules joined with ", "; an
`addDirectories` entry's title is "Allow access to <dir>". The second line comes from
`destination`: `localSettings` "This project, on this Mac", `projectSettings` "This project,
shared", `userSettings` "All projects", `session` "This session", and none for anything else. Any
other entry type keeps its `label` (see "How suggestion labels are built" in
[hosts.md](hosts.md)) with no second line. The exact rule is the point: a rule for one exact
command does not cover a different one, and the old one-line label hid the rule well enough that a
different command asking again looked like the rule had not been saved.

### Countersign's own dropdown

The three menus inside a panel, Approve ▾, the header's Snooze and the plan's "then: mode", are one
`PanelDropdown` drawn inside the panel, not an `NSMenu` and not a child window. A native menu is its
own window with its own keyboard handling: it takes keys away from the panel's monitor and draws
in the system's look, not the panel's. The dropdown is a SwiftUI overlay on `PanelRootView`, so the
panel keeps the keyboard and the one accent.

- **State.** `PanelModel.dropdown` is a `PanelDropdownState`: the open `PanelDropdownMenu` (its
  id, direction, rows and `onPick`) and an `ApprovalCore.DropdownNavigation`, which holds the
  highlighted row, wraps ↑ and ↓ around the ends, and maps the digits 1 to 9 to the first nine
  rows. At most one dropdown is open; its anchor button toggles it. Each open starts a fresh
  `DropdownNavigation`, on the first row, or on the checked row for the plan's mode, as a macOS
  pop-up button does.
- **Placement.** Each anchor button reports its bounds with `anchorPreference`
  (`PanelDropdownAnchorKey`), and `PanelRootView`'s `overlayPreferenceValue` resolves them in its
  own coordinates. Footer dropdowns open upward, the header's Snooze downward, both with the card's
  trailing edge on the anchor's. The card hugs its rows' natural width, at least 200 pt, and wraps
  text at the space left of the anchor's trailing edge.
- **Staying inside the panel.** The overlay sits inside the panel's `clipShape`. When the card
  would come closer than 8 pt to the panel's top or bottom edge, the layer reports a floor, and
  `PanelRootView` applies it as a `minHeight` (at most `maxHeight`), so the panel grows and the
  footer moves down with it. The floor is measured from the edge the anchor is pinned to, the
  footer's distance from the bottom or the header's from the top, so growing does not change it.
  Once the panel has settled it never shrinks (see "Keeping the layout still when the content
  changes"), so it keeps the grown height after the dropdown closes.
- **Look.** A card like a question's option cards: the panel's surface, `Color.primary` at 4%
  over it, a 1 pt stroke and the hover card's shadow. The highlighted row is tinted with
  `CountersignPalette.accentText` at 16%; hovering a row highlights it, so the mouse and the
  arrows share one highlight. Each of the first nine rows shows its digit as a `KeyHint`. The mode
  dropdown marks the current mode with an `accentText` checkmark.
- **Closing.** Picking a row closes the dropdown before its action runs. Esc, a click anywhere
  in the panel outside the card (a clear full-panel layer under the card catches it, so the click
  does nothing else), or a click on the backdrop outside the panel closes only the dropdown; the
  next Esc or backdrop click answers in the chat as usual.
- **Arm lock.** The rows are disabled before the panel is armed, and `KeyRouter` swallows the
  dropdown's keys then, so nothing is picked during the lock.

### Gaps expand from the side nearest the change

`FileDiffBuilder`'s `.gap` segments arrive as a flat run of unchanged lines with no indication of
how a person wants to read them, so `NumberedDiffCard` decides based on the gap's position among
its file's segments: a gap at index 0 has no visible segment above it, so every reveal grows only
from the bottom, nearest the change that follows; a gap as the last segment grows only from the
top; anything in between grows from both ends at once. `GapRevealState.reveal(current:total:position:)`
turns one click into up to 30 more visible lines — 30 from the single active side for an edge gap,
15 from each side for a middle one — and keeps doing that on every subsequent click until nothing
hidden remains, at which point the row simply stops rendering. "Show all" skips the increments
entirely and sets `fromTop` to the segment's full length in one write, which is enough on its own
to cover every line regardless of how much was already revealed from either side. The state lives
in `NumberedDiffCard` itself, keyed by segment index, not in `PermissionView`: each file's diff card
is a distinct view identity in the `ForEach`, so SwiftUI already keeps their expansion states apart
without a compound key.

The row's wording comes from `FileDiffBuilder.gapTitle(hiddenCount:of:)`. A gap of context lines
reads "Show N unchanged lines". The rest of a created or deleted file past its first 40 lines is
also a `.gap`, but every line in it is added or removed, so it reads "Show N more lines", never
"unchanged". Both forms say "line" for one.

### Falling back when the file can't be read

`FileDiffBuilder.load(for:)` returns `nil` for the whole request when any file in it can't be
diffed against the real file on disk (see "Files that are not diffed" below). `PanelModel` loads
that once at `init`, into `fileDiffs`, and `PermissionView` branches on it for edit, write and
patch alike: loaded renders `NumberedDiffCard` per file; `nil` falls back to the request's own
before/after strings — `PatchParser.diff` for an edit, the first 40 lines of `content` for a
write, `PatchParser.files` for a patch — rendered through `UnnumberedDiffCard`, the same row
styling minus the numbered gutter, since there's no real line number to show. A caption,
"Showing the change only — the file couldn't be read.", sits under the fallback so the absence of
line numbers reads as a deliberate signal rather than a rendering gap.

A fallback card starts at the change's first line, with no placeholder row above it:

- **Collapsing an edit's context.** `PatchParser.diff` keeps 3 unchanged lines next to each change
  and folds the rest of a run into one "N unchanged lines" row, but only when that row replaces
  at least 4 lines (`minimumCollapsedLines`). A shorter run shows in full, since a row standing in
  for one or two lines costs as much space as the lines. Without that minimum, the
  `claude-edit.json` fixture would open with a "1 unchanged line" row in place of its first line.
- **Codex hunk headers.** `PatchParser.files` strips git-style ranges (`-a,b +c,d @@`) from an
  `@@` line and keeps what follows as the hunk's anchor, as in Codex's `@@ class Foo`. An anchor
  becomes a separator row, including one above the first hunk. An `@@` with no anchor, bare or
  range-only, becomes the neutral `…` separator, and only between hunks. At the top of a file it
  adds no row, so neither a leftover range such as `-0,0 +1,2 @@` nor a lone `…` sits above the
  first line.
- **After the patch.** `*** End Patch` closes the last file, so blank lines after it never become
  context lines of that file. An added file's content skips separator rows.

### Diff text is a TextKit 2 view per run

Diff lines are not SwiftUI rows. One row per line, an `HStack` of four `Text`s (old number, new
number, marker, code), makes thousands of views for a long file: scrolling lags (see "Profile"
below), and the text looks soft, since SwiftUI draws `.primary` and `.tertiary` text over the
panel's material with vibrancy, which blends the glyphs with the blur behind them.

`DiffRunView` (`DiffRunView.swift`) draws them instead. It is an `NSViewRepresentable` around
`DiffRunHostView`, which holds one `NSTextView` created with `usingTextLayoutManager: true`, not
editable, selectable, and plain text (`isRichText = false`).

**Runs and gap rows.** A run is a stretch of consecutive visible lines between gap rows. It covers a
`.visible` segment together with the lines a neighbouring gap has already revealed above or below
its row, so selection flows across a reveal boundary. `NumberedDiffCard` builds the list of runs
and gap rows from its segments and `GapRevealState`. A gap row ("Show N …", "Show all") stays
SwiftUI with the reveal rules above. Once a gap is fully revealed, its row disappears and the runs
on either side merge into one. `UnnumberedDiffCard` uses the same view with only the marker
column. Its `.collapsed` rows are SwiftUI separator rows between runs.

**The gutter is outside the text.** The text view starts at the code column: 8 pt of padding, two
34 pt number columns, and a 14 pt marker column in the numbered card, or 8 pt and the marker column
in the fallback card. Its text storage holds only the code lines, each ending in `"\n"`.
`DiffRunHostView` draws the full-width row tints and the gutter (numbers in 11 pt monospaced, the
`+`/`-` marker in 12 pt) itself in `draw(_:)`, on the first line of each row only. Selecting and ⌘C
copy only code, lines joined with `"\n"`, and a selection that reaches the end of a line includes
that line's newline, as in any editor. Long lines wrap inside the text view, so continuation lines
start at the code column and never widen the panel.

**Row geometry.** The text container has no line fragment padding. The text view has a 1 pt top and
bottom inset, and each paragraph has 2 pt of spacing after it. A row spans from its first line
fragment's top minus 1 pt to its last line fragment's bottom plus 1 pt, read from the TextKit 2
layout fragments. That gives each row 1 pt of vertical padding and lets the row tints tile with no
seam. The empty line fragment TextKit adds after the final newline is dropped.

A row is not always one layout fragment. `TextLine.split` breaks only on `"\n"` and strips only a
trailing `"\r"`, so a line can still hold a bare `"\r"` or U+2029, and a file with classic Mac
CR-only line endings arrives as one line holding every `"\r"`. TextKit starts a new paragraph, and
so a new layout fragment, at each of them. `DiffRunHostView` therefore keeps each row's end offset
in the text storage (the running sum of each line's UTF-16 length plus its `"\n"`), assigns every
layout fragment to the row its start offset falls in, and spans that row from its first fragment's
top to its last fragment's bottom. The gutter numbers and marker stay on the row's first line, its
tint covers every paragraph it holds, and the run's height reaches the last fragment. The
characters are never rewritten, so selection and ⌘C still copy the line exactly as it is in the
file. A `"\r"` at the very end of a line's text joins the appended `"\n"` into one `"\r\n"`
separator, which still ends the paragraph at the row's end.

**Height.** `sizeThatFits(_:nsView:context:)` takes the proposed width, lays the whole run out at
that width (`enumerateTextLayoutFragments` with `.ensuresLayout`), and returns the last row's
bottom. The result is cached per width and recomputed when the lines change. `PanelScaffold`'s
`fixedSize` measurement, `PanelController.applyHeight` and the snapshot's settle loop therefore all
see the wrapped height. A gap reveal changes a run's lines, SwiftUI calls `sizeThatFits` again, and
the panel grows. A snapshot probe that revealed every gap 60 ms after the first layout confirmed it.

**Scrolling.** The panel's SwiftUI `ScrollView` is an `NSScrollView` (`HostingScrollView`), so the
text view finds it as its enclosing scroll view, and TextKit 2 renders only the fragments in the
visible viewport as it scrolls. `DiffRunHostView` draws only the rows that intersect the dirty rect.

**Colors.** The code text, gutter and tints are explicit sRGB colors picked for the view's
appearance (`DiffRunPalette`), and both views return `false` from `allowsVibrancy`. Light: text
0.12 gray, numbers 0.66 gray. Dark: text 0.90 gray, numbers 0.45 gray. The tints are the system
green and red for each appearance at 13% opacity. The text colors are opaque, so the
glyphs do not blend with the material behind them.

**Focus.** The text view never takes first responder on its own. `show()` leaves the panel itself
as first responder. A click in a run selects text and makes the text view first responder.
It is not editable, so the key monitor keeps treating Return, Esc, digits and arrows as panel keys.
⌘C is a modified key, so the monitor passes it through to the text view.

**Profile.** A 2,000-line edit (250 eight-line blocks, one wrapping line in each), rendered as a
single fully visible run through the panel's `ScrollView` in the offscreen snapshot window, 3 runs
each:

| | SwiftUI rows | TextKit 2 run |
| --- | --- | --- |
| First layout, until the height settles | 3,590–3,710 ms | 97–104 ms |
| First draw | 267–287 ms | 16–17 ms |
| 50 scroll steps, layout and draw each | 10,171–10,572 ms | 611–623 ms |
| Mean scroll step | 203–211 ms | 12.2–12.5 ms |

## The context checkpoint panel

`ContextCheckpointView` shows a `ContextCheckpointPrompt`: the session's context has crossed a
rung of the configured ladder and the person picks what Claude should do about it. It lives in the
same `PanelScaffold` as the other views, with the question view's option cards (`OptionCard`).

**Layout.** The headline is `Context ~<tokenText> tokens`. Under it the ladder reads `Soft`,
`Status` and `Insist` with each rung's threshold from `prompt.ladder`; the rung that fired is drawn
in the accent and the other two are secondary, so the person sees how far along the ladder the
session is. One line per level says why the panel appeared. When `PanelModel.sessionIdle` is true a
caption adds that Claude is idle and the choice reaches it with the next message: a note added to
an idle session is only delivered when the person types again, and the panel says so instead of
implying an immediate reaction. Four cards follow, numbered 1 to 4 (Continue, Compact after this
step, Hand off & start fresh, Not this session), each with a one-line description. The footer is one
primary button titled with the highlighted choice.

**Keys.** 1 to 4 and ↑/↓ move the highlight; Return and ⌘Return perform the highlighted choice
(⌘Return has no menu here, so it does what Return does); Esc and a click outside answer "no
decision", which is Continue. Delete is not used. Digits move the highlight rather than performing
the choice, so a mistyped digit is never an answer; a click on a card performs it. The arm lock
applies as for every panel: `chooseCheckpoint` is guarded the way `finish` is.

**The highlight rule.** The starting highlight is `ContextCheckpointChoice.highlighted(for:)`:
Compact after this step for the soft and status levels, Hand off & start fresh for insist. The
highlighted card is what Return does, so the default follows how urgent the level is.

**Why choices go through `chooseCheckpoint`.** Not this session must mute the session, yet its
outcome is `.noDecision`, the same as Continue and Esc; the outcome alone cannot tell them apart.
The view therefore never calls `finish` for a choice: it calls `PanelModel.chooseCheckpoint(_:prompt:)`,
which reports the choice through `onCheckpointChoice` and then finishes with
`choice.outcome(for: prompt)`. The runtime uses the callback to persist the mute. Esc and click
outside call `finish(.noDecision)` directly and are never a mute.

**What the panel cannot do.** It cannot run /compact or /clear; those are the person's commands. It
steers Claude with a note, and Claude's reply tells the person what to run.

**Test panel and snapshots.** `countersign test-panel context` shows the sample: a soft checkpoint
at the first million-window threshold plus 12,345 tokens, on the configured 1M ladder, with the
configured handoff file and notes. `countersign snapshot --test-panel context` builds the same
sample from the defaults, never the config file, and `--checkpoint-level soft|status|insist` picks
the level (tokens are that level's million-window threshold plus 12,345, and the highlight follows
the level). A context test panel logs `test panel: chose a context note` when a note was chosen and
`test panel: continued` for no decision.

## Size limits

### The panel never exceeds its max width or height

`PanelController` computes `panelWidth = min(PanelMetrics.width, targetScreen.visibleFrame.width *
0.9)` and `maxPanelHeight = targetScreen.visibleFrame.height * 0.8`, and hands both down through
`PanelRootView`. The root view's outermost `.frame(width:)` is a hard constraint no descendant can
widen: every `Text` that renders request-controlled content (a shell command, a code block,
pretty-printed JSON, a markdown paragraph, a patch anchor) carries `.fixedSize(horizontal: false,
vertical: true)`, which tells it to accept the width its container proposes and wrap or grow
vertically instead of requesting its own unbounded ideal width. Diff lines are not `Text`: a
`DiffRunView` takes the proposed width as its own and wraps inside it (see "Diff text is a TextKit
2 view per run"). Nothing in the tree uses `fixedSize` on the
horizontal axis, and there is no horizontal `ScrollView` anywhere, so a 300-character unbroken
token (a base64 blob, a long query string) wraps mid-token within the panel's width rather than
pushing the window wider or spilling past its edge.

### Fixed header and footer, scrolling body

`PanelScaffold` (`PanelStyle.swift`) is the shared layout every request kind renders through:
`PermissionView`, `QuestionView`, and `PlanView` each split into a `body` (their scrollable
content) and a `footer` (their action row), and none of them owns a `ScrollView` itself.
`PanelRootView` owns the header above the scaffold. None of the three pieces — header, the
body's ideal height, and the footer — can be sized from a plain SwiftUI layout pass: the header's
height depends on the chips it renders, the footer's on how many buttons a request
kind shows, and the body's ideal height on content nobody can predict at compile time. Each is
measured with a `GeometryReader`-in-background view, via the `reportHeight` helper.

`PanelRootView` subtracts the measured header height from `maxPanelHeight` and passes the
remainder to `PanelScaffold` as `availableHeight`. `PanelScaffold` then gives its `ScrollView` a
height of `min(bodyIdealHeight, availableHeight - footerHeight)`: a short body gets a short
`ScrollView` with no wasted space below it, and a tall body gets a `ScrollView` clamped to
whatever room is left after the footer, which stays fully visible and un-scrolled beneath it.
Because the `ScrollView`'s height is derived from `availableHeight` rather than left to grow with
its content, header height plus `ScrollView` height plus footer height can never exceed
`maxPanelHeight`: there is no path where the panel's content is taller than its window, so a long
plan's text is never cut off mid-line with no way to scroll to the rest. The body content inside the `ScrollView` additionally carries
`.fixedSize(horizontal: false, vertical: true)` before `reportHeight` reads it, so the
`GeometryReader` always measures the content's own natural height, never the `ScrollView`'s
(possibly still-unsettled) constrained frame.

### The window follows the measured content, not `fittingSize`

Reading `hostingController.view.fittingSize` after forcing a couple of `layoutSubtreeIfNeeded()`
passes is fundamentally circular for this layout: the `ScrollView`'s own
frame is `.frame(height: scrollHeight)`, and `scrollHeight` is computed from `@State` that starts
at zero and is only filled in by the *next* render once the preference chain reports real numbers.
`fittingSize` measures the tree as it is laid out right now, so on the pass where `bodyHeight` is
still its zero starting value, `fittingSize` faithfully reports a `ScrollView` framed to zero —
header plus footer, no body — and nothing forces a second `fittingSize` read after the state
catches up. A window sized that way comes out as a compact strip with the header and footer rows
and no visible body for any fixture long enough that `scrollHeight` has to clamp.

Two more things compound this. First, `PreferenceKey` values from a `GeometryReader`-in-background
were found not to reliably propagate to an ancestor `.onPreferenceChange` in this specific setup —
verified by instrumenting both the `GeometryReader` itself (which does compute the correct size,
confirmed via `onAppear`) and every `.onPreferenceChange` between it and the root (which never saw
anything but the key's default value, indefinitely). Second, where that sizing does happen to land
correctly, it comes from `NSHostingController`'s own implicit content-size tracking, not from
anything this code controls, so it cannot be made to respect `maxPanelHeight`'s 80% clamp for long
content.

Height measurement uses no `PreferenceKey` at all. `reportHeight` (`PanelStyle.swift`) is a plain
closure: `.background(GeometryReader { proxy in Color.clear.onAppear { perform(proxy
.size.height) }.onChange(of: proxy.size.height) { _, new in perform(new) } })`. A closure call is
ordinary Swift code, not a value relayed through SwiftUI's preference-diffing machinery, so it runs
every time regardless of whichever internal pass computed it. `PanelScaffold` uses it locally to
fill its own `bodyHeight`/`footerHeight` `@State`, which drives `scrollHeight`.
`PanelRootView` uses it for the header, and — as the very last modifier on its fully composed
view, after the background, `clipShape`, and border `overlay` — for the panel's total rendered
height, calling `model.onPreferredHeightChange?(min($0, maxHeight))` on every change. Since that
total already reflects `PanelScaffold`'s own clamped `scrollHeight`, no separate "ideal body
height" needs to cross the `PanelScaffold` boundary, and its `init(model:availableHeight:body:footer:)`
takes none.

`PanelController` wires `model.onPreferredHeightChange` in `init` to a private `applyHeight`, which
recomputes `panelWidth`/`maxContentHeight` for the target screen, clamps the reported height to
`maxContentHeight` (never below 1 pt), and calls `panel.setFrame` re-centered on the screen's
`visibleFrame` — every time the closure fires, not once. `show()` also forces two
`layoutSubtreeIfNeeded()` passes (`layOut()`) before ordering the panel front, as a best-effort head
start, but correctness does not depend on them settling anything: the panel starts at
`alphaValue = 0` and the first real `applyHeight` call — driven by the same run loop that pumps the
0.15 s fade — lands before or during that fade, never at full opacity, so no wrong-sized frame is
ever visible.

A panel shown after a queue handoff has no fade to hide behind, so it relies on the head start
instead: the hook builds its `PanelController` and calls `layOut()` while it waits next in line,
or when the handoff arrives if that prepared panel cannot be reused, in both cases before it has
the lease, and `show()` lays it out again (see "Warm standby and the queue handoff" in
[queue.md](queue.md)). Measured offscreen with a release build, a controller built that way
without being shown, over nine fixtures from a one-line command to a long edit, a long plan and a
set of questions: the panel's frame had its final height after that first `layOut()` in every case
and did not change over twelve more 10 ms run-loop turns with a `layOut()` after each. What the
first on-screen frame looks like has not been checked on screen.

### Keeping the layout still when the content changes

Centering the whole header+content block inside `maxHeight` with SwiftUI's default `.center`
alignment would leave a visible failure mode: whenever the composed view is briefly proposed a
taller height than its own natural content — most plainly, right after a state change shrinks the
natural content but before `applyHeight` has resized the window to match — the shorter content
renders centered inside the stale, taller box, showing equal blank bands above the header and below
the footer, with both jumping on the next such change. `PanelRootView`'s outer `.frame(maxHeight:
maxHeight, alignment: .top)` and `content`'s own `.frame(maxHeight: .infinity, alignment: .top)`
pin the header to the top edge and let the scaffold's `ScrollView`, not the outer block, absorb any
such slack: `PanelScaffold`'s `VStack` gets the same `.frame(maxHeight: .infinity, alignment: .top)`
and its `ScrollView` layers `.frame(minHeight: scrollHeight, maxHeight: scrollHeight)` under
`.frame(maxHeight: .infinity, alignment: .top)`, so the footer — a fixed-height sibling right after
it — always renders at the bottom of whatever height the block is given, and any extra room shows up
purely as blank space in the body, below the content, never outside the header/footer band.

This only closes half the gap, since it does nothing to stop the underlying content height from
actually changing between states. `QuestionView` renders every question's body inside one
`ZStack(alignment: .topLeading)`, one `questionBody(index:)` per question, with every non-selected
body at `.opacity(0)`, `.allowsHitTesting(false)`,
`.accessibilityHidden(true)`. A `ZStack` takes the size of its tallest child regardless of which one
is visible, so `PanelScaffold`'s measured `bodyHeight` reflects the tallest question from the very
first render and never changes when `selectedIndex` changes — switching tabs is purely a visibility
swap, with the shorter selected question's content sitting top-leading inside the reserved space and
any leftover height showing as blank body beneath it. `PermissionView`'s `.default`/`.deny` footer
and `PlanView`'s default/feedback footer use the same trick, one level up: both states render inside
a `ZStack(alignment: .bottom)`, the hidden one invisible and non-interactive the same way, so
`footerHeight` is already the taller state's height before "Deny" or "Keep planning" is ever
opened, whether by click or by ⌫, and opening either never resizes anything. Because both states
are permanently in the tree, anything bound to a hidden button could still fire. That is one
reason neither Return nor ⌫ is a `.keyboardShortcut` but a question put to the view about which
state is visible (see "Return, Esc and the other keys"). `PermissionView`'s Approve and Deny
buttons, and `PlanView`'s Approve button, also add `footerState`/`showingFeedback` to their
`disabled` condition, so no other route, such as
Full Keyboard Access, reaches a hidden button either. The auto-focus of `PermissionView`'s reason
field and `PlanView`'s feedback field is driven by `.onChange` of the footer state, not
`.onAppear`, which fires only once at first mount, since the second footer is permanently in the
tree. The field takes focus on the transition into its state and gives it up on the way back.

None of this stops height from changing for reasons that are genuine, not a same-panel state
switch — a `NumberedDiffCard` gap reveal, typing enough text to wrap the deny reason field or a
question's Other field to another line. For those, `PanelController.applyHeight` enforces two more
rules on top of the 80%-of-screen clamp. First, while the panel is up its height may only
grow, never shrink: `lastAppliedHeight` is threaded through every call and the applied height is
`max(clampedDesired, lastAppliedHeight)`. Second, once a height has been applied the panel's top
edge (`topEdgeY`, an AppKit y-coordinate: `origin.y + height`) is fixed, and growth extends the
window downward from it — `y = topEdgeY - height` — shifting the panel up only as far as needed to
keep its bottom inside `visibleFrame`. Both rules are gated on `hasSettled`, true once at least
`settleWindow` (0.2 s — the 0.15 s fade plus headroom for one more run-loop turn) has passed since
`show()`: `reportHeight`'s very first calls fire while the tree is still mid-layout (a header-only
height from the first pass is a real, observed value, not a hypothetical one) and racing to lock
`topEdgeY` onto one of those would anchor far from center once the true height arrived a moment
later, growing downward from the wrong place instead of settling in the middle of the screen. Before
`hasSettled`, every call re-centers on both axes; only once it's true
does the first call fix `topEdgeY`, and every call after that grows from it. Since the panel is
still fading in from `alphaValue = 0` (per "The window follows the measured content" above) for
most of the first `settleWindow` seconds, none of this settling shows as a jump — grow-only and
top-anchoring only ever apply to changes a person can actually see happening on an already-visible
panel. A panel shown after a queue handoff is at full opacity from its first frame, but in every
fixture measured its height had already settled offscreen before `show()`, leaving nothing to
re-center.

## File context

### The file on disk is the before-state

`PermissionRequest` fires before the tool runs, so whatever is on disk is exactly the `old_string`
side of an Edit or the pre-image a Codex hunk expects to match. `FileDiffBuilder` reads that file
and builds a real, whole-file line diff instead of the bare `old_string` → `new_string` snippet the
request carries, so the reviewer sees the change in the shape of the actual file rather than in the
shape of the tool call.

The file is read once, when the panel is built (`PanelModel.fileDiffs`), and a panel on screen is
not refreshed if the file changes under it. A panel prepared while its hook waits in line is built
early, possibly minutes before it shows, and the file can change in that time: the person edits
it, another session writes it, a formatter runs. So when a queue handoff would reuse that panel,
the hook runs `FileDiffBuilder.load(for:)` again first and compares the result; any difference
means the prepared panel is thrown away and a new one is built from the file as it is now,
logged as `queue handoff: prepared panel rebuilt (file changed)` (see "Warm standby and the queue
handoff" in [queue.md](queue.md)). The head's own edit is not one of those changes: its decision
reaches the host only when its hook exits, after the handoff, so the host has not run that tool
yet when the next panel reads the file.

### The enclosing-block heuristic

Showing the whole file for a one-line change is noise; showing only the changed lines strips the
context a reviewer needs to judge whether the edit is safe. `FileDiffBuilder` instead finds, for
each maximal run of changed lines, the smallest enclosing block by indentation: it walks upward
from the run to the nearest less-indented, non-blank line (the block's header) and downward to the
first line whose indentation returns to the header's level, keeping that closing line only when it
looks like a closer (`}`, `]`, `)`, `end`, `fi`, `done`, `esac`). Tabs count as 4 columns of indent
so tab- and space-indented files compare consistently. Everything the heuristic does not select
becomes a `.gap` segment carrying its own lines, so the UI can expand it locally without re-reading
the file.

### Multi-line signatures

A function whose parameter list spans several lines closes with a line like `) -> DisplayLease? {`,
and that closing line is itself less indented than the body, so it is exactly what the header walk
above finds first: a "parent function" made of only its last line, with the `func waitForDisplay(`
line the reviewer actually wants cut off. `visibleRange(for:in:)` corrects this once the ordinary
header is found: if that header's trimmed text starts with a closing bracket (`)`, `]`, or `}`),
`findSignatureStart` walks further upward from it to the nearest earlier non-blank line at the
*same* indentation whose trimmed text is not itself a closer, and that becomes the header instead.
This is the same walk that turns a `} else {` header into its `if` line, since the two cases are
the same shape: a closer standing in for a block whose real opening is further up at its own
indent. The walk is bounded by the same `enclosingBlockSearchLimit` as the original header search,
measured from the change to the resolved header, so a signature (or an if/else) that starts
implausibly far away still falls back to the original, unextended header rather than reaching
arbitrarily far up the file.

### Fallbacks and the ±2 floor

The heuristic only fires when it has something to anchor to. A top-level change (indent 0), a
header that never resolves, or a header/footer more than 60 lines from the change all fall back to
a flat ±4 lines of context instead of guessing at a block that isn't there. Independent of which
path was taken, the visible range is always widened to at least ±2 lines around the change; this
can pull in one extra line past a heuristic-found boundary that sat closer than that, which is
deliberate — a block header with zero lines of breathing room either side reads as a mis-detection.

### Files that are not diffed

Files over 2 MB or 20,000 lines are too large to diff usefully inline: `edit` and `patch` return
`nil` for them (the UI falls back to the request's own `old_string` → `new_string` diff, see
"Falling back when the file can't be read"), and `write` falls
back to showing the new content alone as `.created` rather than attempting a diff against content
it won't scan. A Codex `.update` hunk that can't be located as a contiguous run in the real file —
context has drifted, or the file changed since the hunk was generated — also returns `nil` for that
file, and `load(for:)` propagates that `nil` to the whole request rather than showing a partial,
possibly misleading set of diffs.

### Lines and the final newline

`TextLine.split` is the one place text becomes lines for display: created, deleted, written, edited
and patched files, the Claude edit fallback, and the write preview. A terminating newline ends the
last line. It never starts another one, so a 7-line file that ends in `"\n"` shows 7 lines, not 7
and an empty eighth. An empty text has zero lines, so writing into an empty file shows only added
lines, with no removed empty line 1. `"\r"` before a newline is dropped, and the check looks at the
last Unicode scalar, because Swift treats `"\r\n"` as one `Character`.

Each `TextLine` also records whether it ended with a newline, and both diff walks compare that
along with the text. Lines in the middle always end with one. So when only one side's last line
has a newline, that line shows as removed and added, as git does, with no "no newline at end of
file" marker row. Otherwise the two last lines match as usual.

`applyingHunks` splits the real file the same way, applies the hunks, joins with `"\n"` and adds the
final newline back only if the real file had one and the result still has lines. So a Codex update
never shows a newline change the patch did not make.

## Visual language

`PanelStyle.swift` is the one place hierarchy gets decided, so `QuestionView` and `PlanView` both
render through it rather than styling their own buttons and rows. Four rules keep the three
request kinds reading as one product:

- **The accent is the only strong color.** The accent, amber unless `accentColor` picks another,
  from `CountersignPalette` (see "Countersign's mark and one accent"), is kept for the few things
  that want attention — the
  waiting chip, the selected question tab, an option card's selected stroke and indicator, a plan's
  bullet dots and numbered-item digits, a diff's "Show …" rows, the arm lock's progress line and the
  primary button's fill — so a glance finds what needs a decision. Everything else stays on the
  `Color.primary` / `Color.secondary` opacity scale already established by `CodeCard` and `Chip`.
- **One primary action per state.** Each footer has exactly one `PrimaryButtonStyle()`
  button — Submit, Approve — and in the default state it is also what Return fires. Two filled
  buttons fighting for the eye make the flat grey rows around them read as noise; a single
  accent-filled action avoids that without inventing a second visual weight class.
- **Secondary actions are links, not buttons.** "Answer in chat", "Keep planning"'s eventual
  "Back", and the question view's "+ Add a note" all read as `LinkButtonStyle` text rather than
  bordered rectangles, because they are opt-outs or escape hatches, not choices the person is
  weighing against the primary action. Reserving `SecondaryButtonStyle`'s filled pill for actions
  that materially compete with the primary one (`Next`, `Keep planning`, `Send feedback`) keeps
  that weight class meaningful instead of applying it to everything that isn't accent-filled.
- **A key hint is a badge only where it needs one.** `AnswerInChatButton`'s "esc" is a `KeyHint`
  with `placement: .link`: an outlined rounded-rectangle badge that hugs its text. The outline
  exists because the link has no fill of its own — a bare "esc" sitting
  next to "Answer in chat" would read as one more word in the sentence rather than a keyboard
  shortcut. The `⏎` and `⌫` hints inside the filled Approve/Deny/Submit/Send/Keep-planning buttons
  stay a plain glyph with no outline (`placement: .onAccent`/`.onDestructive`/`.onSecondary`): the
  button's own fill already sets them apart, so a second border would be redundant. Every button
  label that pairs a `Text` with a `KeyHint` — `AnswerInChatButton`, Approve, the default footer's
  Deny, the reason step's Deny, Keep planning, Submit and Send feedback — centers the hint on the
  label text's cap-height midline (baseline minus half the text font's cap height,
  both read from `NSFont`) with the shared `.keyHintMidline` alignment guide and the
  `keyHintTextGuide(capHeight:)`/`keyHintGuide()` helpers in `PanelStyle.swift`, rather than
  `HStack`'s default `.center`, which aligns the two views' line-height boxes and leaves the hint
  sitting visibly high against the text. Each `ButtonStyle` publishes a `labelCapHeight` matching
  its own label font (`PrimaryButtonStyle` and `DestructiveButtonStyle` at 13 pt semibold,
  `SecondaryButtonStyle` at 13 pt medium, `LinkButtonStyle` at 12 pt regular), so a label at a
  different size never borrows another style's cap height.
- **Reveal-on-demand for text inputs.** A field that is empty and irrelevant most of the time —
  the question view's note, the plan view's feedback text — starts hidden behind a link and only
  takes up footer or body space once the person asks for it or has already typed into it. This is
  why `QuestionView` tracks `notesExpanded` per question instead of always showing the notes field,
  and why `PlanView`'s footer swaps to a feedback state instead of keeping a feedback `TextField`
  permanently docked next to Approve.

## Accessibility

The panel is shortcut-driven and non-activating, so VoiceOver reaches it through announcements and
the accessibility tree rather than through a Tab loop. `PanelAnnouncement` in `ApprovalCore` holds
every string that is pure logic, so the wording is tested.

What VoiceOver hears:

- **On show.** `PanelController.show()` gives the panel the accessibility title "Countersign
  approval", posts `focusedUIElementChanged` on the hosting view so the panel's content is the
  VoiceOver focus, and posts a high-priority announcement with a one-line summary, from
  `PanelAnnouncement.text(for:)`: host, project and, for a subagent, "subagent <type>", then what
  is asked, for example "Claude Code, countersign: asks permission to use Bash", "asks a question",
  "asks 2 questions", "proposes a plan" or "suggests a context checkpoint".
- **During the arm lock.** The primary button (Approve, Submit, the plan's Approve, the checkpoint's
  choice) has the accessibility value "Not available yet" while the panel is unarmed, and the
  panel announces "Ready" once when the lock ends. With no arm delay there is nothing to wait for
  and nothing is announced.
- **Shortcuts.** `KeyHint` chips are hidden from the tree, so a chip is never read as a stray
  glyph. Each button, option card and dropdown row carries the shortcut as its accessibility hint
  instead: "Shortcut: Return", "Shortcut: Command-Return", "Shortcut: Delete", "Shortcut: Escape",
  "Shortcut: 1".
- **Choices.** An `OptionCard` is one element (`.combine`) with the selected trait on the chosen
  card and its indicator glyph hidden. A question tab reads "Answered" once it has an answer and
  carries the selected trait when current. A dropdown row is a button; the highlighted row has the
  selected trait and the checked row's value is "Current".
- **Chips.** `Chip` has an explicit label ("Test panel", "Subagent <type>", "Permission mode:
  <mode>") and hides its symbol. The "+N waiting" chip is a `Button`, so VoiceOver and the keyboard
  can open the list; it is labelled "N waiting" and its hint says whether the list is open.
- **Diffs.** `DiffRunHostView` draws its gutter itself, so it exposes one accessibility element per
  row instead of the text view. `DiffLineSpeech` builds each label: "Added, line 12: <text>",
  "Removed, line 11: <text>", "line 4: <text>" for context, and no line numbers in the
  marker-only gutter. The gap button's icon is hidden and its label is its title.
- **Decoration.** Chevrons, `doc.text`, the plan's bullet dots and rules, the Countersign mark and
  the arm line are hidden.

Reduce Motion: with `accessibilityDisplayShouldReduceMotion` the panel does not fade in, and with
the SwiftUI `accessibilityReduceMotion` environment value the arm line jumps to full instead of
growing across the arm delay. The arm lock itself still lasts the full delay.

Increase Contrast: with `colorSchemeContrast == .increased`, the hairlines and card borders that
are `primary` at 8 to 12% (the panel, code cards, diff cards, the deny reason field, hover cards,
the waiting list and dropdown cards) use `PanelBorder`, which draws `primary` at 50%, about 4:1 on
either panel background. The orange shell-flag colour, `#FF9500` on light and `#FF9F0A` on dark,
does not reach 4.5:1 on a code card (`#F2F2F2` and `#292929`), so it is replaced by
`PanelContrast.increasedContrastOrangeLight` and `increasedContrastOrangeDark`: the orange
darkened, or lightened, in the same 0.005 HSL steps as the accent's text colours until it reaches
4.5:1 against the card.

Known limit: there is no Tab loop. The panel owns the keyboard through its key monitor, so VoiceOver
navigates it with its own cursor and presses controls with VoiceOver's press command, while every
action also has its shortcut. Dynamic Type is not supported.

## Snapshots

`countersign snapshot` renders a request's panel to a PNG without putting anything on screen, so
layout work can be checked by builders, agents and scripts while the person keeps working:

```sh
swift build
.build/debug/countersign snapshot <request.json> --host claude|codex|cursor|antigravity \
  [--waiting N] [--appearance light|dark] [--accent #RRGGBB] [--unarmed] [--question-notes] \
  [--open-menu approve|snooze|mode] -o <out.png>
```

`--open-menu` renders the panel with one of its dropdowns open (see "Countersign's own dropdown"),
as a click on its button would open it: `approve` for Approve ▾, `snooze` for the header's Snooze,
`mode` for a plan's "then: mode". `PanelModel`'s `openDropdownOnAppear` asks the view that owns
that button to open it when it appears, so the rows, the highlight and any growth of the panel are
the ones the screen shows. A panel without that button, such as `approve` for a request with no
suggestions or `mode` for anything but a plan, is an error with exit status 1.

It draws the same `PanelRootView` the panel shows, with the same model, and changes nothing about
the on-screen path. It is a separate subcommand, never reachable from `hook`, and it behaves like
an ordinary CLI: usage and errors go to stderr with exit status 1.

A test panel's sample (see "The test panel") takes the place of the request file:

```sh
.build/debug/countersign snapshot --test-panel command|question|plan \
  [--waiting N] [--appearance light|dark] [--accent #RRGGBB] [--unarmed] [--question-notes] \
  [--open-menu approve|snooze|mode] -o <out.png>
```

It builds the request with `TestPanelSample.request(for:)` and the model with `isTestPanel` set, so
the image has the "Test" chip and never the chat-tracking warning, exactly as `test-panel` shows
it. `--test-panel` cannot be combined with a request file or `--host`; the other flags work as for
a file, and `--question-notes` shows the question sample as it looks with `questionNotes` on.

The settings window (see "The window" in [setup.md](setup.md)) has a mode of its own:

```sh
CLAUDE_CONFIG_DIR=<dir> CODEX_HOME=<dir> XDG_CONFIG_HOME=<dir> \
  .build/debug/countersign snapshot --settings \
  [--home <dir>] [--show-changes claude|codex|cursor|antigravity] [--show-copies] \
  [--status active|paused|paused-until-open|quiet] [--size <width>x<height>] \
  [--tab agents|panels|app|advanced] [--restore-prompt panels|app] \
  [--explanation <preferenceName>] [--appearance light|dark] -o <out.png>
```

It builds the window's `SettingsModel` exactly as the window does, reading the hosts' files and the
config file through those variables. So the image takes the file's `accentColor`, and, unless
`--appearance` overrides it, the file's `appearance`, as the window would. Cursor and Antigravity have no such variable, so their rows
always read the real `~/.cursor/hooks.json` and `~/.gemini/config/hooks.json`, read-only like
everything else here — unless `--home <dir>` is given: it builds `SettingsEnvironment.current(home:
dir)` instead of `SettingsEnvironment.current()`, which roots `AppPaths` and every host's
`HookConfigLocation` (claude, codex, cursor and antigravity alike) under `dir` and ignores
`CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `XDG_CONFIG_HOME`, so a snapshot can show all four hosts as set
up against a made-up home with nothing read from the real one. `resolvedExecutable` and the
`stablePath` derived from it still come from the running binary regardless of `--home`, since they
describe the binary taking the snapshot, not a host's config; a host row whose "Show changes" is
expanded still renders that real path in its diff, `--home` does not cover that case. It draws
`SettingsRootView`, the
window's root view, the same way as the panel below: `.prohibited` activation policy, a borderless
`defer: true` window never ordered in, `cacheDisplay` into a 2× bitmap. `--show-changes`, which
may be repeated, opens
that agent's "Show changes" under Agents as a click would.

The notice about a second installed copy (see "More than one copy" in [settings.md](settings.md))
comes from the same files on disk. Without `--home`, the snapshot looks at the real
`/opt/homebrew`, `/usr/local`, `/Applications`, `~/.local/bin` and `~/Applications`, like the
window, including its `--version` probe of an installer copy without its app. With `--home <dir>`,
it looks at `dir/.local/bin` and `dir/Applications` for the home
paths, and reads the three system paths under `dir/root/` instead, `dir/root/opt/homebrew`,
`dir/root/usr/local` and `dir/root/Applications` (`SettingsEnvironment.current(home:)` sets that
root), so a demo layout can hold any combination, and a home with nothing there shows no notice
whatever the machine has installed. The `root` folder keeps `/Applications` apart from
`~/Applications`, which would otherwise be the same folder, `dir/Applications`. Paths under the
root are shown and written into the removal command without it, as
`/Applications/Countersign.app`, so the image reads as on a real Mac. Fake files are enough: a text
file at `.local/bin/countersign`, and an `Info.plist` holding `CFBundleShortVersionString` in
`Applications/Countersign.app/Contents/` or `root/Applications/Countersign.app/Contents/`. Whoever
builds the layout may not be able to make symbolic links; Homebrew's copy takes its version from
what `opt/countersign` resolves to, so a Homebrew copy made of plain files shows "version unknown".
With `--home`, the snapshot never runs a demo `countersign --version`, so an installer copy
without its app shows "version unknown" too. The running binary is never one of the demo's
copies, so the kept copy is the one a demo hook entry names, or none. `--show-copies` opens the
notice's "Show copies" as a click would, when there is a notice.

The header's pause and snooze controls never read the real pause switch or quiet-time file, which
have no variable to redirect them: they show the active state (no caption) unless `--status` picks paused, paused until
Countersign opens (the pause the companion's quit question sets, see "Quit" in [app.md](app.md)),
or quiet time ending 15 minutes after the snapshot is taken.
`--tab` picks the group the sidebar shows — `agents`, `panels`, `app`, `help` or `advanced` —
`agents` when it is left out, and never reads or writes the group the window remembers (see
"Groups and layout" in [settings.md](settings.md)). Without `--size`, the image is the window's
default width, 820 pt, and as tall as the whole page: the header, the sidebar and the selected
group, measured with `SettingsHeader` and `SettingsContent` at that width in the same settle loop
as the panel, so everything that group would scroll to in the window is in the PNG. `--size
<width>x<height>`, in whole points no smaller than the window's minimum of 680 × 480, renders the
window's content at exactly that size instead: the sidebar keeps its width whatever `--size` asks
for, and the content scrolls when it overflows, the same as the real window. Any other value of
either flag is a usage error. Either way the hosting view has no sizing options, as in the window, so
the image is exactly the size asked for. Nothing is written: the model writes only when a control
is used, an agent's or a test panel's button is clicked, "Open in Editor" is chosen, a text field
disappears or the window closes, and offscreen nothing is clicked, typed, switched or closed. A snapshot's window is never
key, so switches that are on and the slider's filled track draw in the inactive grey rather than the accent.

`--restore-prompt panels|app`, only accepted with `--settings`, renders the group's Restore
Defaults confirmation instead of the window itself: it builds the model from `--home`'s config
exactly as above, then draws `RestoreDefaultsPrompt.makeAlert(pane:lines:)`'s alert content view
the same way `--quit-prompt` draws the quit question's (see below), so the wording of a group's
reset confirmation can be checked without opening the window or clicking Restore Defaults. `--size`
and `--tab` are ignored when it is given, since there is no window content to size or select a
group in.

`--explanation <preferenceName>`, also only accepted with `--settings`, renders a `PreferenceName`'s
info popover instead of the window: `SettingsExplanationView`'s content view alone, sized to its own
fitting size rather than the window's, since a real `.popover` draws chrome and an arrow that only
exist once AppKit itself positions and orders in a popover window, which this command never does. It
needs no `--home` and reads no config, since `explanation` and `defaultText` depend only on the name
and the built-in defaults; `--home`, `--tab`, `--size`, `--status`, `--show-changes` and
`--show-copies` are all ignored when it is given.

The menu-bar companion's quit question (see "Quit" in [app.md](app.md)) has one too:

```sh
.build/debug/countersign snapshot --quit-prompt [--appearance light|dark] -o <out.png>
```

It builds the alert with `QuitPrompt.makeAlert()`, the factory the companion shows, calls
`layout()`, and draws the alert window's content view the same way, never ordering the alert in and
never running it. Two things differ from the screen. The alert's background is a material that, like
the panel's, draws nothing offscreen, so the bitmap is filled with `windowBackgroundColor` first.
And its icon is the running process's application icon, which AppKit loads asynchronously, so the
command runs the run loop for a second before drawing: from `.build/debug` that is the icon of the
folder holding the binary, and only the binary inside `Countersign.app`
(`Countersign.app/Contents/MacOS/countersign snapshot --quit-prompt …`, which any argument keeps in
CLI mode) draws the Countersign icon the companion shows. The image is the alert's own size.

The menu-bar companion's manual update check (see "Update check" in [app.md](app.md)) has one for
each outcome it can answer:

```sh
.build/debug/countersign snapshot --update-answer up-to-date|available|failed \
  [--appearance light|dark] -o <out.png>
```

It builds the alert with `UpdateCheckAlert.makeAlert(for:)`, from an
`ApprovalCore.UpdateCheckAnswer` the same way the companion does, but for a fixed demo outcome
rather than a real network check: `up-to-date` is `.upToDate`, `available` is
`.newerAvailable(version: "0.2.0")` with `ApprovalCore.UpdateCommand.curlInstallCommand` as the
upgrade command and that version's release-notes URL, and `failed` is
`.unknown(reason: "HTTP 404")`. `currentVersion` is always `CountersignVersion.current`, the
version of the binary taking the snapshot, never the demo version. It calls `layout()` and draws
the alert window's content view the same way `--quit-prompt` does, never ordering the alert in and
never running it, so nothing is written to disk and no window ever shows.

The first-run tour (see "The first-run tour" in [settings.md](settings.md)) has one too:

```sh
.build/debug/countersign snapshot --tour 1|2|3|4 [--appearance light|dark] -o <out.png>
```

It draws `FirstRunTourView(step:)` alone, the same sheet content the Settings window presents,
settled the same way `--quit-prompt` and `--settings --explanation` settle: run the main run loop
in 20 ms turns until `fittingSize` stops changing, size the hosting view to that, then
`cacheDisplay` it onto a bitmap filled with `windowBackgroundColor` first, since the real sheet
draws no material of its own worth reproducing offscreen. It reads no config and needs no
`--home`, since a step's title and body come from `FirstRunTourStep` alone; the buttons render but
do nothing, since nothing here is wired to a `SettingsWindowController` to advance or dismiss.

The menu-bar status item's icon (see "The icon and the 2 s refresh" in [app.md](app.md)) has one
too:

```sh
.build/debug/countersign snapshot --menu-bar-icon active|paused|quiet \
  [--appearance light|dark] -o <out.png>
```

It draws `MenuBarIcon.image(for:)`'s tinted content, not the template image itself, onto a strip
filled with the menu bar's own background colour, `#F2F2F2` for `--appearance light` (the default)
and `#2B2B2B` for `--appearance dark`, tinted black or white to match: no `NSStatusItem`, no
`NSWindow`, and no dependence on the real menu bar's own appearance, so the two states can be
compared side by side without switching System Settings. Like the other snapshots, it renders at
2×.

The corner cards, the waiting notice and the approval card (see "The approval card"), have
`--waiting-notice` and `--approval-card`, described in "Snapshots" in [notice.md](notice.md).

### Never on screen

- `NSApplication.shared` gets the `.prohibited` activation policy, and `run()` is never called, so
  `finishLaunching` never happens. With no launch there is no Dock icon, and there is no activation
  (see "Never activating").
- The panel lives in a borderless `NSWindow` created with `defer: true` and never ordered in. No
  window-server window exists for it, and nothing can appear or take focus.
- `cacheDisplay(in:to:)` draws the view hierarchy into a bitmap in-process. Nothing reads the
  screen, so no Screen Recording permission is involved.

Rendering every fixture in both appearances left the frontmost app unchanged.

### Image size

The image is the panel's width by its measured content height. The `reportHeight` closures that
fill the header, body and footer heights need run-loop turns to settle (see "The window follows
the measured content"), so the command runs the main run loop in 20 ms turns until
`fittingSize` returns the same height three turns in a row. It then sizes the window to that
height, capped exactly as on screen: `PanelController.panelWidth(screen:)` and
`maxContentHeight(screen:)` for the display under the mouse, 640 pt wide and at most 80% of the
visible frame. The window rounds its frame to whole points, as the panel's own `setFrame` does, so a
759.2 pt cap renders 760 pt tall.

The bitmap is always 2× the point size, created by hand rather than with
`bitmapImageRepForCachingDisplay(in:)`, which follows the window's backing scale and would give a
1× image on a non-Retina display. Whether SwiftUI rasterizes text at 2× when the only display is
1× has not been checked.

### What differs from the panel

- **Material.** The panel's background is `.regularMaterial`, a blur of whatever sits behind the
  window. Offscreen nothing sits behind it, so `PanelRootView` reads a `panelSurface` environment
  value: `.material` by default, `.solid` for snapshots, which fills with `windowBackgroundColor`.
- **Arm state.** Snapshots show the armed panel, as it looks once the arm lock (see "The arm
  lock") has cleared. `--unarmed` shows the lock state instead: dimmed actions, a disabled
  Snooze button and, with `--open-menu`, disabled rows.
- **Question notes.** `PanelModel.questionNotes` defaults to `false`, matching `questionNotes`'s
  own default, since a snapshot reads no config file (see "Why snapshot never reads the file" in
  [settings.md](settings.md)). `--question-notes` sets it to `true`, so a question fixture's "+ Add
  a note" link shows the way it does with the setting on.
- **Backdrop and shadow.** Neither is drawn. The PNG is the panel alone, with transparent rounded
  corners.
- **Appearance.** `--appearance` sets the window's appearance; without it the snapshot follows the
  system setting, not `appearance` in the file.
- **Accent.** Amber, the default, since a snapshot reads no config file. `--accent #RRGGBB`
  renders the panel with that accent, as `accentColor` would (see "The three accent colors");
  anything but `#` and six hex digits is a usage error.

Keyboard, focus and animation cannot be seen in a PNG; those still need the panel on screen.
