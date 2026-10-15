# Heat-Bits: context for building a first-time-user tutorial

This file describes Heat-Bits for its in-app onboarding tutorial (guided tour / coach marks).
It explains what the app is, how a new user thinks about it, every screen and control a tutorial would point at
(with the exact selectors), what's on screen the very first time, and the tour's script.

**The tour is built.** It lives in `assets/web/index.html` under `// ---------------- guided tour ----------------`
(`startTour`, `tourSteps`, `tourShow`, `tourPlace`, `endTour`). Section 8 describes what it does now. If you change a
screen the tour points at, update `tourSteps()` and this file together.

---

## 1. What Heat-Bits is (one paragraph for the tutorial's intro)

Heat-Bits is a habit tracker built around **heat maps**: every habit gets a GitHub-style grid of days, and each
square fills in with the habit's color when you do it. Darker or more filled squares mean more done. Around that it adds a
**calendar** (habits, activities, reminders and to-dos laid out by the hour), **trackers** (finer detail inside
a habit, like sets per muscle group), **graphs**, and an **initial goal** per habit (default: 14 days in a row)
to get a new habit started.

**Where it runs.** All of these share one codebase, the single page `index.html`:
- the web page,
- a Windows app (Flutter, which also hosts sync),
- an Android app (Flutter).

The Windows and Android apps sync over the home Wi-Fi.

## 2. Core concepts (glossary the tutorial should teach)

| Term | Meaning | Where it lives |
|---|---|---|
| **Habit** | Something you want to do on repeat days. Two types: **Yes / No** (done or not) and **Measurable** (log a number with a unit, e.g. 8 glasses, 5 km). | Sidebar list; each has its own page |
| **Repeat days** | The weekdays a habit is scheduled (S M T W T F S toggles). Days it isn't scheduled don't break streaks. | Habit page, next to the year |
| **Heat map** | The year grid. Click a past square to fill or clear it (measurable asks for a number). Future squares are faded grey and show what's scheduled. | Habit page, All Habits, This Week |
| **Streak** | Scheduled days completed in a row (unscheduled days are skipped, not counted as breaks). | Habit stats, sidebar number (e.g. "9d") |
| **Initial goal** | "X days until initial goal": a starter target (default 14 days in a row), editable with the pencil. | Habit page under the title; progress bar in Today lists |
| **Tracker** | A mini heat map inside a habit for detail (e.g. Chest/Legs inside Gym). Yes/No or Measurable, with its own repeat days. Completing a tracker also completes its habit. | Bottom of a habit page; This Week → Trackers panel |
| **All Habits** | Every habit combined on one grid. Darker means more habits done that day; a thin white outline (30% opacity) means a perfect day. | Sidebar; also the heat map on This Week |
| **Activity** | A calendar block that isn't a habit (e.g. "Gym class 6–7pm"). Always repeats weekly on chosen weekdays. | Calendar |
| **Reminder** | A dated reminder (optionally monthly, with an amount, e.g. rent). Can be "paid". | Calendar |
| **To-do** | A one-off task. Can have a date/time to appear on the calendar. | To-do list (All Habits / This Week) and Calendar |
| **Weekly / Monthly / Once** | How the "Add to the calendar" dialog groups types: Habit and Activity are Weekly, Reminder is Monthly, To-do is Once. | Calendar dialog, All Tasks panel |
| **Just this day / Weekly pattern / All days** | The question asked when you move or resize a habit or activity on the week calendar: change only that date, that weekday every week, or every day it repeats. | Calendar |

## 3. First run: what a new user actually sees

- **Web / Windows (first launch):** two **demo habits** are created with ~45 days of random history:
  "Morning walk" (Yes/No, orange) and "Water" (Measurable, glasses, blue). Morning walk has two example
  trackers, "Distance" (Measurable, km) and "Stretch after" (Yes/No), so the Trackers panel and the habit page
  show what trackers are for. The habits carry `demo: true`, and the
  device remembers it added them (`state.settings.demoAdded`), so removing every habit doesn't bring them back.
  The app opens on **This Week** (configurable later in Settings → Always open on).
  - The tour's last step offers **Remove the example habits** (removes every habit with `demo: true`). A single
    habit can also be deleted from its page with the trash button `#deleteHabitBtn`, which asks for confirmation.
