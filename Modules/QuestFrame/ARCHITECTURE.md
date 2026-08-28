# QuestFrame architecture & bugfix notes

This file explains how the `Modules/QuestFrame` code is put together and
*why* it's built this way, plus the "why" behind the non-obvious workarounds
in it. The Lua files only carry a short pointer back here so the actual
reasoning isn't buried under long explanatory comments. Bugfix sections below
are referenced from the code via their issue number (e.g. `#161`).

## Files

- `QuestFrameModule.lua` — the whole module: the AWQ-owned quest list panel
  embedded as a quest log tab, world-quest map-pin post-processing, and the
  Ace3 lifecycle glue between them. It's kept as a single file (rather than
  split across several) because the two halves share state (`hoveredQuestID`,
  `filterDecisionCache`/`filterDecisionMapID`) and the taint-safety rules
  documented below apply uniformly across both — splitting it made that
  shared context and ordering harder to follow, not easier. Internally it's
  organised into `--region` blocks in a fixed order:
  - **Variables** — module-wide shared state and small helpers used by more
    than one region.
  - **QuestLog** — everything about building/laying out the AWQ quest list
    panel (`awqPanel`) and its quest/filter buttons. The panel is embedded in
    the quest log as its own tab — see the quest log tab section below.
  - **Taint-safe list refresh trigger** — the ticker that decides when the
    quest list needs to redraw.
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

## Quest log tab (no issue number)

`awqPanel` is registered as a `QuestMapFrame` content frame behind its own
side tab, using Blizzard's generic display-mode system, rather than being a
separate window:

- `QuestLogDisplayMode` is a plain table from `EnumUtil.MakeEnum` (a
  value->key invert, so it has *no array part* — `#` is always 0), so we add
  a `WorldQuests` key with a value higher than every existing one instead of
  hooking or overriding anything. Scanning for max (rather than assuming a
  fixed slot) keeps us compatible with other addons that register their own
  tabs, however they picked their values.
- The tab is an anonymous frame inheriting `LargeSideTabButtonTemplate`,
  appended to `QuestMapFrame.TabButtons`; the panel is appended to
  `QuestMapFrame.ContentFrames` with a matching `.displayMode`.
  `QuestLogMixin:SetDisplayMode` iterates both arrays with plain equality
  checks, so no other registration is needed. Both are set up once, from
  `QuestFrameModule:InitQuestLogTab` (called from `OnEnable` via
  `InitQuestLogFrames`) — there is no user-facing way to switch the panel
  back to a separate window.
- Since `QuestMapFrame_OnLoad`'s tab-wiring loop has already run by the time
  addons load, the tab gets its own `SetCustomOnMouseUpHandler`, which also
  requests a list update immediately on selection (no polling lag).
- After switching modes we re-run SetDisplayMode's show/hide loop ourselves
  (`SyncContentFrames`): SetDisplayMode early-outs when the mode is
  unchanged, which would silently skip its ContentFrames loop and leave two
  panes overlapping. Mirroring the loop makes our pane switches
  self-healing, including for other addons' frames.
- Anchoring rule: the tab anchors below whichever tab is currently last in
  `TabButtons`. `ValidateTabs` only touches the built-in chain by parentKey,
  and other addons' tabs may already be chained after `MapLegendTab`, so
  following the array tail stacks every custom tab without overlap.
