# Drop (Massdrop) "Vast" 35" Ultrawide — a measured reference

A measured reference for the **Drop/Massdrop Vast 35-inch curved ultrawide**
(3440x1440, 100 Hz, AU Optronics VA, 1800R, 2017) — a monitor for which **no user manual
appears to have ever been published**.

Drop was acquired by Corsair in 2023; the product page now redirects away, and the
community threads that held most of the practical knowledge (~3,500 posts) are
effectively inaccessible. This repo exists so the information is not lost.

Everything here was measured on real hardware over DisplayPort, or photographed off the
monitor's own on-screen display, or researched with sources cited. Claims carry provenance labels — see [Provenance](#provenance). The headline table
below is a summary; the labels live in the documents it links to.

## Headline findings

| Question | Answer |
|---|---|
| **Does it have speakers?** | **No** — but it has an undocumented **3.5 mm line-out jack**. Drop's own spec sheet says only "Speakers: None" and never mentions the jack. |
| **Does DisplayPort audio work?** | **Yes — measured.** DisplayPort audio drives the 3.5 mm jack and plays through headphones. But **macOS has no native volume control for it**; the monitor's OSD `Volume` is the only one, and it sits at 50 on this unit, which is loud. |
| **Firmware version?** | **`V0.1`**, shown in the OSD header. No other source we could reach reports a version number for this monitor. |
| **Is there a firmware update?** | **No.** None was ever published. Drop had AUO rewrite the controller firmware *at the factory* before shipping; users who asked for patches got nothing. |
| **Does DDC/CI work?** | **Barely.** At ~120 ms pacing it answers **at most one** transaction per power event, then returns Null Messages until power-cycled. Process churn is excluded; **pacing is NOT** (the gap probes ran sequentially on an already-wedged bus), and **the host is not excluded either** — this may be Apple Silicon's DCP rather than the display. Not a usable control path regardless. |
| **What is "LOS"?** | **Still unknown.** An undocumented setting with values 1/2/3 under `Other Settings`. `LOS 3` is reported to fix DP no-signal hangs. "Loss of Signal" is a guess. |
| **Why does it identify as "DP"?** | Its monitor-name descriptor is literally `DP`, and its EDID vendor ID `ICB` is **unregistered** — absent from the UEFI PNP registry entirely. The *EDID* was left at scaler defaults. (The picture-processing firmware was separately reworked at the factory; see the row above.) |

## Contents

- **[`docs/osd-settings.md`](docs/osd-settings.md)** — the OSD menu tree: all nine
  top-level menus transcribed from photographs. The closest thing to the manual that
  never existed, though submenu option lists were not captured.
- **[`docs/findings.md`](docs/findings.md)** — what the monitor exposes over DisplayPort:
  full EDID decode, the audio path, and the DDC/CI investigation.
- **[`docs/vendor-research.md`](docs/vendor-research.md)** — vendor and community
  research: panel identity, the unregistered vendor ID, firmware history, audio hardware.
- **[`docs/thunderbolt-dock.md`](docs/thunderbolt-dock.md)** — the Plugable USB4-HUB3A
  Thunderbolt 4 hub used for these measurements: why it is transparent to every finding,
  and why it has no firmware update path on any operating system.
- **[`photos/`](photos/)** — photographs of every OSD menu.
- **[`data/`](data/)** — the raw 256-byte EDID, its full decode, and the DDC selftest and patience captures.
- **[`tools/`](tools/)** — the two programs used, both reusable on other displays.

## Tools

Both are self-contained and were written for this investigation.

### `tools/edid_decode.py`

A dependency-free EDID decoder (base block + CEA-861 extensions): identity, timings,
chromaticity, adaptive-sync range, audio Short Audio Descriptors, speaker allocation.

```bash
python3 tools/edid_decode.py data/edid.bin
```

### `tools/ddcprobe.swift`

Read-only DDC/CI enumeration for **Apple Silicon** Macs, talking to the display over the
DisplayPort AUX I2C channel via `IOAVService`.

```bash
swiftc -O tools/ddcprobe.swift -o ddcprobe
./ddcprobe list       # external displays reachable over I2C
./ddcprobe get 10     # read one VCP code (0x10 = brightness)
./ddcprobe quickscan  # probe the ~50 codes monitors actually implement
./ddcprobe selftest   # N reads in one process — diagnoses a wedging bus
./ddcprobe patience   # escalating inter-command gaps — slow bus vs single-shot
./ddcprobe checksumtest  # unit-test the reply-checksum validator (no display needed)
```

On a multi-display Mac every command except `list` operates on the FIRST external
display found; it prints which one it selected before probing.

It is **read-only by construction**: it issues only Get VCP Feature (`0x01`) and
Capabilities Request (`0xF3`), never Set VCP Feature (`0x03`), so it cannot change a
monitor setting.

It is also **self-validating**, which turned out to matter. A naive scan of this monitor
reports "0 of 256 codes supported" — a false negative produced by the wedged bus, not a
measurement. `ddcprobe` verifies a known-good control code before scanning, re-checks it
every 16 codes, and refuses to run against a wedged bus rather than emitting a confident
zero.

## Provenance

Claims are separated by how they were established, because mixing them is how bad
reference material gets made:

- **Measured** — observed directly on hardware here (`findings.md`, `osd-settings.md`).
- **Researched** — from a cited primary or secondary source, marked CONFIRMED (read from
  a primary source) or REPORTED (secondhand) in `vendor-research.md`.
- **Inferred** — reasoning from evidence, always labelled as such.

Where our measurements contradict vendor claims, both are stated. Three known
discrepancies: the EDID claims 10 bpc while Drop's spec says 8-bit; the EDID's
adaptive-sync range reads 40–125 Hz against a marketed 49–100 Hz; and the detailed-timing
physical size field is boilerplate copied from a 32-inch 16:9 panel and is simply wrong.

## Test setup

MacBook Air (M4, macOS 26.4.1) → Plugable USB4-HUB3A Thunderbolt 4 dock → DisplayPort →
the monitor, running 3440x1440 @ 100 Hz. The dock is transparent to every finding here:
it carries the video, the audio endpoint, and the DDC/CI I2C channel without alteration.

## Contributing

Corrections welcome, especially:

- **What "LOS" actually does.** Nobody knows.
- **DDC/CI behaviour on other units** — is the one-transaction-per-power-cycle limit
  universal, or specific to firmware `V0.1`?
- **Sub-menu option lists** not captured here: `ECO Mode` (likely the FPS/RTS picture
  presets), `Color Temperature`, `Gamma`, `Aspect Ratio`, `Audio Source`, `Language`.
- **A scaler teardown.** The scaler vendor is unidentified.

If you have this monitor, `tools/ddcprobe.swift` and `tools/edid_decode.py` will tell you
what yours reports.

## Licence

Code under [MIT](LICENSE). Documentation, photographs and measurements are released into
the public domain under [CC0](LICENSE-DOCS) — this is meant to be used, quoted and
corrected freely.