- **Android (unpaired):** starts **empty** (no demo data) because pairing brings the PC's habits over (anything already on the phone is kept too).
  The phone tour leads with pairing.
- **The tour opens by itself** on that first launch only (fresh data, `state.settings.tutorialSeen` not set).
  Existing installs that update don't get it automatically; it's under Help.
- **Phone layout** (any window ≤ 700 px wide): the sidebar is **hidden**. A fixed **tab bar at the bottom**
  (`#bottomNav`, filled by `renderBottomNav()`) has This Week, Calendar, **Habits** (2×2 grid icon), Graphs and Settings.
  The Habits tab opens a bottom sheet (`#habitSheetBackdrop`, tiles in `#habitTiles`): All Habits, each habit, and
  **New habit**. Android's back button closes the sheet. The new-habit form, Help button and Export button in the
  sidebar aren't reachable there: Help is in Settings, Export is on Graphs.

## 4. Navigation map

The sidebar (`#sidebar`, list `#habitList`) contains, in order:

| Item | Selector | Page |
|---|---|---|
| This Week | `li[title="This Week"]` | Week calendar + Trackers panel + heat map + Today + To-do |
| Calendar | `li[title="Calendar"]` | Month / Week calendar + All Tasks panel |
| Graphs | `li[title="Graphs"]` | Charts |
| Settings | `li[title="Settings"]` | All settings |
| All Habits | `li[title="All Habits"]` | Combined heat map + Today + To-do |
| (divider) | `.list-divider` | |
| each habit | `li[title="<habit name>"]` | That habit's page |
| + (collapsed sidebar only) | `.add-habit-item` | Opens the New habit dialog (`#nhmName`, Yes/No or Measurable, repeat days) |
| ? (collapsed sidebar only) | `.help-item` | Starts the tour |

The active item has class `.habit-item.active`. That's the reliable way for tutorial code to know the current page.

Sidebar extras: collapse button `#collapseToggle`; new-habit form (`#newHabitName`, type buttons `#typeBool` /
`#typeMeas`, unit `#newHabitUnit`, `#addHabitBtn`); **Help & tour** button `#helpOpenBtn` right below the
new-habit form; footer with `#exportOpenBtn` (Export / import) and `#storageNote` (in the apps it shows sync
status, e.g. "Syncing with 1 phone").

## 5. Screen by screen (what to explain, and where it is)

### This Week (default start page)
On phones the order is: week calendar, heat map, Today, Trackers, To-do.
- **Week calendar** `#weekWrap`, nav `#weekPrev` / `#weekNext` / `#weekToday`, quick add `#weekQuickAddBtn` (+).
  - Opens scrolled to the current time.
  - Click an empty slot to add something.
  - Drag a block to move it, and drag its bottom tab (`.event-resize-handle`) to resize.
  - On phones: **hold a block for half a second**, then drag to move it. The bottom grip is bigger (16 px) and
    resizes straight away. Holding a block and letting go without moving shows its delete button.
  - Double-click (phones: tap twice) a block to edit it.
- **Trackers panel** `#weekTrackersPanel`: pick a habit in its select; each tracker shows a square that gets
  brighter the more you did it this week, plus a Complete button.
- **Resize handle** `#weekResizeHandle`: drag to make the calendar taller or shorter; double-click to reset.
- **Heat map** `#heatmapWrap` (All Habits data). Clicking a past day opens a checklist of every habit and
  tracker for that day (`#dayModalBackdrop`).
- **Today** list `#allHabitRows`: today's scheduled habits with Complete buttons and the initial-goal bar.
  Completed habits disappear from the list ("All done for today.").
- **To-do** `#todoInput` + `#todoAddBtn`, list `#todoRows`.

### All Habits
Combined heat map, stats bar, color swatch `#allColorToggle`, **Today** and **To-do** (same as This Week).

### A habit's page (click a habit in the sidebar)
- **Title**: click to rename. The type tag ("yes / no" or "measurable · unit") sits next to it.
- **Initial goal** row `#solidRow` ("14 days until initial goal"); pencil `#solidEdit` to change the target.
- **Color** `#colorToggle`; **delete** `#deleteHabitBtn`.
- **Stats**: current streak, longest streak, days logged, this year.
- **Complete** button `#completeZone`. For measurable habits it opens an inline box (`#inlineValue`, Save
  `#inlineSave`, red ✕ `#inlineCancel`).
