# Drop/Massdrop "Vast" 35" — vendor and community research

External research, gathered 2026-08-11. **Nothing here was measured on this
machine** — that lives in `findings.md`. Each claim is marked CONFIRMED (read
from a primary source), REPORTED (secondhand, e.g. a search snippet), or
INFERRED.

## Identity

**CONFIRMED: the monitor is the Massdrop/Drop "Vast" 35-inch Curved Gaming
Monitor.** The `jackhumbert/massdrop-vast` GitHub repo contains a registry
export of this model's EDID, and every field in it reproduces our capture:
manufacturer bytes `24 62` → `ICB`, product `0x3500`, week 40 / year 2017,
EDID 1.4, video input byte `0xB5`, image size 82 x 35 cm. Its Windows device
instance path is `DISPLAY\ICB3500\...`.

- Panel: **AU Optronics VA, 35", 1800R** (CONFIRMED — Drop's own spec sheet).
  Drop worked directly with AUO on the design.
- Exact panel part number: **NOT CONFIRMED.** `M350QVR01.1` and `M350DVR01`
  both circulate on forums; the sources are paywalled (overclock.net returns
  HTTP 402) or 403. Same-panel siblings ASUS ROG Strix XG35VQ and BenQ
  EX3501R are confirmed.
- Scaler vendor: **NOT CONFIRMED.** No teardown or FCC internal photos found.

### "ICB" is an unregistered vendor ID

**CONFIRMED, and it explains a lot.** The authoritative UEFI Forum PNP ID
registry (2,556 entries, fetched live) contains `ICA`, `ICC`, and `ICD` — but
**no `ICB` at all**. The community `hwdata/pnp.ids` list agrees, and the
`linuxhw/EDID` corpus (655 vendor directories of real-world dumps) has no `ICB`
directory.

**INFERRED:** an unregistered three-letter ID plus a round product code
(`0x3500` — literally "35" then "00" for a 35-inch) is the signature of an
ODM/scaler-firmware default, not a brand identity. This is consistent with our
unit's monitor-name descriptor reading `"DP"`. The `jackhumbert` repo exists
precisely because the factory strings were "generic and unhelpful"; that author
replaced the name with `Massdrop_Vast`.

## Audio hardware — the chassis has a jack, not speakers

**CONFIRMED: no built-in speakers, but a real 3.5 mm audio-out jack exists.**

Drop's own product photo of the I/O panel shows, top to bottom: 3 x HDMI,
1 x DisplayPort, and beneath them a **green-ringed 3.5 mm jack** (green = line
out in the PC colour code).

The archived official spec list says:

```
Inputs: 3 x HDMI (1 x v2.0, 2 x v1.4), DisplayPort (v1.2)
Speakers: None
Power supply type: Internal PSU
```

Note the vendor spec **never mentions the jack** — it only says "Speakers:
None". The jack is real but undocumented. Review corroboration: MMORPG's spec
table says `Speakers: None` and its prose mentions "a headphone jack if you
don't have speakers"; DisplayNinja lists "Headphone Jack" and no speakers.

**NOT CONFIRMED:** whether the jack is amplified for headphones or line-level
only, and whether the HDMI inputs also route to it (probable, unverified).

## Firmware — no user-flashable path

**NOT FOUND in the sources searched** (Drop's archived product pages, their
community threads via search snippets, and general web search, 2026-08-11): no
Drop support page, download, or flashing tool. Absence of evidence across a
bounded search is not proof none ever existed. Drop's product page now 302s to a Corsair landing page; Corsair
acquired Drop in July 2023.

- Custom firmware **was** written for this monitor — but at the **factory**, by
  Drop and AUO before shipping. Drop staff described tracing ghosting to
  "poorly optimized controller firmware" and rewriting it "with their
  partners". That is a manufacturing-stage change, not an end-user path.
  (REPORTED — search snippets; the Drop threads could not be read in full.)
- Users asked for firmware patches and got nothing. One asked about a patch for
  FreeSync flickering; another contacted support and "they couldn't answer."
  (REPORTED.)
- **No service or factory menu is documented.** The community's 100 → 110/120 Hz
  overclocking was entirely GPU-side (NVIDIA Control Panel custom resolutions,
  CRU), not via a hidden OSD menu.
- **NOT CONFIRMED:** whether the scaler is physically flashable via an on-board
  I2C/ISP header. No teardown found.

## OSD menu tree (partial, assembled from reviews)

No user manual appears to have ever been published online. This is **not a
complete verified tree** — it is what reviews and user reports mention, and it
is exactly what the photographs will supersede.

