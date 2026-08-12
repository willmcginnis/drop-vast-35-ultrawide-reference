# What the Drop/Massdrop "Vast" 35" ultrawide exposes over DisplayPort

The monitor is confirmed as the **Massdrop/Drop "Vast" 35" Curved Gaming
Monitor** (AU Optronics VA panel, 1800R, 2017). Vendor and community research —
audio hardware, firmware, the OSD tree, panel identity — is in
`vendor-research.md`, kept separate because none of it was measured here.

Measured 2026-08-11 on a MacBook Air (M4, macOS 26.4.1) with the monitor
attached through a **Plugable USB4-HUB3A Thunderbolt 4 dock**.

Everything below is measured on this machine unless explicitly marked as
inferred. Raw captures live in `data/`.

---

## 1. The link, as macOS sees it

| Property | Value |
|---|---|
| Connection | DisplayPort (via TB4 dock, 40 Gb/s upstream) |
| Active mode | 3440x1440 @ 100 Hz, 8 bpc, unscaled |
| Reported size | 35-inch external screen |
| Active timing pixel clock | 533.1 MHz (the EDID range descriptor separately declares a 650 MHz maximum) |
| Dock | Plugable USB4-HUB3A, firmware 39.82, micro 0.85.0 |

The dock is **not** in the way of anything measured here. It carries the DP
stream, the audio endpoint, and the DDC/CI I2C channel. Plugging the monitor
directly into the Mac would not change any finding in this document.

## 2. Monitor identity (from EDID)