- **Repeat days** `#dayToggleRow` (S M T W T F S) and **At** time `#habitTimeInput`. The time puts the habit on the week
  calendar every day it repeats.
- **Heat map** `#heatmapWrap`: click past squares to fill or clear; year arrows `#prevYear` / `#nextYear` (Calendar-year layout).
- **Trackers** section: **+ Add tracker** `#addSubTrackerBtn` opens `#subTrackerModalBackdrop`
  (name, Yes/No or Measurable, unit); list `#subTrackerList`, each tracker with its own repeat days and Complete.

### Calendar
- **Month / Week** toggle: `#viewMonthBtn` / `#viewWeekBtn`. It opens in Month after a restart.
- **Month**: `#calGrid`, nav `#calPrev` / `#calNext` / `#calToday`. Each day shows up to 11 habit squares (filled = done),
  a to-do count and a bell for reminders. Click a day to see it in the side panel (`#calDetail`).
- **Week**: hour grid like This Week.
  - **Add**: click an empty slot to open **Add to the calendar** (`#eventModalBackdrop`).
  - **Type buttons**: `#blockTypeHabit`, `#blockTypeActivity`, `#blockTypePayment` (Reminder), `#blockTypeTodo`.
  - **Fields**: name `#eventTitleInput`, Hour `#eventTimeInput`, Duration `#eventDurationInput`, and colors `#eventColorRow`
    (palette, custom picker, "Default").
  - **Type-specific fields**: Habit gets Yes/No or Measurable plus repeat days; Activity gets repeat days; Reminder
    gets amount, date and "Repeats monthly"; To-do gets a date.
  - **Moving a block** asks `#repeatChoiceBackdrop`: Just this day / Weekly pattern / All days.
  - **Double-click any block** to open the editor `#habitEditPopover`. A habit shows name, color, repeat days and Complete;
    an activity shows name, color and repeat days; a reminder shows name, color, date, amount and monthly; a to-do shows name, color and date.
  - **Reminders** can be dragged from the All-day row into the grid to become timed boxes.
- **All Tasks panel** (week view) `#calDetail`:
  - **Groups**: Weekly (Habits, Activities), Monthly (Reminders), Once (To-dos).
  - **Sections**: each one collapses via `[data-sec-toggle="habits|activities|payments|todos"]` and has a **+**
    (`#calHabitAddIconBtn`, `#calActivityAddIconBtn`, `#calPaymentAddIconBtn`, `#calTodoAddIconBtn`, built at render time).
  - **Rows**: each has a drag handle (drag onto the grid), an edit pencil `.cal-edit-btn` and a trash icon.
  - **Whole panel**: folds into a thin strip with `#tasksPanelToggle`.
  - In the month view the panel instead shows the selected day.

### Graphs
- **Time on the calendar** (donut):
  - Range buttons `[data-trange="week|month|year"]`.
  - Click legend rows `[data-tslice]` to show or hide slices, including **Unplanned**; `#timeAllBtn` does Show all / Hide all.
- **Completion** line chart:
  - Range buttons `[data-lrange="7d|30d|3m|6m|1y|all"]`.
  - Legend chips `[data-line]` toggle habits on and off.
  - The **?** (`#lineHelpBtn`) explains the maths.
- **Trackers** line chart (only when some habit has trackers):
  - Habit select `#trackerHabitSelect`.
  - Ranges `[data-trrange]`.
  - Mode `[data-trmode="pct|amount"]` (Completion % or Amount).
  - Chips `[data-trline]`.
- **Habits**:
  - Range buttons `[data-range="7d|30d|12w|6m|12m|all"]`.
  - Each habit card collapses (`[data-toggle-habit]`); `#graphAllToggle` does Expand all / Collapse all.
- **Export / import** `#graphsExportBtn` (also reachable here on phones).