**Control scheme (REPORTED — Tom's Hardware, a secondary source) — and it is
unusual:** a single
joystick. Click **up** to open the OSD; **left/right** moves up and down through
choices; **up** selects; **down** backs out. **Pressing the stick in toggles
power**, which reviewers hit by accident repeatedly. From idle, MMORPG reports
shortcuts: up = crosshair overlay, down = cycle picture presets, left = input
select, right = main menu.

| Setting | Detail | Source |
|---|---|---|
| Brightness, Contrast | Tom's calibration: Brightness 55, Contrast 44 | Tom's Hardware (REPORTED) |
| DCR (dynamic contrast) | Inside the Brightness/Contrast menu | user report |
| Colour Temp → User | R/G/B sliders; Tom's calibration R 62, G 62, B 38 | Tom's Hardware |
| Gamma presets | count/values unknown | Tom's Hardware |
| Hue / Saturation | | Tom's Hardware |
| Picture modes | includes FPS and RTS presets | DisplayNinja |
| Crosshair overlay | | MMORPG, DisplayNinja |
| Overdrive | **on/off only**, no multi-level; ships ON | Tom's Hardware |
| FreeSync | on/off toggle | Drop staff reply |
| Input select | | MMORPG |
| PIP / PBP | "use multiple inputs to simultaneously display different screens" | official Drop copy |
| Other Settings → DP Config | **1.1 / 1.2**; 1.1 cannot do 100 Hz at native res | user report |
| LOS (values 1/2/3) | reported as "in the DisplayPort submenu" — **superseded**: the photographed tree places it under `Other Settings`. Undocumented. LOS=3 fixed a DP no-signal/boot-hang for one user. "Loss of Signal" is a plausible expansion but is **INFERRED** | user report |
| Low blue light filter | **single-sourced**, menu position unknown | DisplayNinja |

**Not found in any source:** aspect/scaling options, OSD language list, OSD
timeout, OSD position/transparency, sharpness, volume control for the jack,
factory reset, and **whether a DDC/CI toggle exists**.

Multiple Drop users complained the setting names were never explained — "Like
several other settings (DCR…), I have no idea what LOS suppose to do."

## DDC/CI — a genuine null result

**No reports of DDC/CI behaviour for this monitor were found in the trackers and
searches listed below** (2026-08-11), and this was checked rather than assumed:

- GitHub issue search for "Massdrop" across `rockowitz/ddcutil`,
  `waydabber/BetterDisplay`, `alin23/Lunar`, `MonitorControl/MonitorControl`:
  **0 hits in every repo.** Control search ("Vast" in ddcutil) returned 3
  unrelated hits, so the search mechanism works.
- GitHub code search for `ICB3500`: only the `jackhumbert` repo.
- No OSD DDC/CI enable/disable toggle appears in any source. Cannot confirm one
  exists **or** that one doesn't.

So our measurements in `findings.md` appear to be **new information not
documented anywhere online**. For general context, ddcutil documents both
observed behaviours as a known class: monitors that answer with a DDC Null
Message instead of setting the unsupported-VCP bit, and monitors that require
slow pacing.

## Discrepancies between vendor claims and our EDID

1. **Refresh range.** Drop markets FreeSync as **49–100 Hz**. The archived EDID
   dump says 49–125. **Ours says 40–125** (`data/edid-decoded.txt`). The
   researcher speculated an AMD FreeSync vendor block might explain the 40 vs
   49 gap — **that is ruled out**: our CEA extension contains only Video, Audio,
   Speaker Allocation, and an HDMI 1.4 VSDB (OUI `00-0C-03`). There is no AMD
   vendor-specific block. The difference is between EDID revisions or is an
   artefact of the archived dump having been hand-edited.
2. **Bit depth.** Our EDID says **10 bpc**; Drop's spec sheet says "16.7 million
   colors (8-bit)". The EDID overstates the panel — more evidence of
   uncustomised scaler defaults. macOS drives it at 8 bpc.
3. **LFC (low framerate compensation).** Tom's Hardware says not supported;
   DisplayNinja says it is. Unresolved, minor.

## What could not be retrieved

Drop's community threads (~3,540 posts) are effectively inaccessible — the live
site redirects to Corsair and Wayback snapshots are mostly redirect pages, so
every Drop-forum claim above is from search snippets only. Overclock.net is
behind a paywall (HTTP 402), HardForum and the Linus Tech Tips thread return
403. No manual or spec-sheet PDF appears to exist online.

## Sources

- [Drop product page, archived spec sheet (Wayback, 2021)](https://web.archive.org/web/20211105221044/https://drop.com/buy/massdrop-vast-curved-gaming-monitor/details)
- [Drop official I/O panel photo](https://massdrop-s3.imgix.net/product-images/massdrop-vast-curved-gaming-monitor/nousb_20170915160854.jpg)
- [jackhumbert/massdrop-vast — EDID override repo](https://github.com/jackhumbert/massdrop-vast)
- [UEFI Forum PNP ID registry](https://uefi.org/uefi-pnp-export)
- [hwdata pnp.ids](https://github.com/vcrhonek/hwdata/blob/master/pnp.ids)
- [linuxhw/EDID vendor corpus](https://github.com/linuxhw/EDID)
- [MMORPG.com review](https://www.mmorpg.com/hardware-reviews/massdrop-vast-35-inch-ultrawide-gaming-monitor-1440p-ultrawide-you-can-actually-afford-2000107326)
- [DisplayNinja review](https://www.displayninja.com/massdrop-vast-review/)
- [Tom's Hardware](https://www.tomshardware.com/news/massdrop-vast-35-inch-gaming-monitor,35711.html)
- [Blur Busters](https://blurbusters.com/the-massdrop-vast-a-35-2ms-va-100hz-freesync-ultrawide-monitor/)
- [ddcutil — DDC Null Message](https://www.ddcutil.com/ddc_null_response/)
- [ddcutil — monitor notes](https://www.ddcutil.com/archived/monitor_notes/)
