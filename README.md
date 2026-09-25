# Cookie

A small Mac app for putting checklist items on calendar days. A compact month calendar sits above the selected day's list; type a task, press Return, and it lands on that day.

Checking a task off rolls a cookie across the row.

## Features

- **Month calendar.** Days with unfinished tasks get a dot: filled red once the day has passed, hollow for days still ahead. Collapse the calendar with the chevron beside the month (⌘⇧C), or drag the handle under it to resize.
- **Quick entry.** The field under the calendar always adds to the selected day and keeps focus, so you can type several tasks in a row.
- **Earlier section.** When today is selected, unfinished tasks from past days appear above today's list. They keep their original date; nothing rolls over on its own.
- **Drag to reschedule.** Drag a task onto a calendar day, or hold it at the top or bottom edge of the list to step through days, then drop it where it belongs.
- **Editing.** Double-click a task, or right-click and choose Edit. Return saves, Escape cancels.
- **Completed section.** Finished tasks move to a collapsible section for their day, in the order you completed them.
- **Undo.** ⌘Z restores a deleted task or reverts an edit.

| Shortcut | Action |
| --- | --- |
| ⌘T | Go to today |
| ⌘⇧C | Show or hide the calendar |
| ⌘Z | Undo delete or edit |
| ⌘, | Settings (add new tasks at the top or bottom) |

## Requirements

- macOS 15 or later
- Xcode 16 or later (Swift 6)

## Building and running

```bash
scripts/build-app.sh --run
```

This builds with Swift Package Manager, assembles `build/Cookie.app` (the bundle is needed for the Dock icon), and opens it. Pass `--release` for an optimized build.

Run the tests with:

```bash
swift test
```

The build scripts point `DEVELOPER_DIR` at `/Applications/Xcode.app`; adjust that if Xcode lives elsewhere.

## Where tasks are stored

Tasks are saved as JSON at `~/Library/Application Support/Cookie/tasks.json`, a moment after each change and again when the app quits. The file is plain, readable JSON. If it ever can't be read, the app moves it aside as `tasks-unreadable-<timestamp>.json` instead of overwriting it. Deleted tasks are kept for 30 days, so undo works, and then dropped.

Two environment variables help during development:

| Variable | Effect |
| --- | --- |
| `COOKIE_SAMPLE_DATA=1` | Start with built-in sample tasks, kept in memory only. |
| `COOKIE_DATA_DIR=<folder>` | Read and write `tasks.json` in that folder instead. |

For example:

```bash
open --env COOKIE_SAMPLE_DATA=1 build/Cookie.app
```

## Project layout

```
Sources/CookieCore/   Task model, calendar-day math, the task store, and saving
Sources/CookieApp/    The SwiftUI app: window, calendar, day list, dragging
Tests/CookieCoreTests Tests for the store and the task file
Assets/               App icon (AppIcon.svg is the source; the .icns is generated)
scripts/              build-app.sh builds the app; make-icon.sh regenerates the icon
```

`CookieCore` has no UI code, so the same model can back an iPhone version later.

## License

MIT. See [LICENSE](LICENSE).