### Settings
- **Devices & sync** `#syncCard` (apps only):
  - PC: QR code, address and pairing code, New code `#syncNewCode`, a second QR code (**Get the Android app**,
    links to the latest GitHub release's APK), paired phones.
  - Phone: **Scan QR code** `#syncScanBtn`, manual `#syncHostInput` + `#syncCodeInput` + `#syncConnectBtn`;
    when paired, **Sync now** `#syncNowBtn` and **Unpair** `#syncUnpairBtn`.
- **Appearance**: theme color presets (incl. Custom), Light/Dark/Auto, app color, All Habits heat map color,
  **Font size** `[data-fs-opt]`, font (incl. installed fonts `#localFontInput`), Reset `#settingsResetBtn`.
- **Sound** `#soundCard`: **Sounds** on/off `#setSound` (on by default), Volume Low / Medium / High
  `[data-sound-vol]`, Pitch Lower / Normal / Higher `[data-sound-pitch]`, **Taps and drags** `#setSoundTaps`. Per device, never synced.
- **Layout**:
  - Sidebar always shown or auto-hide: `[data-sidebar-opt]`.
  - **Always open on** `#setStartPage`.
  - Switches: hide page titles, hide to-do dates, hide calendar icons, patterned calendar boxes.
- **Heat map** layout `[data-layout-opt="year|centered|rolling"]`: Calendar year, Centered on today, or Today on the right.
- **Help**: **Show the tour** `#settingsTourBtn` (the way into the tour on phones).
- **Settings file**: export and import settings only (`#settingsExportBtn`, `#settingsImportBtn`).

### Data export / import
`#exportOpenBtn` opens `#exportModalBackdrop`:
- **Full backup (JSON)** `#exportJsonBtn`
- **Habit history (CSV)** `#exportCsvBtn`
- **Import** `#importPickBtn`, or paste into `#importPaste`, with Merge or Replace.

## 6. Platform differences the tutorial must respect

| | Web / Windows | Android |
|---|---|---|
| Sidebar | Full sidebar (collapsible, optional auto-hide) | Hidden; bottom tab bar + Habits sheet |
| Demo data | Yes, first launch | No; pairing brings data |
| Drag / resize on calendar | Mouse drag works | Hold half a second, then drag; bigger bottom grip to resize; tap twice to edit |
| Help / tour | **Help & tour** under New habit, or **?** when collapsed | Settings → Help → **Show the tour** |
| Sync | PC is the hub (shows QR) | Pairs by scanning the QR |
| Export | Saves to Downloads | Opens the share sheet |

Inside the apps, `window.__HB_HOST__` exists: `role` is `"host"` (PC) or `"client"` (phone), and `platform` is
`"windows"` or `"android"`. In a plain browser it's undefined. Use this to pick the PC or phone tutorial.

## 7. Implementation notes for whoever builds the tutorial

- **The DOM is re-rendered often.** `render()` rebuilds the sidebar and the main area after almost every action,
  and the inner HTML is replaced. Re-query the target element at each step (don't hold references), and
  re-position highlights after clicks, window resize, and incoming sync updates.
- **Navigate by clicking** sidebar items (`document.querySelector('li[title="Calendar"]').click()`). Internal
  functions live inside one closure (IIFE) and aren't on `window`. To call `render()` or `openEventModal()`
  directly, add the tutorial code inside that closure (near the end, before the final `render();`).
- **Only some targets exist at a time.** Each page renders its own elements, so `#todoInput` exists only on This Week and All Habits,
  `#solidRow` only on a habit page, and `#syncCard` only in the apps.
- **Dialogs** use `.modal-backdrop.open`; the edit popover uses `.side-popover.open`. Close them with Escape
  or their Cancel buttons. While one is open, incoming sync updates wait.
- **Remembering "tutorial done":** `state.settings.tutorialSeen` (settings are per device and never sync). It's set
  when the tour starts. Don't put it in habits, todos, activities or payments; those sync between devices. (Not
  `localStorage`: in the apps the page's address can change port, which would lose it.)
- **Main data** is in `localStorage["grid-habit-tracker-v2"]` (web). In the apps the Flutter side stores it
  in a file and injects it as `window.__HB_BOOT_STATE__`.
- **Styling:** use the CSS variables so the tutorial matches all themes and dark mode:
  `--bg --surface --surface-2 --ink --ink-soft --border --border-strong --accent --radius`, fonts `--font-body`
  `--font-head`, and scale text with `calc(<px> * var(--fs, 1))` so the Font size setting applies.
- **Phone width (≤ 700px):** coach-mark bubbles should sit above or below their target, not to the side, and
  stay within a 12 px margin.

## 8. The tour as built

A highlight (`.tour-spot`) around one thing at a time and a card (`.tour-card`) with a step counter, **Skip tour**,
**Back** and **Next** (**Done** on the last step). Escape closes it, and the arrow keys step through it. Android's
back button closes it too (it pushes a history entry, like the Habits sheet). Each step can switch page first.
Targets are looked up again every 150 ms, so re-renders and sync updates don't leave the highlight behind. If a
target is missing, the card shows centered with the page dimmed. When the tour ends, the app goes back to the page
the user was on. The steps come from `tourSteps()`, which builds them for the current layout.

Every step's text is kept to about two lines of the card. Steps with `calView` switch the Calendar to Month or
Week first; the tour puts the user's own choice back when it ends. The Settings cards have ids for the tour:
`#appearanceCard`, `#layoutCard`, `#heatmapCard`.

### PC / web, wide window (16 steps in a browser, 17 in the Windows app; 2 fewer with no habits)
1. **Welcome to Heat-Bits** (no target). Mentions the two example habits when they're there.
2. **Your week** `#weekWrap` (This Week): plan by the hour; click an empty slot or **+** to add.
3. **Moving things around** `#weekWrap`: drag to move, drag the bottom edge to resize, double-click to edit.
4. **Your year** `#heatmapWrap`: darker squares, click a past day to check off what you forgot.
5. **Today** `#allHabitRows`: **Complete**, the initial-goal bar.
6. **Trackers** `#weekTrackersPanel`: trackers log details inside a habit (sets per muscle); check them off here.
7. **A habit's own page** `#dayToggleRow` (first habit's page): repeat days; off days don't break the streak.
8. **Add trackers** `.subtracker-section` (same page): **+ Add tracker**, each with its own small heat map.
9. **Add your own habit** `.new-habit` (collapsed: `.add-habit-item`): **Yes / No** or **Measurable**.
10. **Calendar: month** `#calGrid` (Month view): click a day to see and check off its habits.
11. **Calendar: week** `.cal-panel` (Week view): plan by the hour; **Month** / **Week** switch views.
12. **Graphs** first `.graph-card`.
13. *(Windows app only)* **Your phone** `#syncCard`: pairing, and the code to download the Android app.
14. **Appearance** `#appearanceCard`: theme colors, light or dark, app color, font and size.
15. **Layout** `#layoutCard`: the start page, and what to hide (sidebar, page titles).
16. **Heat map** `#heatmapCard`: calendar year, centered on today, or today on the right.
17. **That's it** `#helpOpenBtn` (collapsed: `.help-item`): reopen from **Help**. Offers **Remove the example habits**.

### Phone layout (≤ 700 px; 14 steps, 15 on an unpaired Android phone)
1. **Welcome**. On an unpaired phone it says the phone syncs with the PC.
2. *(unpaired Android only)* **Connect to your PC** `#syncCard` (Settings): Settings → Devices & sync on the PC,
   then **Scan QR code** here, same Wi-Fi.
3. **Your week** `#weekWrap`: tap an empty slot or **+** to add.
4. **Moving things around** `#weekWrap`: hold, then drag; the bottom bar resizes; tap twice to edit.
5. **Your year** `#heatmapWrap`.
6. **Today** `#allHabitRows`.
7. **Trackers** `#weekTrackersPanel`.
8. **Getting around** `#bottomNav`: the tabs; **Habits** opens each habit, its trackers, and **New habit**.
9. **Calendar: month** `#calGrid`.
10. **Calendar: week** `.cal-panel`.
11. **Graphs**.
12. **Appearance** `#appearanceCard`.
13. **Layout** `#layoutCard`.
14. **Heat map** `#heatmapCard`.
15. **That's it** `#settingsTourBtn` (Settings): reopen from Settings. Offers **Remove the example habits**.

Possible next additions, shown once the first time a feature is used: the Just this day / Weekly pattern / All days
question (first move on the calendar), and Graphs' **?** button.

## 9. Tone and copy guidelines

- **Tone:** short, friendly, second person ("you"), sentence case, no jargon. Say "square" or "day", not "cell"; say
  "repeat days", not "schedule".
- **Labels:** refer to buttons by their visible label in **bold** ("Complete", "Scan QR code", "Add to the calendar").
- **Length:** one idea per step, at most two sentences, plus the action to take.
