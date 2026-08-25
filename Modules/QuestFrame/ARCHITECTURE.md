# QuestFrame architecture & bugfix notes

This file explains how the `Modules/QuestFrame` code is put together and
*why* it's built this way, plus the "why" behind the non-obvious workarounds
in it. The Lua files only carry a short pointer back here so the actual
reasoning isn't buried under long explanatory comments. Bugfix sections below
are referenced from the code via their issue number (e.g. `#161`).

## Files

- `QuestFrameModule.lua` — the whole module: the AWQ-owned quest list panel
  next to the world map, world-quest map-pin post-processing, and the Ace3
  lifecycle glue between them. It's kept as a single file (rather than split
  across several) because the two halves share state (`hoveredQuestID`,
  `filterDecisionCache`/`filterDecisionMapID`) and the taint-safety rules
  documented below apply uniformly across both — splitting it made that
  shared context and ordering harder to follow, not easier. Internally it's
  organised into `--region` blocks in a fixed order:
  - **Variables** — module-wide shared state and small helpers used by more
    than one region.
  - **QuestLog** — everything about building/laying out the AWQ quest list
    panel (`awqPanel`) and its quest/filter buttons.
  - **Taint-safe list refresh trigger** — the ticker that decides when the
    quest list needs to redraw.
  - **Player-movement show/hide trigger** — the event frame that hides the
    panel while the player is moving and brings it back when they stop.
  - **Initialization** — filter list setup, world-quest map-pin
    post-processing (`PostProcessWorldQuestPins` and its helpers), the
    taint-safe pin refresh ticker, and the Ace3 `OnInitialize`/`OnEnable`
    hooks that wire everything above together.
- `QuestFrameTooltip.lua` — the tooltip used by the quest list rows. Kept
  separate since it's a fairly self-contained chunk of tooltip-building logic
  that both the list and, indirectly, the pins care about.

## Background: why so much of this exists

Blizzard's world map/quest log code runs a lot of its own logic from inside
*secure* execution contexts (the map canvas's `secureexecuterange`, and the
pin hover/tooltip chains). Any addon code that runs as part of those chains —
an event handler, a hook, or a frame script triggered synchronously by
Blizzard's own code — gets flagged as tainted, and that taint spreads to
everything Blizzard does afterwards in the same chain. Depending on where it
spreads, this can silently blank out values (`SECRET`), block protected API
calls outright (`ADDON_ACTION_BLOCKED`), or both.

Because of this, the QuestFrame module avoids the "normal" approach of
hooking Blizzard's functions or registering for its events, and instead polls
for the state changes it cares about from isolated `C_Timer` tickers
(`InitializeListRefreshTriggers` for the quest list, `InitializePinRefreshTriggers`
for the map pins, both started from `OnEnable`). Any outgoing mutation that
could interact with Blizzard's protected/secure code is wrapped in
`securecallfunction` and, where relevant, gated behind additional safety
checks documented below.

## Issue #67 — tracking calls taint the objective tracker

`QuestUtil.TrackWorldQuest` / `QuestUtil.UntrackWorldQuest` normally end by
calling `ObjectiveTrackerManager:UpdateAll()`. When invoked from addon code,
that taints the objective tracker and can block protected actions later
(e.g. `UseQuestLogSpecialItem()`).

Fix (`ApplyWorkarounds`): both functions are overridden to drop the
`ObjectiveTrackerManager:UpdateAll()` call entirely.

Fix (`RunTrackingDeferred`): clicks that call into
`TrackWorldQuest`/`UntrackWorldQuest`/`SetSuperTrackedQuestID` — which kick
off Blizzard's objective-tracker and quest-log chains — are deferred via
`C_Timer.After(0, ...)` and run through `securecallfunction`, so they execute
in a clean context instead of the click handler's.

## Issue #147 — child-zone quest coordinates on a continent map

When placing addon-owned pins for child-zone quests on a continent map
(`AddTrackedWorldQuestPin`), quest info coming from a child map's
`GetQuestsOnMap` call has zone-space coordinates. These are projected onto
the continent via `C_Map.GetMapRectOnMap` before use, instead of being used
as-is (which would place the pin in the wrong spot).

## Cold-continent quest data (no issue number)

