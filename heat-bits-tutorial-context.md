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
  (`#bottomNav`, filled by `renderBottomNav()`) has This Week, Calendar, **Habits** (2×2 grid icon), Notes and **⋯ More** (Graphs, Settings).
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
`#typeMeas`, unit `#newHabitUnit`, `#addHabitBtn`); right below the new-habit form, **Export / import**
`#exportOpenBtn` and then **Help & tour** `#helpOpenBtn` (its **?** is faded until hovered); footer with
`#storageNote` (in the apps it shows sync status, e.g. "Syncing with 1 phone").

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
  brighter the more you did it this week, with the number of days done in it (Settings → Layout → **Numbers on trackers**
  turns them off; **Tracker number style** Thin / Normal / Bold and **Tracker number opacity** set how they look), plus a Complete button.
- **Resize handle** `#weekResizeHandle`: drag to make the calendar taller or shorter; double-click to reset.
- **Heat map** `#heatmapWrap` (All Habits data). Clicking a past day opens a checklist of every habit and
  tracker for that day (`#dayModalBackdrop`).
- **Today** list `#allHabitRows`: today's scheduled habits with Complete buttons and the initial-goal bar.
  Completed habits disappear from the list ("All done for today.").
- **To-do** `#todoInput` + `#todoAddBtn`, list `#todoRows`. On This Week each row has a grip (`.drag-handle`):
  drag it onto the week grid to give the to-do that day and time. Ticking a to-do fades it out of the list into the
  bin: **Finished (n)** (`.todo-bin-btn`, also under the calendar's To-dos section) opens `#todoBinBackdrop`, where
  each one can be put back or deleted, or the whole bin emptied. Finished to-dos still show on the calendar.

### All Habits
Combined heat map, stats bar, color swatch `#allColorToggle`, **Today** and **To-do** (same as This Week).

### A habit's page (click a habit in the sidebar)
- **Title**: click to rename. The type tag ("yes / no" or "measurable · unit") sits next to it; click it to switch the type or change the unit (`#typeModalBackdrop`). Tracker tags work the same way.
- **Initial goal** row `#solidRow`, under the heat map: a full-width bar, "6 / 14" and "8 days until initial goal";
  pencil `#solidEdit` to change the target.
- **Habit notes** `#habitDescRow`, under the initial goal, a row of squares: **Description** `#habitDesc` (the text of the
  habit's own note, same note as in Notes, so editing either one changes both), then a square for each other note in the
  habit's folder (oldest first; a click opens it), then a dashed **+** square `#habitNoteAdd` that opens New note with the
  habit's folder picked.
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
- **Month / Week / Alarms** toggle: `#viewMonthBtn` / `#viewWeekBtn` / `#viewAlarmsBtn`. It opens in Month after a restart.
- **Alarms** view `#calAlarms` (`renderCalAlarms`): a clock-app list of everything that can ring, sorted by time of day:
  the standalone alarms (edited in place, like Settings → Alarms; **+ New alarm** `#calAlarmAdd`) and every coming habit,
  activity, dated to-do and reminder. With an alert it's on, without it's off; the switch adds a notification at its time
  (or restores the previous settings, kept in `alertOff`), and an on row shows when (at the time … 1 day before),
  Notification / Alarm and PC and phone / PC only / Phone only. Untimed things sort at 9:00 ("All day"), when they ring.
  Filter **All / On / Off** `[data-al-filter]`.
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
    All four have **Alert** `#peAlertSection`: when (`#peAlertWhen`: at the time … 1 day before), Notification or Alarm
    (`#peAlertKind`), and PC and phone / PC only / Phone only (`#peAlertWhere`). Things without a time alert at 9:00.
  - The same **Alert** picker (`.alert-picker`) is in the forms that create things: the sidebar's New habit box
    (`#newHabitAlert`), the New habit dialog (`#nhmAlert`) and Add to the calendar (`#eventAlert`, any type).
  - **Reminders** can be dragged from the All-day row into the grid to become timed boxes.
- **All Tasks panel** (week view) `#calDetail`:
  - **Groups**: Weekly (Habits, Activities), Monthly (Reminders), Once (To-dos).
  - **Sections**: each one collapses via `[data-sec-toggle="habits|activities|payments|todos"]` and has a **+**
    (`#calHabitAddIconBtn`, `#calActivityAddIconBtn`, `#calPaymentAddIconBtn`, `#calTodoAddIconBtn`, built at render time).
  - **Rows**: each has a drag handle (drag onto the grid), an edit pencil `.cal-edit-btn` and a trash icon.
  - **Whole panel**: folds into a thin strip with `#tasksPanelToggle`.
  - In the month view the panel instead shows the selected day.

### Notes (`li[title="Notes"]`, phone: Notes tab)
- **List** `.notes-side`: on top **Sort** `#notesSort` and a magnifying glass `#notesSearchBtn` (Ctrl+O) that swaps the
  Sort row for a search box `#notesSearch` (✕ or Escape closes it); the tree `#notesTree`; at the bottom icon buttons for
  a new note `#noteNewBtn`, canvas `#canvasNewBtn` and folder `#folderNewBtn` (they go in the selected folder),
  import/export `#notesIoBtn` (opens Export & import at the Obsidian options), **?** for the Markdown help, and (PC only)
  **«** `#notesSideHide`, which folds the list into a thin strip with **»** `#notesSideShow` to bring it back (`notesUi.sideHidden`, per device). **Ctrl+\** hides / shows it; Ctrl+O also brings it back. A **Habits** folder (open by default) holds a folder
  for every habit (its color dot), and each habit's folder holds one for each of its trackers. A **Quick notes** folder
  (`quick`, fixed) holds quick notes.
- **New note** from anywhere: the sidebar's **New note** `#newNoteSideBtn` (collapsed: `.newnote-item`) opens
  `#newNoteBackdrop`: **Quick note** `#nnQuick`, or a name `#nnName` + folder `#nnFolder` + **Create note**.
  **Ctrl+Shift+Q** anywhere makes a quick note ("Quick note Oct 16 20.48" in Quick notes) and puts the cursor in it.
  (Not Ctrl+Shift+N: browsers keep that for a private window.) In the PC app, Ctrl+Shift+Q also works while another
  program is in front (or Heat-Bits is in the tray): a small box in the app's colours opens in the middle of the screen,
  with **Title** and **Note**. Enter in Title moves to Note, Enter in Note saves it to Quick notes and closes the box,
  Shift+Enter is a new line, Esc cancels. An empty title gets the usual "Quick note …" name. Notes in the list get a delete button `.nt-del-note` (shown on hover and on the open note; it asks first, like the note's own trash button). User folders have rename and delete buttons. Delete asks `#choiceBackdrop`: **Keep the notes** (they move up a level) or **Delete the notes too** (subfolders included); an empty folder just asks to confirm.
  Double-click a note in the list to rename it there (Enter saves, Escape cancels; links to it follow the new name).
  Drag a note onto a folder to move it. On wide screens, the grip `#notesResize` on the list's right edge sets its width
  (kept per device in `notesUi.sideWidth`); double-click it to reset.
- **Note** `#notesPane`: greyed path above the title (`.note-path`, e.g. `Habits / Triceps / Exercises.md`; click a folder in it
  to show that folder in the list), title `#noteTitle` (renaming updates links to it), **Edit / Read / Side by side**
  `[data-note-mode]` (no side by side on phones). **Edit** is live: headings, bold, lists, tasks, links and pictures show
  formatted as you type, and the Markdown symbols appear only on the line with the cursor (`.lv-editor`). On other lines,
  clicking a link opens it and clicking a task box ticks it. **Side by side** is the plain text next to the finished note. delete `#noteDel`, **← Back** `#noteBackBtn` after following a link.
  To move a note to another folder, drag it in the list.
- **Habit notes**: every habit's folder has a note named after the habit (id `hn-<habitId>`); renaming the habit
  renames it, and once deleted it isn't made again.
- **To-dos in notes**: **To-do** `#noteAddTodo` opens a picker in `#noteSuggest` (find one, or type a new one); typing
  `[[` and part of a to-do's text also offers it. Written `[[todo:<id>|text]]`, shown as a box with the to-do's text and
  date; clicking it ticks the real to-do. On a canvas, **Add to-dos** `#cvAddTodo` (an existing one, or **+ New to-do**)
  makes a to-do card with a working box; double-click or **Rename** to change its text.
- A to-do that's in a note or canvas shows a note icon `.todo-note-link` in the to-do lists; it opens that note.
- **Pictures**: **Picture** `#noteAddImage` in the note's toolbar, pasting an image (Ctrl+V), or dropping image files on the
  note. Written `![[img-….jpg]]` (`|300` sets the width). Click one in Read to see it full size. On a canvas: **+ Add image**
  `#cvAddImage`, paste after clicking the board, or drop files on it; double-click a picture card (or **View**) for full size.
  Big photos are shrunk to 2000 px. In the apps they're files that sync after the data; in a browser they stay in that browser.
- **Keyboard shortcuts** (listed at the bottom of the Markdown help, `NOTE_KEYS`): Ctrl+E Edit ↔ Read, Ctrl+Shift+E side by side,
  Ctrl+B / I bold / italic, Ctrl+Shift+X strike, Ctrl+` code, Ctrl+K `[[link]]`, Ctrl+1…6 / 0 headings, Ctrl+Enter task,
  Ctrl+Shift+8 / 7 bullets / numbers, Enter continues a list, Tab / Shift+Tab indent, Ctrl+Shift+Q quick note (anywhere), Ctrl+Alt+N new note, Ctrl+O search,
  Alt+← back, Ctrl+S save.
  Typing `[[` shows title suggestions `#noteSuggest`. In Read mode, task boxes tick the text, and **Linked from** `#noteBacklinks`
  lists notes that link here. A link to a note that doesn't exist yet is faded; clicking it creates that note.
- **Sort** `#notesSort`: Name A–Z, Name Z–A, Last edited, Newest first, Manual (per device). Dragging a note onto the top
  or bottom half of another note (or a folder onto the top/bottom edge of one of your folders) puts it before/after it:
  that switches to **Manual** and saves the order of everything as it was on screen. The order syncs. Dropping on the
  middle of a folder moves it into that folder (folders can be nested, but never into themselves).
- **+ Canvas** `#canvasNewBtn`: a board (stored as a note with `kind: "canvas"`). Toolbar: **+ Add text** `#cvAddText`,
  **Add notes** `#cvAddNote`, zoom **− / Fit / +**, **Dots** `#cvDots` (background dots on/off, setting `canvasDots`), and
  **?** `.cv-help-btn` (how the canvas works). Drag the background to pan; Ctrl + scroll or pinch to zoom;
  double-click the background for a text card; double-click a text card to write (Markdown), a note card to open the note.
  Drag a card to move it, its corner to resize, and one of its dots onto another card to draw an arrow. Selecting a card
  or arrow shows `#cvSelBar` (colors, Edit/Open, Remove). Notes dragged from the list onto the board become cards.
  Canvases count as backlinks for the notes they hold.
- **Markdown help** `.md-help-btn` (the **?** under the list, the **?** in the note's toolbar, and a **Markdown help** button on the empty pane) opens
  `#mdHelpBackdrop`: each Markdown feature with what to type and how it looks.
- A habit's page has a **Notes** button `#habitNotesBtn`, and each tracker a notes icon `.subtracker-notes`, that open their folder.
- Phone: the list fills the screen (no page title); opening a note replaces it. **‹ Notes** `#noteClose`, swiping right
  on the note (not on a canvas), tapping the Notes tab, or the back button returns to the list.

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
- **Habits / Notes** switch `.graphs-tabs` (`state.graphsTab`, per device). **Notes** is a graph of the notes like Obsidian's
  (`renderNotesGraphView`, a `<canvas>` `#ngCanvas` with its own small force layout): a dot per note (squares are canvases,
  habit-folder notes take the habit's color, size grows with links), lines for `[[links]]`, `![[embeds]]` and canvas note
  cards. Drag dots, drag the background to pan, wheel/pinch to zoom, double-click empty space or **Fit** `#ngFit` to fit;
  hover lights up the neighbours, a click opens the note. Controls: search `#ngSearch`, **Notes without links** `#ngOrphans`,
  **Links to missing notes** `#ngMissing` (hollow dots; a click makes the note), **Always show names** `#ngLabels`.

### Settings
Cards in this order (each has `data-keywords` for the search), grouped in the index:
- **Find a setting** `#settingsSearch` above the cards: hides the cards and rows that don't match (a card whose title
  or keywords match shows whole; Devices & sync, Data & storage and Alarms are matched as a whole). Esc clears it, and
  the filter stays while the page redraws. "No setting matches that." `#settingsSearchEmpty`.
- **Index** `.settings-index`: on the right, in groups **Look**, **Alerts**, **Devices & data**, then Help (on narrow
  screens and phones a row of chips at the top, without the group names). Click to jump; the card you're on is
  highlighted as you scroll, and cards hidden by the search are dimmed. On the phone app (`HB.role === "client"`)
  **Devices & sync** is moved to the top of the page and of the index ("This phone").

**Look**
- **Appearance** `#appearanceCard`: theme color presets (incl. Custom), Light/Dark/Auto, app color,
  **Font size** `[data-fs-opt]`, font in two groups, **Web fonts** (Default, Lora, JetBrains Mono; downloaded once) and
  **On this device** (System plus every installed font typed into `#localFontInput`, remembered per device in
  `settings.localFonts`, each with a × `[data-forget-font]` to drop it), Reset `#settingsResetBtn`.
- **Layout** `#layoutCard`: sidebar always shown or auto-hide `[data-sidebar-opt]`; **Sidebar side** `[data-sidebar-side]`
  (Left/Right, `html.sb-right`; wide windows only; the resize edge, collapse arrow and auto-hide flip too); **Sidebar
  width** `#setSidebarWidth` (200–420 px, Reset `#sidebarWidthReset`; not on phones; the edge `#sidebarResize` can be
  dragged, double-click resets); **Always open on** `#setStartPage`; **Hide page titles** `#setHideTitles`.
- **Calendar & to-dos** `#calendarCard`: **Hide to-do dates and times** `#setHideTodoDates`, **Hide calendar icons**
  `#setHideKindIcons`, **Patterned calendar boxes** `#setPatternBorders`.
- **Heat maps & trackers** `#heatmapCard`: layout `[data-layout-opt="year|centered|rolling"]` (Calendar year, Centered on
  today, Today on the right), **All Habits heat map color** `#hmColor…` (Match app color `#hmMatchBtn`), **Numbers on
  trackers** `#setTrackerNumbers` with **Tracker number style** `[data-tn-weight]` and **opacity** `#trackerNumberRange`.

**Alerts**
- **Alarms** `#alarmsCard`: **+ New alarm** `#alarmAddBtn`; each alarm has a time, label, on/off switch, repeat days
  (none = once), Notification / Alarm and PC and phone / PC only / Phone only. Alarms sync. In the apps, **Test notification**
  and **Test alarm** `[data-alert-test]` send a sample in 5 seconds. They only ring in the apps, not in a browser.
- **Sound** `#soundCard`: **Sounds** on/off `#setSound` (on by default), Volume Low / Medium / High
  `[data-sound-vol]`, Pitch Lower / Normal / Higher `[data-sound-pitch]` plus a slider `#soundPitchRange` (50–200%), **Taps and drags** `#setSoundTaps`. Per device, never synced.

**Devices & data**
- **Devices & sync** `#syncCard` (apps only):
  - PC: QR code, address and pairing code, New code `#syncNewCode`, a second QR code (**Get the Android app**,
    links to the latest GitHub release's APK), paired phones.
  - Phone: **Scan QR code** `#syncScanBtn`, manual `#syncHostInput` + `#syncCodeInput` + `#syncConnectBtn`;
    when paired, **Sync now** `#syncNowBtn` and **Unpair** `#syncUnpairBtn`.
  - Both: **Sync settings** `#syncSettingsToggle` (on by default): colors, font, sound, layout and heat map stay the
    same on the PC and the phone. Turning it off on one device keeps that device's own settings.
- **Behavior** `#desktopCard` (Windows app only, `HB.platform === "windows"`): **Keep running when closed**
  `#setCloseToTray` (`closeToTray`) and **Quick note from any program** `#setGlobalHotkey` (`globalHotkey`). Both on
  by default, per device.
- **Data & storage** `#dataCard` (apps only): the folder the data is kept in, what's in it (heatbits.json with the
  counts of habits, notes, to-dos…, its size and when it was saved; `attachments\` with the pictures).
  PC only: **Open folder** `#dataOpenBtn`, **Change folder…** `#dataChangeBtn` (Windows folder picker; the data is
  copied there, or, if that folder already has Heat-Bits data, the user picks *Use the data there* or *Replace with mine*)
  and **Back to Heat-Bits' own folder** `#dataDefaultBtn`. Phones keep the data in the app's own storage.
- **Settings file** `#settingsFileCard`: export and import settings only (`#settingsExportBtn`, `#settingsImportBtn`).
- **Help** `#helpCard`: **Show the tour** `#settingsTourBtn` (the way into the tour on phones).

### Data export / import
`#exportOpenBtn` opens `#exportModalBackdrop`:
- **Full backup (JSON)** `#exportJsonBtn`
- **Habit history (CSV)** `#exportCsvBtn`
- **Import** `#importPickBtn`, or paste into `#importPaste`, with Merge or Replace.
- **Notes & Obsidian** `#obsSection`: **Export notes (.zip)** `#obsExportZipBtn` (Markdown + canvases + pictures, opens as an
  Obsidian vault), PC app: **Export notes to a folder** `#obsExportDirBtn` (into "Heat-Bits notes" in the picked folder);
  **Import an Obsidian vault** `#obsImportDirBtn` (PC app and browsers, not the Android app) and **Import Markdown files**
  `#obsImportFileBtn` (a zipped vault or .md/.canvas files). An import shows what it found, then adds it as a new folder in Notes.

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

### PC / web, wide window (18 steps in a browser, 19 in the Windows app; 2 fewer with no habits)
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
13. **Notes** `#notesTree`: Markdown notes, a folder per habit and tracker, links with `[[Note name]]`.
14. *(Windows app only)* **Your phone** `#syncCard`: pairing, and the code to download the Android app.
15. **Appearance** `#appearanceCard`: theme colors, light or dark, app color, font and size.
16. **Sound** `#soundCard`: sounds on or off, volume and pitch.
17. **Layout** `#layoutCard`: the start page, and what to hide (sidebar, page titles).
18. **Heat maps & trackers** `#heatmapCard`: calendar year, centered on today, or today on the right; how the tracker numbers look.
19. **That's it** `#helpOpenBtn` (collapsed: `.help-item`): reopen from **Help**. Offers **Remove the example habits**.

### Phone layout (≤ 700 px; 16 steps, 17 on an unpaired Android phone)
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
12. **Notes** `#notesTree`.
13. **Appearance** `#appearanceCard`.
14. **Sound** `#soundCard`.
15. **Layout** `#layoutCard`.
16. **Heat maps & trackers** `#heatmapCard`.
17. **That's it** `#settingsTourBtn` (Settings): reopen from Settings. Offers **Remove the example habits**.

Possible next additions, shown once the first time a feature is used: the Just this day / Weekly pattern / All days
question (first move on the calendar), and Graphs' **?** button.

## 9. Tone and copy guidelines

- **Tone:** short, friendly, second person ("you"), sentence case, no jargon. Say "square" or "day", not "cell"; say
  "repeat days", not "schedule".
- **Labels:** refer to buttons by their visible label in **bold** ("Complete", "Scan QR code", "Add to the calendar").
- **Length:** one idea per step, at most two sentences, plus the action to take.