- Layout (`LayoutAwqPanel`): spans `QuestMapFrame.ContentsAnchor` (right edge
  22px in, matching every built-in pane's gutter), but the pane itself starts
  29px down rather than filling ContentsAnchor the way `QuestsFrame` does —
  mirroring `EventsFrame`/`MapLegendFrame` instead, since that reserves the
  same 29px band (still inside `QuestMapFrame`) that the relocated search box
  needs (see search box relocation below). The scroll frame fills the pane
  flush, so the `MinimalScrollBar` floats outside it in the gutter, same as
  every built-in pane. `ContentsAnchor` moving (e.g. via
  `QuestSessionManagement`) carries the pane along for free.
- Unsupported client fallback: if `QuestMapFrame.TabButtons`,
  `QuestMapFrame.ContentFrames` or `QuestLogDisplayMode` don't exist,
  `RegisterQuestLogTab` returns false and `InitQuestLogTab` just logs a debug
  message — `awqPanel` is never shown. There is no automatic docked-window
  fallback; users on such a client have to switch `panelDisplayMode` to
  `"window"` manually (see below).

Deliberate consequences of this design:

- **`SetDisplayMode` owns `awqPanel:Show`/`Hide`.** `QuestLog_Update` never
  touches panel visibility itself; hide conditions (zero quests,
  `onlyCurrentZone`, `hideQuestList`) show an empty-state text inside the
  pane instead (`SetEmptyStateVisible`/`DeactivateListPane`).
- **No taint surface added.** Registration happens once from clean
  `OnEnable` context, by inserting array entries and setting plain table
  keys — no hooks into Blizzard functions, consistent with #168. This is why
  the earlier "embed into `QuestScrollFrame.Contents`" experiment was
  abandoned but this tab approach is viable: rendering stays fully inside
  AWQ-owned widgets and never shares Blizzard's render chain.
- **Refresh gating.** Both the ticker diffs and `TryApplyQuestLogUpdate`
  skip work while our display mode isn't selected; switching back to the
  tab re-renders immediately via its mouse handler.
- Known limitation: `QuestMapFrame_OpenToQuestDetails` force-switches to the
  Quests display mode (Blizzard-hardcoded), e.g. when opening the log via a
  quest alert — users land on the Quests tab in that case.
- **Search box relocation.** In place of a "World Quests" title, `awqPanel`
  relocates Blizzard's own `QuestScrollFrame.SearchBox` onto itself
  (`MoveSearchBoxToPanel`) while our tab is the active display mode, and
  hands it back to `QuestScrollFrame` (`RestoreSearchBox`) otherwise. It's
  the literal same `EditBox` instance, not a new one, so:
  - `QuestLog_Update`'s existing `QuestScrollFrame.SearchBox:GetText()` read
    needed no changes: since that function only filters/renders while our
    tab is the active mode, the box is guaranteed (by the relocation) to
    already be sitting on our pane with "our" text at that point.
  - It's a deliberately shared instance: whatever is typed filters
    whichever list (Quests or World Quests) happens to be showing, and the
    same text is still there when you switch back. This was a user choice,
    not an oversight — an alternative was saving/restoring independent text
    per tab, but full sharing was picked for simplicity.
  - **Move/restore trigger: `awqPanel`'s own `OnShow`/`OnHide` scripts**
    (set in `InitQuestLogFrames`) are the real, synchronous mechanism.
    `awqPanel` is a genuine member of `QuestMapFrame.ContentFrames`, so both
    Blizzard's `SetDisplayMode` and our own `SyncContentFrames` mirror call
    `awqPanel:SetShown()` *directly* on it (it's not merely a descendant of
    some other frame that gets shown/hidden) — meaning `OnShow`/`OnHide`
    fire reliably the instant our display mode is (de)selected, no matter
    what triggered the change (our tab, another tab, another addon,
    `QuestMapFrame_OpenToQuestDetails`). This is what actually fixed an
    earlier version of this feature where switching *away* from our tab
    visibly hid the search box for up to half a second: `awqPanel` was
    hidden immediately by `SetDisplayMode`, but with the box still parented
    to it, and the polled ticker fallback (below) didn't restore it until
    its next 0.5s tick. `OnShow`/`OnHide` are plain script handlers on an
    addon-owned frame, not a hook into any Blizzard function, so this adds
    no taint surface (unlike hooking `SetDisplayMode` itself would).
  - Both functions are also called from a redundant, harmless-if-it-races
    fallback path: immediately from the tab's own `SetCustomOnMouseUpHandler`
    (belt-and-suspenders — `SetDisplayMode`/`SyncContentFrames` right above it
    already trigger the `OnShow` path in the same call), and from a
    `lastDisplayMode` diff check added to the `InitializeListRefreshTriggers`
    ticker (a slower, independent safety net in case the `OnShow`/`OnHide`
    mechanism is ever bypassed — polled rather than hooked, per #168).
    `MoveSearchBoxToPanel`/`RestoreSearchBox` are both idempotent, so any of
    these racing each other (or firing more than once) is harmless.
  - Blizzard's `QuestLogQuests_Update` calls `SearchBox:UpdateState()` on
    every `QUEST_LOG_UPDATE` *regardless of which tab is showing*, which
    `:Disable()`s the box whenever the normal Quests list is empty with no
    active search — a very plausible state for players who mainly do world
    quests. The ticker force-`:Enable()`s it back on every tick while our
    tab is active, so it never gets stuck uninteractable while relocated.
  - Because it's Blizzard's real box, its other native behavior still
    applies as-is: `QuestMapFrame_OnHide` clears it (and thus the world
    quest search term) whenever the map closes, and typing it still feeds
    Blizzard's own `QuestSearcher` for the Quests tab in the background.

- **Pitfall: `useAtlasSize` textures need a clipping parent.**
  `awqPaneBackground` uses the `QuestLog-main-background` atlas with
  `useAtlasSize=true` (its own fixed native pixel size) anchored by a single
  `TOPLEFT` point, exactly like Blizzard's real `QuestScrollFrame.Background`.
  Blizzard gets away with the single anchor point because that texture is a
  layer directly on `QuestScrollFrame`, a `ScrollFrame` widget, and
  `ScrollFrame`s auto-clip everything they own (own layers included, not
  just scroll-child content) to their own rect. It was first written parented
  to `awqPanel` (a plain `Frame`, which has no such clipping), so the
  texture rendered at its full native height, unclipped, past awqPanel's
  real bottom edge. Fix: parent `awqPaneBackground` to `awqScrollFrame`
  instead, so the same clipping Blizzard relies on applies here too.

- **Pitfall: tab icon dimming.** `SidePanelTabButtonMixin:SetChecked` swaps
  `activeAtlas`/`inactiveAtlas` KeyValues, but no ready-made world quest atlas
  pair exists, so `awqTab.SetChecked` is overridden per-instance to use the
  addon's own icon instead. Blizzard's own `-inactive` atlas variants aren't
  desaturated — they keep their native hue, just dimmed a notch — so an
  initial attempt using `SetDesaturated()` looked flat grey while unselected
  instead of matching the other tabs. Fix: a uniform `SetVertexColor`
  brightness multiplier, which fades the icon without touching its hue.

## Standalone window (`panelDisplayMode = "window"`, no issue number)

Some users prefer the world quest list back as its own docked window next to
the map (the layout used before the quest log tab was added) instead of a
`QuestMapFrame` content pane, e.g. because they want both the built-in Quests
tab and the world quest list visible at the same time. `panelDisplayMode`
("tab" or "window") controls this, and — unlike most other options, which are
read fresh on every render — it's a structural choice about which frame
hosts the shared list, so it's applied through a dedicated
`QuestFrameModule:SetDisplayMode(mode)` function instead of the generic
`RequestQuestLogUpdate`/`RequestFullRefresh` config-callback path.

- **Two host frames, always both created.** `InitQuestLogFrames` creates
  *both* `awqTabPanel` (the `QuestMapFrame` content pane, registered as a
  quest log tab exactly as before) and `awqWindowPanel` (a `BackdropTemplate`
  frame docked beside `WorldMapFrame`) up front, every session, regardless of
  the configured mode. Only one is ever shown at a time; the other just sits
  hidden. Building both unconditionally is what makes switching later a live
  operation — there is no lazy/on-demand creation to invoke mid-session.
- **The list itself is a single shared instance.** `awqScrollFrame` (and
  everything inside it: `awqContainer`, the filter buttons, the quest-row
  `titleFramePool`, `headerButton`) is created exactly once, initially
  parented to `awqTabPanel`. Switching modes reparents this same instance
  onto whichever host frame is now active (`SetDisplayMode`) rather than
  creating a second copy — quest rows, scroll position semantics, and filter
  button state all carry over untouched.
- **Live switching, no reload.** `SetDisplayMode` is called once from
  `InitQuestLogFrames` (applying the saved config value) and again from the
  `panelDisplayMode` config callback (see `RegisterCallbacks`) every time the
  user changes the dropdown. It tears down whatever the previous mode left
  active (`HideWorldQuestWindow`/`RestoreSideTabs` for window mode,
  `RestoreSearchBox`/`awqTabPanel:Hide()` for tab mode), reparents
  `awqScrollFrame` with mode-appropriate anchors, toggles `awqTab`'s
  visibility, and force-switches `QuestMapFrame` off our display mode if it
  was still selected when leaving tab mode for window mode (our tab button is
  about to be hidden, so nothing must be left pointing at its now-empty
  pane). `isWindowMode` (mirrored onto `QuestFrameModule.isWindowMode` for the
  refresh-trigger region outside the `QuestLog` do-block) is the single
  runtime flag every other mode-aware branch in this file reads.
- **One scroll-frame template for both modes.** `CreateFrame`'s template
  can't be changed after creation, so a single shared `awqScrollFrame` has to
  pick one template for its whole lifetime. It always uses
  `ScrollFrameTemplate` (the same one the built-in quest log panes use, with
  a `MinimalScrollBar`) rather than switching to the older
  `UIPanelScrollFrameTemplate` the pre-tab version used for the docked
  window — a cosmetic difference from the original standalone window, traded
  for not needing two separate scroll frames (and thus two separate
  containers/button pools/quest-row-building passes) kept in sync.
- **Geometry.** `awqWindowPanel` is anchored `TOPLEFT` off `WorldMapFrame`'s
  `TOPRIGHT`, sized to `PANEL_WIDTH` x `WorldMapFrame`'s height, and given the
  same tooltip-background/border `BackdropTemplate` look the pre-tab version
  used (there is no `QuestLogBorderFrameTemplate`/`QuestLog-main-background`
  chrome or empty-state text in this mode — both belong to `awqTabPanel` and
  are simply hidden, never destroyed, while window mode is active). Since
  `awqWindowPanel` is never a `ContentFrames` member, nothing else resizes it
  automatically, so `QuestFrameModule:UpdatePanelGeometry` (polled from
  `InitializeListRefreshTriggers`, same taint-safety rationale as the rest of
  that ticker — see #168) keeps its size following `WorldMapFrame:GetSize()`.
  `SetDisplayMode` clears the cached last-seen width/height when entering
  window mode so the very next tick re-applies the size instead of trusting
  a possibly-stale value from a previous window-mode session.
- **Side tabs.** `QuestMapFrame.QuestsTab`/`.MapLegendTab` visually sit behind
  a docked `awqWindowPanel`, so `MoveSideTabsToPanel`/`RestoreSideTabs`
  relocate them onto its edge while it's shown and put them back when it's
  hidden, exactly like the pre-tab implementation did.
- **Visibility is direct, not display-mode-driven.** While `isWindowMode` is
  true, every place that gates on `QuestLogDisplayMode` (`QuestLog_Update`'s
  "another tab is selected" check, the ticker's `listVisible`/
  `lastDisplayMode` bookkeeping, `TryApplyQuestLogUpdate`'s early-out) is
  skipped instead. `QuestLog_Update`'s hide conditions
  (`onlyCurrentZone`/`hideQuestList`/zero quests) call
  `QuestFrameModule:HideWorldQuestWindow()` (`awqWindowPanel:Hide()` +
  `RestoreSideTabs()`) through the shared `DeactivateListPane` helper, and
  the "should render" path `Show()`s `awqWindowPanel` and calls
  `MoveSideTabsToPanel()` through the shared `ActivateListPane` helper — the
  same two helpers the quest-log-tab mode uses to show/hide its empty-state
  pane instead.
- **No search box relocation.** `QuestScrollFrame.SearchBox` stays exactly
  where Blizzard put it; `MoveSearchBoxToPanel`/`RestoreSearchBox` and the
  search-box-`:Enable()` workaround are both skipped for this mode, since
  `awqWindowPanel` isn't occupying the built-in search box's usual home.
- **Everything else is shared.** Filter buttons, quest-row building/sorting,
  the taint-safe pin-refresh ticker (#168, #173, #174), and the
  `RebuildFilterDecisionCache`/`ShouldFilterQuest` filtering pipeline (#156)
  are unchanged between the two display modes — only panel
  creation/placement and show/hide plumbing differ.

## Hide while moving (`panelDisplayMode = "windowHideMoving"`, no issue number)

A third `panelDisplayMode` value: the standalone window, but hidden while
the player is moving and shown again once they stop. `QuestFrameModule.hideWhenMoving`
(set by `SetDisplayMode`) and `QuestFrameModule.playerIsMoving` (set by the
player-movement show/hide trigger region) are read together at the top of
`QuestLog_Update`, which calls the same `DeactivateListPane` other hide
conditions use. Movement events are the one exception to #168's
polling-only rule — `PLAYER_STARTED_MOVING`/`PLAYER_STOPPED_MOVING` are
engine-dispatched, never part of Blizzard's secure execution chains, so
handling them directly can't taint anything.

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