On a freshly opened ("cold") continent map, `C_TaskQuest.GetQuestsOnMap` for
a child zone returns nothing, because Blizzard's data provider only loads
child-zone quest data after the player has actually opened that zone's map.
`C_TaskQuest.GetQuestsOnMap(continentMapID)` is always populated by
Blizzard's `RefreshAllData` once on the continent, though, so
`GetChildMapQuests` queries child zones first (so `info.mapID` is the zone
mapID, for accurate projection per issue #147 above), then falls back to the
continent-mapID query for any quests not found that way (`info.mapID` is
then the continent mapID, which `AddTrackedWorldQuestPin` also already
handles).

The same cold-open gap means Blizzard's data provider hasn't created its pin
pool yet on a cold continent either — `PostProcessWorldQuestPins` lets that
case through anyway (rather than bailing out) since its alpha-hide passes
are no-ops with no active pins, and `dp:AddWorldQuest()` creates the pool
itself on first use from pass 3.

## Issue #156 — reward-money reads taint the gold tooltip

`DataModule:IsQuestFiltered` reads `GetQuestLogRewardMoney`. If that read
happens inside Blizzard's secure `RefreshAllData` range (e.g. from a pin
post-processing pass triggered off Blizzard's own refresh), it taints the
quest's money value and breaks the gold-reward tooltip on hover.

Fix: `QuestFrameModule:RebuildFilterDecisionCache` precomputes every quest's
filtered/not-filtered decision once per map, from a non-secure context
(`QuestLog_Update` / `RequestFullRefresh`), into
`QuestFrameModule.filterDecisionCache` / `filterDecisionMapID`.
`ShouldFilterQuest` only ever reads that cache — it never calls
`IsQuestFiltered` itself. A cache miss or stale map defaults to "not
filtered" (pin shown) until the next `QuestLog_Update` refreshes it.

## Issue #161 — tainted coroutines make UIWidget geometry reads return SECRET

Several spots avoid calling geometry-reading APIs (`GetHeight`, `GetFont`,
`GetStringHeight`, `GetWidth`) on frames that might be read from a tainted
coroutine, since those calls return `SECRET` in that case and blow up any
arithmetic done with them:

- The quest buttons: `button.Text:SetWordWrap(false)` is set explicitly so
  long titles truncate with "..." instead of wrapping. Wrapping also caused a
  layout loop: a taller button changes the available width, which changes
  whether the text fits, oscillating between wrapped and truncated states and
  producing visible flicker.
- `QuestLog_AddQuestButton` stores the title as `button.awqTitle` so
  `QuestFrameTooltip.lua`'s `Tooltip_BuildSafe` can read it without calling
  `GetText()` on a `FontString`.
- The quest list row height is hard-coded (`12pt rendered line height ≈
  14px`) instead of measured, and stored on `button.fixedHeight` so
  `VerticalLayoutFrame` can read it without calling `GetHeight()`.
- Pin filtering never calls `Hide()`/`EnableMouse()`/`SetHitRectInsets()` on
  pins (see issue #174 below for why), since that is what originally caused
  the tainted-hover chain that produced these SECRET values in the first
  place.

## Issue #166 — stale addon-added pins linger after a map change

AWQ borrows pins from Blizzard's world-quest pin pool to show child-zone
quests on continent maps. Blizzard normally releases them via
`pool:ReleaseAll()` on the next `RefreshAllData`, but on some maps (e.g. the
Eastern Kingdoms continent) its data provider returns without refreshing its
pins, so pins we added stay active and linger at their previous map's
coordinates ("out in the ocean").

Fix (`PostProcessWorldQuestPins` pass 1b): every own addon-added pin is
checked against `IsAddonPinExpected` on every refresh and re-hidden
(`SetAlpha(0)`) if it's no longer valid for the current map. The same guard
also covers a same-map stale pin, such as a super-tracked world quest pin
lingering after the quest is untracked while continent POIs are disabled. A
pin freshly reclaimed from the pool may also still be alpha-hidden from when
it belonged to a previous map, so pins we actively add always get
`SetAlpha(1)` explicitly.

## Issue #168 — taint-safe refresh triggers (ticker-based polling)

Registering event handlers for things like `QUEST_LOG_UPDATE`,
`SUPER_TRACKING_CHANGED`, `WORLD_MAP_OPEN`, etc. would run addon code
synchronously inside Blizzard's own event-dispatch chain, tainting it (see
background section above). Both the quest list and the pins instead poll for
the same state changes every 0.5s from a `C_Timer.NewTicker`, with no event
registrations at all:

- `InitializeListRefreshTriggers` polls: map opened, map display change,
  search-box text change, super-tracked quest change, quest log entry count
  change, and combat-end (forces one extra refresh in case something changed
  unnoticed during combat).
- `InitializePinRefreshTriggers` polls whether the quest map is shown and
  re-runs pin post-processing.

The two tickers are independent (they used to share one) because, since the
quest list panel is fully addon-owned, it never touches a protected call and
so never needs to check combat lockdown, while the pin code still does.

The one deliberate exception is the player-movement trigger (see its own
section below), which registers real events instead of polling.

## Player-movement panel visibility (no issue number)

While the player character is moving, the AWQ panel next to the map can be
hidden (opt-in via the `hideWhenMoving` option); when they stop, it comes
back — but only if it should be shown. Unlike the refresh triggers in issue
#168, this registers `PLAYER_STARTED_MOVING`/`PLAYER_STOPPED_MOVING` on a
hidden event frame, because those two events are dispatched by the engine
itself and are never raised inside any of Blizzard's secure execution ranges
(`RefreshAllData`, pin hover chains), so running addon code in their handlers
carries none of the taint risk #168 works around. The handlers also only
touch AWQ-owned state — the `playerIsMoving` flag and the panel — never pins
or tooltips.

Design:

- The flag always mirrors the real movement state, even when
  `hideWhenMoving` is off; the option is only consulted where the flag is
  *used*, so toggling the option mid-move takes effect on the very next
  update.
- `PLAYER_STARTED_MOVING` sets `QuestFrameModule.playerIsMoving` and, when
  the option is on, hides the panel immediately for instant feedback.
- The "should it be visible" decision lives in exactly one place:
  `QuestLog_Update`. A guard near its top keeps the panel hidden whenever
  `playerIsMoving` is set *and* the option is on, so any *other* refresh that
  lands mid-run (ticker diffs, filter changes, combat ending) cannot flash
  the panel back up while the player is still moving.
- `PLAYER_STOPPED_MOVING` clears the flag and — but only if it was actually
  set, since the event fires constantly during normal play — calls
  `RequestQuestLogUpdate()` instead of showing the panel directly, so the
  ordinary hide conditions (`onlyCurrentZone`, `hideQuestList`, zero quests
  with no filters, pvp/arena lockdown, map closed) still decide whether the
  panel returns — including cases where those conditions became true *while*
  the player was moving.
- A config callback on `hideWhenMoving` re-runs the update when the option is
  toggled, so enabling it while moving hides the panel right away and
  disabling it brings the panel back without waiting for a movement change.

## Issue #173 — pin acquisition blocked in combat

Acquiring a pin from Blizzard's pool can call protected APIs internally
(e.g. `SetPropagateMouseClicks`/`SetPassThroughButtons`), which are blocked
by combat lockdown (`ADDON_ACTION_BLOCKED`).

Fix: `QuestFrameModule:IsLockedDown` returns true during combat (and in
pvp/arena instances, which have no world quests anyway), and
`PostProcessWorldQuestPins` skips all pin work while locked down, printing a
one-time notice. Work resumes automatically once combat ends, since the
guard is re-checked every tick.

## Issue #174 — mutating pins while the cursor is over the map

Showing or repositioning a pin (`AcquirePin` → `pin:Show()`, or
`pin:SetPosition()`) makes the engine synchronously recompute what's under
the cursor and fire `OnMouseEnter`/`OnMouseLeave`, even outside of combat. If
our tainted code triggers that while the cursor is over an Area POI,
Blizzard's own hover chain (`AreaPoiUtil.TryShowTooltip` →
`GameTooltip_AddWidgetSet` → `widget:Setup`) runs tainted, and every widget
geometry read it does afterwards (`GetStringHeight`/`GetWidth`/
`GetNumPoints`) permanently returns `SECRET` — even when later called from
completely untainted Blizzard code. `securecallfunction` does **not** help
here: it only stops taint from propagating back out to the caller, it does
not give the callee itself a clean context.

