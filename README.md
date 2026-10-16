# omarchy widgets

The widget store for [Omalauncher](https://github.com/SimonSchubert/omalauncher), the Android launcher that
runs Arch Linux and draws home-screen widgets written in OWL, a small declarative widget language.
It also holds OWL apps: full-screen views that open from the app drawer instead of sitting on a page.

Everything in `widgets/` and `apps/` has been reviewed. When a pull request is merged, CI builds
`index.json` (widgets) and `apps.json` (apps) and publishes the store to GitHub Pages, where the
launcher's **store** reads them. Before installing, it shows you every command a widget or app runs
and every package it installs, and it checks the download against the reviewed file's SHA-256.

## Submitting a widget

The easy way: long-press your widget on the phone and tap **publish**. Your coding agent forks
this repo with the GitHub CLI and opens the pull request for you.

By hand:

1. Fork this repo and add your widget at `widgets/<your GitHub username, lowercase>/<name>/widget.owl`.
   Names use lowercase letters, digits and dashes.
2. Give it `meta` and declare its packages:

   ```owl
   widget "disk" {
     meta { description: "Free space on the root disk"; version: "1.0"; license: "MIT"; category: "system" }
     size: 3x2
     requires { pacman: ["dua-cli"] }
     ...
   }
   ```

3. Optionally add `preview.png`, a screenshot of the tile (under 300 KB). For the store to show
   the tile in the user's own Omarchy theme, add `previews/<theme>.webp` too, one per theme (under
   100 KB each, named like `tokyo-night.webp`); the launcher's debug build makes them with
   `scripts/store-previews.sh`.
4. Check it locally: `java -jar tools/owl.jar review . widgets/<you>/<name>/widget.owl`
5. Open a pull request. The **review** check runs the same rules and writes a summary of what the
   widget runs and installs; a maintainer reviews it and merges.

The widget language is documented in [docs/LANGUAGE.md](docs/LANGUAGE.md).

## Submitting an app

An app is an OWL file that starts with `app "name" { }` instead of `widget`: the nodes at its top
are the whole full-screen view, and it has no tile, so no `size`. It goes at
`apps/<your GitHub username, lowercase>/<name>/app.owl`, follows the same steps and rules as a
widget, needs `meta { owl: 8 }`, and should have an `icon`: an SVG in the file, drawn in
`currentColor` so it takes the user's theme accent, or a PNG embedded as an `asset`. The launcher
shows it standalone on the theme's background; see the Apps section of the launcher's widget
README for the style the store's apps share:

```owl
app "notes" {
  meta { owl: 8; description: "Quick notes that stay on the phone"; version: "1.0"; license: "MIT"; category: "productivity" }
  title: "notes"
  icon: """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round">
    <path d="M11 5h18l9 9v29H11z"/>
    <path d="M29 5v9h9M17 24h15M17 32h10"/>
  </svg>"""
  state notes = [] persist
  Column {
    Input { placeholder: "write a note…"; clear: true; onSubmit: notes = [value] + notes }
    for n in notes { Text { text: n } }
  }
}
```

Check it with `java -jar tools/owl-apps.jar review . apps/<you>/<name>/app.owl`. Its previews are
pictures of the whole view at a phone's size, which `scripts/store-previews.sh` makes too. A widget
and an app can't share a name. Launchers from before apps (0.7.2 and older) only read `index.json`, so they never see one.

## Rules

- One folder per widget, and only `widget.owl`, `preview.png`, `README.md` and `previews/<theme>.webp` in it
  (`app.owl` for an app).
- You can only add or change widgets and apps under your own username.
- `meta` needs a `description` (10-200 characters), a `version` and a `license`. Add a `category`
  (`news`, `dev`, `productivity`, `time`, `world`, `sport`, `finance`, `media`, `games`, `pets`, `fun`, `home` or `system`) so it shows under that tab in the store; without one it goes under "other".
- Every package the commands need goes in `requires`. CI checks that the packages exist in Arch
  and warns about programs whose package isn't declared.
- Updates raise the version. If an update changes the commands or packages, the app asks users to
  approve it again.
- Values go into commands as `${sh(value)}`, outside any quotes, or as numbers (`${int(n)}`):
  anything else could run whatever a server or a file sends. CI rejects it.
- No hidden or surprising behavior. Commands that pipe downloads into a shell or run
  downloaded files, delete recursively, ask for root, decode base64 or use `eval` are flagged, and need a good reason and
  a clear description.
- No personal data: tokens, personal paths or a hard-coded location.

## What the review looks at

Widgets run shell commands inside the phone's Arch system, not with Android permissions. They
can still read and change files there, and use the network. Reviewers read every command; the
CI summary lists them all, with anything risky flagged.

## Layout

```
widgets/<author>/<name>/widget.owl    the widget
widgets/<author>/<name>/preview.png   optional screenshot
widgets/<author>/<name>/previews/     optional screenshots per Omarchy theme (<theme>.webp)
apps/<author>/<name>/app.owl          an app, with preview.png and previews/ like a widget's
order.txt                             the order of the store
docs/LANGUAGE.md                      the widget language
w/index.html                          where a shared widget's link lands: shows it, opens the launcher
tools/owl.jar                         the checker CI runs on widgets (built from the app's owl module)
tools/owl-apps.jar                    the newer checker CI runs on apps (owl 8); it replaces owl.jar
                                      once the launcher that reads apps is out
runtimes/quickshell/                  OWL for Quickshell on Linux: the same widgets, drawn
                                      by Quickshell (Omarchy Mobile's widget board uses it)
```
