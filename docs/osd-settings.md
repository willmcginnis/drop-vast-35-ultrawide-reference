# Captured OSD settings tree — Drop/Massdrop Vast 35"

Transcribed from photographs taken 2026-08-11 (`../photos/IMG_9649..9657.jpg`),
with the monitor on the DisplayPort input at 3440x1440. This is the most complete settings list known to exist for this monitor, and it
supersedes the partial tree assembled from reviews in `vendor-research.md`. It is
**top-level state only** — several submenu option lists were not captured; see
"What was not captured" at the end.

Values shown are this unit's state at capture time, not defaults.

## OSD header

Every page shows the same three-field header:

| Field | Value | Note |
|---|---|---|
| Input | `DP` | active input |
| **Firmware** | **`V0.1`** | the monitor's own firmware version string |
| Resolution | `3440x1440@98Hz` | see the refresh-rate note below |

**The firmware version is `V0.1`.** This is the first hard version number we
have for this monitor — no external source reported one. It is consistent with
everything else about this scaler: a `0.1` that shipped and was never updated,
matching the unregistered `ICB` vendor ID and the uncustomised `"DP"` monitor
name in the EDID.

## Top-level menu (9 entries)

```
Input Source
Brightness/Contrast
Color Settings
Picture Quality Settings
Display Settings
Audio Settings
Multi-Window Settings
OSD Setting
Other Settings
```

### 1. Input Source

Radio selection; `Auto Select` was the active choice.

| Option | |
|---|---|
| **Auto Select** | active |
| DisplayPort | |
| HDMI 1 | |
| HDMI 2 | |
| HDMI 3 | |

Matches the documented I/O: 1 x DP + 3 x HDMI.

### 2. Brightness/Contrast

| Setting | Value | Type |
|---|---|---|
| Brightness | **100** | 0-100 |
| Contrast | 75 | 0-100 |
| DCR (dynamic contrast ratio) | Off | on/off |
| **Low Blue** | Off | on/off |

`Low Blue` was only single-sourced in the review research and its menu location
was unknown. **Confirmed, and it lives here** — not in a separate eye-care menu.

### 3. Color Settings

| Setting | Value |
|---|---|
| Gamma | 2.2 |
| ECO Mode | Standard |
| Color Temperature | 6500K |
| Hue | 50 |
| Saturation | 50 |

`ECO Mode` is almost certainly the picture-preset selector that reviews
described as holding FPS and RTS modes — **its option list was not captured.**

### 4. Picture Quality Settings

| Setting | Value | Note |
|---|---|---|
| Bypass | Off | likely a scaler-bypass / low-latency mode |
| Sharpness | 50 | 0-100 |
| **Response Time** | On | this is the overdrive control |
| Dynamic Noise Reduction | Off | |
| Super Resolution | 0 | upscaling sharpener |
| Dynamic Luminance Control | Off | |

`Response Time` being a plain **On/Off** with no multi-level choice matches
Tom's Hardware's observation that overdrive here is on/off only.

### 5. Display Settings

| Setting | Value |
|---|---|
| Aspect Ratio | Full Screen |

Only one entry. The research listed aspect/scaling as "not found" — it exists,
but **the option list was not captured**.

### 6. Audio Settings

| Setting | Value |
|---|---|
| Mute | Off |
| **Volume** | **50** |
| Audio Source | Auto |

This settles the audio question from the monitor's side: it exposes a real
volume control, it is **not muted**, and volume sits at the midpoint.

**`Volume` here is the ONLY volume control for DisplayPort audio.** macOS
provides no native control for this output — the keyboard volume keys and
menu-bar slider have no effect on it, because the monitor presents as a
fixed-level sink. At the default of 50 the output is loud. Measured. Combined
with the confirmed 3.5 mm line-out jack, audio over DisplayPort is fully
enabled end to end — it just needs headphones or powered speakers in the jack.

`Audio Source: Auto` presumably follows the active video input; its option list
was not captured.

### 7. Multi-Window Settings

| Setting | Value |
|---|---|
| Multi-Window | Off |
| SubWin 2 Input | |
| SubWin 3 Input | |
| SubWin 4 Input | |
| PIP Size | |
| PIP Position | |
| Swap | |

Sub-window entries are greyed/blank while Multi-Window is Off. Four windows appear addressable, matching the four `Window1..4` status blocks at
the bottom of every OSD page — suggesting PBP with up to 4 simultaneous sources
rather than only PIP. **INFERRED from the labels; multi-window was not enabled
and the behaviour was not exercised.**

### 8. OSD Setting

| Setting | Value |
|---|---|
| Language | English |
| Menu Transparency | 20 |
| OSD H Position | 50 |
| OSD V Position | 50 |
| OSD Timer | 10 |
| Menu Rotation | 0 |

All six were listed as "not found" in the review research. The language option
list was not captured.

### 9. Other Settings

| Setting | Value |
|---|---|
| DP Config | **DP 1.2** |
| FreeSync Mode | On |
| **LOS** | **LOS 3** |
| Factory Reset | (action) |

- `DP Config` is correctly on **1.2**; DP 1.1 cannot carry 3440x1440 @ 100 Hz.
- `LOS` is the undocumented setting nobody on Drop's forums could explain. This
  unit is on **LOS 3** — the same value a user reported as fixing a DisplayPort
  no-signal/boot-hang. Semantics still unknown; "Loss of Signal" remains an
  inference.

## Status footer

Every page carries a four-window status block:

```
Window1:                                Window2:
Input Source:  DP                       Input Source:
Resolution:    3440x1440@98Hz           Resolution:
Window3:                                Window4:
Input Source:                           Input Source:
Resolution:                             Resolution:
```

## Cross-check against DDC/CI — the one reading we got was correct

**The OSD shows Brightness = 100. Our single successful DDC/CI read returned
`current=100, max=100` for VCP `0x10`.** They agree exactly.

That matters for two reasons. It confirms the lone DDC transaction was a genuine
measurement rather than a coincidence of a stale buffer, and it confirms the
frame decoding in `ddcprobe` is correct — a mis-parsed reply would be unlikely
to land on the right value.

**No DDC/CI toggle appears in the captured user menus.** All nine top-level menus
were captured and none contains one; this does not exclude a hidden or service
menu. The research could not confirm this either way; it is now
**confirmed absent**. So the single-transaction-per-power-cycle behaviour is not
something that can be switched off — it is simply how this firmware behaves.

## Refresh rate: the OSD says 98 Hz, macOS says 100 Hz

Three sources disagree slightly:

| Source | Value |
|---|---|
| EDID detailed timing (computed) | 99.99 Hz |
| macOS / `displayplacer` | 100 Hz |
| **Monitor OSD** | **98 Hz** |

**INFERRED, not confirmed:** FreeSync is **On**, so the monitor may be reporting
the *instantaneous* variable refresh rate rather than the negotiated maximum. On
a mostly-static desktop the panel would legitimately be running below 100 Hz.
Testing this would mean watching the OSD reading while forcing sustained
full-rate output.

## What was not captured

Menus were photographed at their top level, so option *lists* for the following
are still unknown. Each needs one more photo with the item opened:

- `ECO Mode` — likely the FPS/RTS picture presets
- `Color Temperature` — values beyond 6500K
- `Gamma` — available preset values
- `Aspect Ratio` — options beyond Full Screen
- `Audio Source` — options beyond Auto
- `Language` — the language list
- `PIP Size`, `PIP Position`, `SubWin N Input` — need Multi-Window turned On
- The joystick-shortcut **crosshair overlay** reviews describe, which does not
  appear in any main menu
