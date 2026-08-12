# The Thunderbolt dock in this setup — Plugable USB4-HUB3A

The monitor was driven through a **Plugable 5-in-1 Thunderbolt 4 and USB4 Hub**
(SKU `USB4-HUB3A`, Intel "Goshen Ridge" controller) rather than plugged directly into
the Mac. Documented here because the obvious first suspicion for any dock-attached
display problem is the dock, and in this case it is measurably not at fault.

## What this unit reports

Measured with `system_profiler SPThunderboltDataType` on macOS 26.4.1:

| Field | Value |
|---|---|
| Vendor / Device | Plugable / `USB4-HUB3A` |
| Vendor ID / Device ID | `0x2230` / `0x2017` |
| Device Revision | `0x3` |
| Mode | USB4 |
| **Firmware Version** | **39.82** |
| **Micro Firmware Version** | **0.85.0** (upstream port and all three downstream ports) |
| Link speed | 40 Gb/s |

## The dock is transparent to everything in this repo

It carries, without alteration:

- the DisplayPort stream at **3440x1440 @ 100 Hz**,
- the monitor's **DisplayPort audio endpoint** (macOS creates it normally), and
- the **DDC/CI I2C channel** — a Get VCP Feature request reached the monitor and
  returned a correctly-framed, checksum-valid reply through the dock.

That last point is worth stating plainly because DDC/CI is the thing most likely to be
eaten by an intermediary. It was not. The monitor's one-transaction-per-power-cycle DDC
limit described in [`findings.md`](findings.md) is the **monitor's** behaviour, not the
dock's.

**Plugging the monitor directly into the Mac would change nothing in this repo.**

## Firmware: there is no update path, on any OS

**CONFIRMED — Plugable publishes no firmware for this SKU at all.** Not a newer version,
not the current one, not a changelog.

Checked directly against primary sources: Plugable's device-firmware-updates page (which
lists eleven SKUs, **none of them Thunderbolt or USB4**), their drivers page, their
knowledge base, and their support forum. Forum searches for `firmware USB4-HUB3A`,
`firmware TBT4-HUB3C`, and `39.82` each returned **zero results**.

**The instrument was validated:** a positive control on the same search endpoint — the
bare term `firmware` — returned 50 posts spanning 2012–2025. So the zeros above are real
absences, not a broken search.

**Micro firmware `0.85.0` appears nowhere** in any source.

### Even if there were one, it would not run on an Apple Silicon Mac

Plugable's Thunderbolt firmware updaters are Windows-only, in their own words:

> "The firmware update cannot be performed on a Mac or Linux system."

And from Plugable staff on a request for Linux Vendor Firmware Service support (2022):

> "we do not have any ability to support updating the TBT3-UDZ via Mac or Linux …
> Unfortunately, I would not expect for this to change in the future."

Plugable's legacy USB-hub firmware page suggests Mac users update "through a Boot Camp
installation" — but that guidance is for USB 3.0 hubs, and **Boot Camp does not exist on
Apple Silicon**, so it is not an option here. Whether a virtual machine could do it is
**not verified**; Thunderbolt controller NVM flashing generally needs direct hardware
access that a guest does not get. Assume bare-metal Windows.

For contrast, and to correct the premise that this is a platform limitation rather than
a vendor choice: CalDigit ships a **macOS** Thunderbolt firmware updater supporting Apple
Silicon on macOS 11.2+. Different vendor, different product — cited only to show that
Windows is not inherently required.

### Two version-comparison traps

- **Do not compare 39.82 against other vendors' numbers.** Thunderbolt NVM versions are
  per-OEM builds. CalDigit ships 30.3, 39.1 and 64.1 on various products; reading "39.1"
  as older than "39.82" would be meaningless.
- **Plugable's KB mentions "NVM firmware version of 41 or higher"** — that refers to the
  **host PC's** internal Thunderbolt controller as a condition for downstream port
  behaviour on Thunderbolt 3 hosts. It is not a hub firmware version and is irrelevant on
  a USB4 Mac host.

## Known issues with this hub on Apple Silicon

From Plugable's own support forum. Notably, **none of them are ours**:

- **Monitors not waking** (2022): an M1 MacBook Pro driving two Dell displays through
  this hub. Traced to the **USB-C-to-HDMI adapters**, not the hub; replacing them fixed
  it.
- **Intermittent whole-hub dropouts** (2022): traced to Logitech Brio / StreamCam
  webcams. Plugable: "our suspicion is that the webcam somehow shuts down the USB hub
  chipset in our hubs for a second before reconnecting." Workaround is to connect the
  camera directly to the host.
- **DisplayPort via adapter is explicitly sanctioned** (2022, Plugable staff): "Our
  usb4-hub3a has been tested with our USBC-DP adapter with no issues. This configuration
  should work with any USB-C to DP adapter."

**NOT FOUND — zero reports of any kind:** ultrawide-specific problems, 100 Hz-specific
problems, DisplayPort audio problems (`USB4-HUB3A audio` → 0 results), or DDC/CI
passthrough problems with this hub.

### Ignore the "60 Hz cap" claims — they are about a different product class

Plugable staff have said "none of our docks support the 120 Hz refresh rate" and
"docking stations are typically capped at 60Hz". Those statements are about Plugable
**docking stations with onboard video outputs**, which drive displays through a Realtek
MST or DisplayLink chip. The `USB4-HUB3A` has no video IC — it tunnels DisplayPort over
Thunderbolt and hands it to whatever adapter you attach.

In the same 2023 thread, Plugable staff recommended the `USB4-HUB3A` specifically as the
escape hatch for a 5120x1440 ultrawide, precisely because it is a pure tunnel. Our
measured 3440x1440 @ 100 Hz with working DisplayPort audio and DDC/CI passthrough is
direct evidence against applying the 60 Hz framing to this hub.

## Verdict

Nothing to chase. The unit is doing everything asked of it, no update exists to install,
and Plugable's own posture on their docking stations is "if you are not currently
experiencing video issues, this update is not needed."

**The one open question**, if certainty matters more than this inference: Plugable's KB
and forum simply do not state whether 39.82 is current for revision `0x3`. Only their
support team can answer that.