| Field | Value |
|---|---|
| Manufacturer ID | `ICB` |
| Product code | `0x3500` (13568) |
| Serial number | 0 — **not programmed** |
| Manufactured | Week 40, 2017 |
| EDID version | 1.4 |
| Display name string | `"DP"` |
| Input | Digital, DisplayPort, **10 bits per colour** |
| Panel size | 82 x 35 cm (35.1" diagonal), 2.34:1 |
| Gamma | 2.20, sRGB is the default colour space |

Both EDID block checksums are valid, so this is a clean read, not a corrupted one.

### The EDID is sloppily authored

Three independent signs that the vendor did a minimal job, which matters because
it predicts the DDC/CI behaviour in section 4:

- The **display name is literally `"DP"`** — the connector type, not a model
  name. This is why macOS's Sound and Displays panels call the monitor "DP".
- The **serial number is 0**, so the panel is not individually identifiable.
- The **detailed-timing image size says 708 x 399 mm** (32.0" diagonal, 1.77:1)
  while the base block says 82 x 35 cm (35.1", 2.34:1). The 708x399 figure is
  boilerplate carried over from a 32-inch 16:9 EDID and is simply wrong for this
  panel. The base-block value is the correct one.

### Colour primaries (CIE 1931)

| | x | y |
|---|---|---|
| Red | 0.6572 | 0.3311 |
| Green | 0.3018 | 0.6230 |
| Blue | 0.1465 | 0.0557 |
| White | 0.3125 | 0.3281 |

White point is D65. The primaries are slightly wider than sRGB: computing
triangle areas in CIE 1931 xy from these values gives **~110% of sRGB area and
~81% of DCI-P3 area**. Coverage (intersection) would be lower still than the
latter. Drop's spec sheet claims "100% sRGB Coverage" — note that area and
coverage are different measures. None of this is a colorimeter measurement; it is
arithmetic on the EDID's own claimed chromaticity.

### Adaptive sync

The Display Range Limits descriptor declares a **40-125 Hz** vertical range with
continuous frequency support, and macOS reflects this
(`SupportsVariableRefreshRate = Yes`). The panel's actual maximum mode is 100 Hz,
so the usable VRR window is **40-100 Hz**.

### Modes offered

The native timing is **3440x1440 @ 99.99 Hz** (533.1 MHz pixel clock,
148.083 kHz horizontal). A 60 Hz variant of the same resolution is the second
detailed timing. The CEA extension adds 2560x1440 at 60 and 100 Hz, 1920x1080 at
60 and 100 Hz, plus legacy TV modes. macOS exposes 164 total mode entries.

Full decode: `data/edid-decoded.txt`.

## 3. Audio over DisplayPort — yes, and it is already working

This was an open question. It is settled: **the monitor is a working DisplayPort
audio sink, and it is currently macOS's default output device.**

Evidence from the CEA-861 extension block:

- **Basic audio flag: set.**
- **Short Audio Descriptor:** LPCM, **8 channels**, sample rates 32 / 44.1 / 48 /
  88.2 / 96 / 176.4 / 192 kHz, bit depths 16 / 20 / 24.
- **Speaker allocation:** front-left / front-right only.

And from CoreAudio (`system_profiler SPAudioDataType`):

```
DP:
  Default Output Device: Yes
  Default System Output Device: Yes
  Manufacturer: ICB
  Output Channels: 8
  Current SampleRate: 48000
  Transport: DisplayPort
```

So the dock passes audio fine and no direct-to-Mac cable is needed.

**Where the sound physically goes — MEASURED, confirmed working.** The chassis
has **no speakers** but does have a **3.5 mm line-out jack** (green-ringed,
visible in Drop's own I/O panel photo). DisplayPort audio routes to that jack and
plays correctly through headphones — verified by plugging them in.

**Important usability caveat, also measured: macOS provides no native volume
control for this output.** The keyboard volume keys and the menu-bar slider do
not affect it, because the monitor presents itself as a fixed-level DisplayPort
audio sink. **The monitor's own OSD `Volume` setting is the only volume control**,
and at its default of 50 the output is loud. If DisplayPort audio here is
painfully loud, that is the fix — Audio Settings → Volume in the OSD, not
anything on the Mac.

The EDID's 8-channel/192 kHz claim is scaler boilerplate: there is no 8-channel
output hardware. The **speaker-allocation field declaring only front-left/right
is the honest signal**, and it matches a stereo analogue line-out exactly.

Curiously, Drop's own spec sheet lists only "Speakers: None" and **never
mentions the jack at all** — it is real but undocumented by the vendor.

**One transient worth knowing about:** on the first probe, an `AirPlay` device
held `Default Output Device` while `DP` held only `Default System Output Device`
— i.e. system alerts went to the monitor but media went to AirPlay. AirPlay
devices appear and disappear as targets are discovered. If audio goes missing
again, check Sound settings for an AirPlay target having grabbed the default.

## 4. DDC/CI — partially supported, and fragile

DDC/CI is the VESA protocol that lets the host read and set the monitor's OSD
settings over the DisplayPort AUX channel. `tools/ddcprobe.swift` talks to it via
Apple's private `IOAVService` I2C API.

Three measured facts:

1. **The channel works.** A Get VCP Feature request for brightness (`0x10`)
   returned a well-formed reply with a valid checksum:
   `6e 88 02 00 10 00 00 64 00 64 a4` — brightness 100, maximum 100.
   DDC/CI therefore reaches the monitor *through the Thunderbolt dock*.

2. **The capabilities string did not answer.** A Capabilities Request (opcode
   `0xF3`) **at offset 0** was answered with a **DDC/CI Null Message**
   (`6e 80 be`) at reply delays of 50, 100, 200 and 400 ms and read sizes of
   64/40/38/32 bytes.

   **Whether that means "not implemented" is NOT established.** Two reasons.
   The prober stops at the first Null Message, so no offset beyond 0 was ever
   requested — an earlier revision of this document claimed "every offset",
   which the shipped tool cannot do. And a Null Message is demonstrably *not* a
   reliable "unsupported" signal on this display: point 3 below shows it
   returning Null for `0x10`, a code it had just answered. So this observation
   is not separable from the wedge.

   Either way the practical consequence stands: the monitor never told us which
   VCP codes it supports, so they would have to be discovered one at a time.

3. **Something wedges the DDC engine, and the cause is NOT yet established.**
   After the capabilities sweep and a 256-code scan, the monitor began answering
   *every* code — including the brightness code that had just worked — with a
   Null Message. It never recovered: 8 polls over 6 minutes of idle all failed.
   **A monitor power cycle did fix it.**

   Then the pattern repeated with a much smaller cause. After the power cycle a
   single `get 10` succeeded; the very next invocation, seconds later, failed,
   and 10 further reads at 3-second spacing all failed. So the trigger is not
   "sustained polling" — one extra transaction was enough.

   Two hypotheses fit that evidence:

   - (a) the display's DDC engine is genuinely near-single-shot per power event;
   - (b) creating and tearing down an `IOAVService` handle **per process** is
     what breaks it, and one long-lived handle would be fine.

   **`selftest` excluded (b).** Run as the first thing touching the bus after a
   power cycle, 15 reads of VCP `0x10` inside a *single* process sharing *one*
   `IOAVService` handle:

   ```
   read  1: OK   cur=100 max=100
   read  2: FAIL cur=0 max=0
   ...
   read 15: FAIL cur=0 max=0
   Passed 1/15 within one process.
   ```

   Process churn is therefore **excluded**: the failure reproduces with no
   handle teardown at all. The writes still succeed and the display still
   answers — it answers with a deliberate Null Message. It is choosing not to
   respond, not failing to receive.

   **It did NOT establish (a) on its own.** Every read in that run was ~120 ms
   apart, so "single-shot" and "needs a much longer gap" were indistinguishable.
   The one variable that separated them is **pacing.**

   **`patience` closed it.** Run as the first bus transaction after a power
   cycle, escalating the gap between reads (`data/ddc-patience.txt`):

   ```
   baseline       : OK   cur=100 max=100
   after   2s gap : FAIL
   after   5s gap : FAIL
   after  10s gap : FAIL
   after  20s gap : FAIL
   after  40s gap : FAIL
   after  80s gap : FAIL
   ```

   **But this does NOT isolate pacing, and an earlier revision wrongly said it
   did.** The gaps ran *sequentially on an already-stateful bus*: the baseline
   consumed the first transaction, then the 2-second probe ran, then the 5-second
   probe, and so on. If the 2-second probe is itself what wedges the engine, every
   later probe is measuring a bus that was already wedged rather than testing its
   own gap independently. A real isolation needs **one power cycle per gap**.

   What IS established: at ~120 ms pacing the display answers **at most one**
   transaction per power event, and process churn is excluded. Whether a long
   *first* gap behaves differently is untested — as is whether the limit belongs
   to the display at all rather than to this Mac (see the open question below). Every test so far used ~120 ms gaps, and
   some scalers need far longer (ddcutil ships "sleep multipliers" for exactly
   this class). `ddcprobe patience` escalates the gap to 2/5/10/20/40/80 s to
   test whether the bus is merely *slow* rather than single-shot. It must also
   run first after a power cycle.

Whatever the cause, a naive scan produces
"0 of 256 codes supported", which is a **false negative** produced by the
instrument, not a fact about the monitor. `ddcprobe` now defends against this:

- It verifies a known-good control code before starting and **refuses to run**
  if the control does not answer.
- It re-checks the control every 16 codes and backs off on a detected wedge.
- It reports whether the control was still alive at the end.
- A `quickscan` mode probes only the ~50 VCP codes real monitors implement,
  cutting bus traffic by roughly 80%.

### Status of the VCP enumeration

**Abandoned as impractical, and it no longer matters.** At ~120 ms pacing the
display answers at most one DDC transaction per power event, so probing 51 codes
would need 51 power cycles. DDC/CI is therefore not a usable
control path on this monitor — and the OSD photographs (`osd-settings.md`) give
the complete settings tree anyway, which is what the enumeration was for.

**The one VCP reading we did get is confirmed correct.** DDC reported
brightness `current=100, max=100`; the OSD independently shows Brightness = 100.
Exact agreement, which validates both the reading and `ddcprobe`'s frame
decoding.

**No DDC/CI toggle exists in the OSD** — all nine menus were captured and none
contains one, so this behaviour cannot be switched off.

## 5. Reproducing any of this

```bash
# Pull the raw EDID from the IORegistry
ioreg -lw0 | grep -m1 '"EDID" = <' | sed -e 's/.*"EDID" = <//' -e 's/>.*//' \
  | tr -d ' \n' > edid.hex
python3 -c "import pathlib; pathlib.Path('edid.bin').write_bytes(
    bytes.fromhex(pathlib.Path('edid.hex').read_text().strip()))"

python3 tools/edid_decode.py edid.bin      # full human-readable EDID report

swiftc -O tools/ddcprobe.swift -o ddcprobe
./ddcprobe list        # external displays reachable over I2C
./ddcprobe get 10      # read a single VCP code
./ddcprobe quickscan   # gentle, self-validating VCP enumeration
```

`ddcprobe` is **read-only by construction**: it issues only Get VCP Feature
(`0x01`) and Capabilities Request (`0xF3`), never Set VCP Feature (`0x03`), so it
cannot alter a monitor setting.
