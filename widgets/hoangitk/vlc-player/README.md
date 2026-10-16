# VLC player

A player tile for VLC for Android, using the phone's media session (`android.media`). It runs no
commands and needs no Linux packages.

- **Tile:** album art, title, artist, progress, previous / play-pause / next, and an animated backdrop.
  Tap `vlc ↗` to open VLC; tap anywhere else for the full-screen view.
- **Full screen:** large album art, progress, controls, a volume slider, and `vlc`, `share`, `copy`
  and `lyrics` buttons.
- **Backdrops:** 11 animated effects (waves, bars, rings, aurora, stars, rain, pulse, grid, rays,
  fireflies, spectrum), shared by the tile and the full screen. `auto` switches effect on every track change;
  the choice is remembered. The effects follow time, not the audio.

Needs notification access for the launcher, otherwise Android doesn't share VLC's session. Only VLC's
session is shown, and the buttons control it only while VLC is the active session; otherwise they open VLC.