Fix: `CanMutateMapPins` returns false whenever a tooltip is shown or the
cursor is over the map canvas. Only the pass that shows/moves pins
(`AddTrackedWorldQuestPin`, and pass 3 of `PostProcessWorldQuestPins`) is
gated on it; skipping is cheap and self-healing since the 0.5s ticker just
retries next tick. The passes that only change a pin's alpha
(`SetAlpha(0)`/`SetAlpha(1)`) fire no mouse events and are always safe to run
regardless of cursor position — `Hide()`, `EnableMouse(false)` and
`SetHitRectInsets()` are never used on pins for the same reason.

## Issue #156/#161 — filter cache rebuild location

`QuestFrameModule:RebuildFilterDecisionCache` is called from a
`securecallfunction` wrapper both after a full quest-log rebuild
(`QuestLog_Update`) and after a full refresh request (`TryApplyFullRefresh`),
so the reward-money reads inside it happen in a clean execution context
rather than Blizzard's secure `RefreshAllData` range.

## Misc self-healing notes

- `TryApplyQuestLogUpdate`/`TryApplyFullRefresh` both defer while
  `GameTooltip:IsShown()`, and leave their dirty flag set so the 0.5s ticker
  keeps retrying until the tooltip clears — a tooltip being up at the wrong
  moment can never leave a stale list/pin state stuck.
- `QuestFrameModule.lastRenderedMapID` is deliberately left unset when a
  refresh is skipped for a shown tooltip, so the ticker's own mapID-diff
  check re-requests the refresh until it actually applies.
- `QuestLog_Update`'s render is wrapped in `pcall` and logged via `DebugLog`
  instead of allowed to error silently, since the ticker will keep retrying
  it regardless and a silent failure would otherwise leave a stale list up
  with no visible signal.
- The per-tick pin helper functions (`ShouldFilterQuest`,
  `AddTrackedWorldQuestPin`, `GetChildMapQuests`, `GetCachedChildQuests`,
  `GetCachedChildQuestByID`, `IsAddonPinExpected`) take a per-call `ctx` table
  instead of being defined as closures inside `PostProcessWorldQuestPins`
  (which runs every 0.5s tick), so the ticker only allocates one small table
  per tick instead of half a dozen fresh closures.
