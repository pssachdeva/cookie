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
- **Menu bar.** The cookie in the menu bar opens today's tasks with an entry field, whatever day the main window is showing. Closing the main window leaves Cookie running there; ⌘Q quits it entirely.
- **iCloud sync.** Tasks sync through your private iCloud database. The app works fully offline and catches up when it's back online.

| Shortcut | Action |
| --- | --- |
| ⌘T | Go to today |
| ⌘⇧C | Show or hide the calendar |
| ⌘Z | Undo delete or edit |
| ⌘, | Settings (add new tasks at the top or bottom) |

## Requirements

- macOS 15 or later
- Xcode 16 or later (Swift 6)
- For iCloud sync: a paid Apple Developer Program membership

## Building and running

There are two builds of the same code.

**Signed, with iCloud sync.** `Cookie.xcodeproj` builds the app signed with your developer team and the iCloud entitlement:

```bash
scripts/build-signed.sh --install
```

This builds a Release version, replaces `/Applications/Cookie.app`, and opens it. Leave off `--install` to only build, or add `--debug` for a Debug build. One-time setup:

1. In Xcode, sign in under **Settings > Accounts** with your developer Apple ID.
2. Open `Cookie.xcodeproj`, select the **Cookie** target, and choose your team under **Signing & Capabilities**. The iCloud capability should list the container `iCloud.com.psachdeva.cookie`; if it shows in red, click the refresh button to register it.

You can also build and run from Xcode itself.

**Unsigned, local only.** A quick build with Swift Package Manager that doesn't need a developer account. iCloud sync stays off:

```bash
scripts/build-app.sh --run
```

This assembles `build/Cookie.app` and opens it. Pass `--release` for an optimized build.

Run the tests with:

```bash
swift test
```

The scripts point `DEVELOPER_DIR` at `/Applications/Xcode.app` unless it's already set.

## Where tasks are stored

Tasks are saved as JSON at `~/Library/Application Support/Cookie/tasks.json`, a moment after each change and again when the app quits. The file is plain, readable JSON. If it ever can't be read, the app moves it aside as `tasks-unreadable-<timestamp>.json` instead of overwriting it. Deleted tasks are kept for 30 days, so undo works, and then dropped.

Three environment variables help during development:

| Variable | Effect |
| --- | --- |
| `COOKIE_SAMPLE_DATA=1` | Start with built-in sample tasks, kept in memory only. |
| `COOKIE_DATA_DIR=<folder>` | Read and write `tasks.json` in that folder instead. Turns sync off. |
| `COOKIE_DISABLE_SYNC=1` | Turn iCloud sync off for this run. |

For example:

```bash
open --env COOKIE_SAMPLE_DATA=1 build/Cookie.app
```

## iCloud sync

Each task is one record in a `Tasks` zone of your private CloudKit database, and the task text is end-to-end encrypted. `CKSyncEngine` uploads local changes and fetches other devices' changes, prompted by silent push notifications and whenever the app comes to the front.

The local file stays the source the app reads from. When two devices change the same task, the changes merge field by field: the text, the day and position, the completion, and the deletion each keep the most recent change. Completing a task on one device and editing its text on another keeps both. Sync bookkeeping is kept in `sync-state.plist` beside `tasks.json`.

Sync only runs in the signed build. Changes made in an unsigned build are uploaded the next time the signed build runs.

## Project layout

```
Sources/CookieCore/   Task model, merging, calendar-day math, the task store, and saving
Sources/CookieSync/   iCloud sync with CloudKit
Sources/CookieApp/    The SwiftUI app: window, calendar, day list, dragging
Tests/                Tests for the core model and the CloudKit record mapping
Cookie.xcodeproj      The signed app target, built from Sources/CookieApp
App/                  Info.plist and entitlements for the signed app
Assets/               App icon (AppIcon.svg is the source; the .icns is generated)
scripts/              build-signed.sh, build-app.sh, and make-icon.sh
```

`CookieCore` and `CookieSync` have no UI code, so they can back an iPhone version later.

## License

MIT. See [LICENSE](LICENSE).
