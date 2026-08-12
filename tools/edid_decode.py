"""Decode a raw 128/256-byte EDID blob into a human-readable report.

Written for the Drop/Massdrop 35" ultrawide attached over DisplayPort, but the
decoder is generic: EDID 1.3/1.4 base block plus CEA-861 extension blocks.

Usage:
    python3 tools/edid_decode.py data/edid.bin
    ioreg -lw0 | ... | python3 tools/edid_decode.py -   # hex on stdin
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

# --- CEA-861 Video Identification Codes (the subset a monitor plausibly lists) ---
VIC_TABLE: dict[int, str] = {
    1: "640x480p @ 60Hz (4:3)",
    2: "720x480p @ 60Hz (4:3)",
    3: "720x480p @ 60Hz (16:9)",
    4: "1280x720p @ 60Hz (16:9)",
    5: "1920x1080i @ 60Hz (16:9)",
    6: "720(1440)x480i @ 60Hz (4:3)",
    7: "720(1440)x480i @ 60Hz (16:9)",
    16: "1920x1080p @ 60Hz (16:9)",
    17: "720x576p @ 50Hz (4:3)",
    18: "720x576p @ 50Hz (16:9)",
    19: "1280x720p @ 50Hz (16:9)",
    20: "1920x1080i @ 50Hz (16:9)",
    21: "720(1440)x576i @ 50Hz (4:3)",
    22: "720(1440)x576i @ 50Hz (16:9)",
    31: "1920x1080p @ 50Hz (16:9)",
    32: "1920x1080p @ 24Hz (16:9)",
    33: "1920x1080p @ 25Hz (16:9)",
    34: "1920x1080p @ 30Hz (16:9)",
}

AUDIO_FORMATS: dict[int, str] = {
    1: "LPCM (uncompressed)",
    2: "AC-3",
    3: "MPEG-1",
    4: "MP3",
    5: "MPEG-2",
    6: "AAC LC",
    7: "DTS",
    8: "ATRAC",
    9: "DSD (One Bit Audio)",
    10: "Enhanced AC-3 (DD+)",
    11: "DTS-HD",
    12: "MAT (Dolby TrueHD)",
    13: "DST",
    14: "WMA Pro",
}

SAMPLE_RATES = [32.0, 44.1, 48.0, 88.2, 96.0, 176.4, 192.0]

SPEAKERS = [
    "FL/FR (front left/right)",
    "LFE (subwoofer)",
    "FC (front center)",
    "RL/RR (rear left/right)",
    "RC (rear center)",
    "FLC/FRC (front left/right center)",
    "RLC/RRC (rear left/right center)",
    "FLW/FRW (front left/right wide)",
]

CEA_BLOCK_TAGS: dict[int, str] = {
    1: "Audio Data Block",
    2: "Video Data Block",
    3: "Vendor Specific Data Block",
    4: "Speaker Allocation Data Block",
    5: "VESA DTC Data Block",
    7: "Extended Tag",
}

EXTENDED_TAGS: dict[int, str] = {
    0: "Video Capability Data Block",
    1: "Vendor-Specific Video Data Block",
    5: "Colorimetry Data Block",
    6: "HDR Static Metadata Data Block",
    7: "HDR Dynamic Metadata Data Block",
    13: "Video Format Preference Data Block",
    14: "YCbCr 4:2:0 Video Data Block",
    15: "YCbCr 4:2:0 Capability Map Data Block",
    18: "HDMI Audio Data Block",
    32: "InfoFrame Data Block",
}

DIGITAL_INTERFACES: dict[int, str] = {
    0: "undefined",
    1: "DVI",
    2: "HDMI-a",
    3: "HDMI-b",
    4: "MDDI",
    5: "DisplayPort",
}

BIT_DEPTHS: dict[int, str] = {
    0: "undefined",
    1: "6 bits per colour",
    2: "8 bits per colour",
    3: "10 bits per colour",
    4: "12 bits per colour",
    5: "14 bits per colour",
    6: "16 bits per colour",
}

ESTABLISHED_TIMINGS: list[tuple[int, int, str]] = [
    (0, 7, "720x400 @ 70Hz"),
    (0, 6, "720x400 @ 88Hz"),
    (0, 5, "640x480 @ 60Hz"),
    (0, 4, "640x480 @ 67Hz"),
    (0, 3, "640x480 @ 72Hz"),
    (0, 2, "640x480 @ 75Hz"),
    (0, 1, "800x600 @ 56Hz"),
    (0, 0, "800x600 @ 60Hz"),
    (1, 7, "800x600 @ 72Hz"),
    (1, 6, "800x600 @ 75Hz"),
    (1, 5, "832x624 @ 75Hz"),
    (1, 4, "1024x768 @ 87Hz (interlaced)"),
    (1, 3, "1024x768 @ 60Hz"),
    (1, 2, "1024x768 @ 70Hz"),
    (1, 1, "1024x768 @ 75Hz"),
    (1, 0, "1280x1024 @ 75Hz"),
    (2, 7, "1152x870 @ 75Hz (Apple)"),
]


def _hdr(title: str) -> str:
    return f"\n{title}\n{'=' * len(title)}"


def _sub(title: str) -> str:
    return f"\n{title}\n{'-' * len(title)}"


def manufacturer_id(word: int) -> str:
    """Decode the packed 3x5-bit PnP manufacturer ID."""
    return "".join(chr(((word >> shift) & 0x1F) + ord("A") - 1) for shift in (10, 5, 0))


@dataclass(frozen=True)
class Timing:
    """A Detailed Timing Descriptor, fully unpacked."""

    pixel_clock_khz: int
    h_active: int
    h_blank: int
    v_active: int
    v_blank: int
    h_front_porch: int
    h_sync_width: int
    v_front_porch: int
    v_sync_width: int
    h_size_mm: int
    v_size_mm: int
    interlaced: bool

    @property
    def h_total(self) -> int:
        return self.h_active + self.h_blank

    @property
    def v_total(self) -> int:
        return self.v_active + self.v_blank

    @property
    def refresh_hz(self) -> float:
        divisor = self.h_total * self.v_total
        if divisor == 0:
            return 0.0
        return self.pixel_clock_khz * 1000.0 / divisor

    def describe(self) -> str:
        scan = "interlaced" if self.interlaced else "progressive"
        diag_mm = (self.h_size_mm**2 + self.v_size_mm**2) ** 0.5
        return (
            f"{self.h_active}x{self.v_active} @ {self.refresh_hz:.2f}Hz ({scan})\n"
            f"      pixel clock : {self.pixel_clock_khz / 1000:.3f} MHz\n"
            f"      horizontal  : active {self.h_active}, blank {self.h_blank}, "
            f"total {self.h_total} (front porch {self.h_front_porch}, "
            f"sync {self.h_sync_width})\n"
            f"      vertical    : active {self.v_active}, blank {self.v_blank}, "
            f"total {self.v_total} (front porch {self.v_front_porch}, "
            f"sync {self.v_sync_width})\n"
            f"      h-freq      : {self.pixel_clock_khz / self.h_total:.3f} kHz\n"
            f"      image size  : {self.h_size_mm} x {self.v_size_mm} mm "
            f"({diag_mm / 25.4:.1f}\" diagonal)"
        )


def parse_dtd(d: bytes) -> Timing:
    """Unpack an 18-byte Detailed Timing Descriptor."""
    pixel_clock_khz = ((d[1] << 8) | d[0]) * 10
    h_active = ((d[4] >> 4) << 8) | d[2]
    h_blank = ((d[4] & 0x0F) << 8) | d[3]
    v_active = ((d[7] >> 4) << 8) | d[5]
    v_blank = ((d[7] & 0x0F) << 8) | d[6]
    h_front_porch = ((d[11] >> 6) << 8) | d[8]
    h_sync_width = (((d[11] >> 4) & 0x03) << 8) | d[9]
    v_front_porch = (((d[11] >> 2) & 0x03) << 4) | (d[10] >> 4)
    v_sync_width = ((d[11] & 0x03) << 4) | (d[10] & 0x0F)
    h_size_mm = ((d[14] >> 4) << 8) | d[12]
    v_size_mm = ((d[14] & 0x0F) << 8) | d[13]
    return Timing(
        pixel_clock_khz=pixel_clock_khz,
        h_active=h_active,
        h_blank=h_blank,
        v_active=v_active,
        v_blank=v_blank,
        h_front_porch=h_front_porch,
        h_sync_width=h_sync_width,
        v_front_porch=v_front_porch,
        v_sync_width=v_sync_width,
        h_size_mm=h_size_mm,
        v_size_mm=v_size_mm,
        interlaced=bool(d[17] & 0x80),
    )


def _descriptor_text(d: bytes) -> str:
    raw = d[5:18].split(b"\n")[0]
    return raw.decode("ascii", errors="replace").rstrip()


def decode_descriptor(d: bytes, index: int, out: list[str]) -> None:
    """Decode one 18-byte descriptor slot (timing or display descriptor)."""
    if d[0] != 0 or d[1] != 0:
        out.append(f"  [{index}] Detailed Timing: {parse_dtd(d).describe()}")
        return

    kind = d[3]
    if kind == 0xFC:
        out.append(f"  [{index}] Display Name          : {_descriptor_text(d)!r}")
    elif kind == 0xFF:
        out.append(f"  [{index}] Display Serial Number : {_descriptor_text(d)!r}")
    elif kind == 0xFE:
        out.append(f"  [{index}] Unspecified Text      : {_descriptor_text(d)!r}")
    elif kind == 0xFD:
        formula = {
            0x00: "default GTF",
            0x01: "range limits only (no timing formula)",
            0x02: "secondary GTF",
            0x04: "CVT",
        }.get(d[10], f"unknown (0x{d[10]:02x})")
        out.append(f"  [{index}] Display Range Limits:")
        out.append(f"      vertical refresh : {d[5]}-{d[6]} Hz")
        out.append(f"      horizontal rate  : {d[7]}-{d[8]} kHz")
        out.append(f"      max pixel clock  : {d[9] * 10} MHz")
        out.append(f"      timing formula   : {formula}")
    elif kind == 0x10:
        out.append(f"  [{index}] (unused / dummy descriptor)")
    else:
        out.append(f"  [{index}] Descriptor type 0x{kind:02x}: {d.hex()}")


def decode_base_block(e: bytes, out: list[str]) -> None:
    """Decode the 128-byte EDID 1.x base block."""
    out.append(_hdr("EDID BASE BLOCK (block 0)"))

    header_ok = e[0:8] == bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
    checksum_ok = sum(e[0:128]) % 256 == 0
    out.append(f"  header valid   : {header_ok}")
    out.append(f"  checksum valid : {checksum_ok} (sum mod 256 = {sum(e[0:128]) % 256})")

    out.append(_sub("Vendor / product identity"))
    out.append(f"  Manufacturer ID   : {manufacturer_id((e[8] << 8) | e[9])}")
    out.append(f"  Product code      : 0x{e[11]:02x}{e[10]:02x} ({(e[11] << 8) | e[10]})")
    serial = int.from_bytes(e[12:16], "little")
    out.append(f"  Serial number     : {serial}" + ("  (not programmed)" if serial == 0 else ""))
    out.append(f"  Manufactured      : week {e[16]}, year {e[17] + 1990}")
    out.append(f"  EDID version      : {e[18]}.{e[19]}")

    out.append(_sub("Basic display parameters"))
    video_input = e[20]
    if video_input & 0x80:
        depth = BIT_DEPTHS.get((video_input >> 4) & 0x07, "reserved")
        iface = DIGITAL_INTERFACES.get(video_input & 0x0F, "reserved")
        out.append(f"  Input type        : digital, {iface}")
        out.append(f"  Colour bit depth  : {depth}")
    else:
        out.append("  Input type        : analog")
    diag_in = ((e[21] ** 2 + e[22] ** 2) ** 0.5) / 2.54
    out.append(f"  Screen size       : {e[21]} x {e[22]} cm  ({diag_in:.1f}\" diagonal)")
    out.append(f"  Aspect ratio      : {e[21] / e[22]:.2f}:1")
    out.append(f"  Display gamma     : {(e[23] + 100) / 100:.2f}")

    features = e[24]
    out.append("  Feature flags     :")
    out.append(f"      standby supported          : {bool(features & 0x80)}")
    out.append(f"      suspend supported          : {bool(features & 0x40)}")
    out.append(f"      active-off / very low power: {bool(features & 0x20)}")
    out.append(f"      sRGB is default colourspace: {bool(features & 0x04)}")
    out.append(f"      preferred timing is native : {bool(features & 0x02)}")
    out.append(
        "      continuous frequency       : "
        f"{bool(features & 0x01)}"
        "   (EDID 1.4: accepts continuous timings, the basis for adaptive-sync;\n"
        "                                    EDID 1.3: means default-GTF support instead)"
    )

    out.append(_sub("Chromaticity (CIE 1931 xy)"))
    lo1, lo2 = e[25], e[26]
    coords = {
        "Red  ": (((lo1 >> 6) & 0x03) | (e[27] << 2), ((lo1 >> 4) & 0x03) | (e[28] << 2)),
        "Green": (((lo1 >> 2) & 0x03) | (e[29] << 2), (lo1 & 0x03) | (e[30] << 2)),
        "Blue ": (((lo2 >> 6) & 0x03) | (e[31] << 2), ((lo2 >> 4) & 0x03) | (e[32] << 2)),
        "White": (((lo2 >> 2) & 0x03) | (e[33] << 2), (lo2 & 0x03) | (e[34] << 2)),
    }
    for name, (x_raw, y_raw) in coords.items():
        out.append(f"  {name}  x={x_raw / 1024:.4f}  y={y_raw / 1024:.4f}")

    out.append(_sub("Established timings (legacy VESA modes)"))
    established = [
        label for byte_idx, bit, label in ESTABLISHED_TIMINGS if e[35 + byte_idx] & (1 << bit)
    ]
    for label in established:
        out.append(f"  - {label}")
    if not established:
        out.append("  (none)")

    out.append(_sub("Standard timings"))
    any_std = False
    for i in range(8):
        b0, b1 = e[38 + i * 2], e[39 + i * 2]
        if b0 == 0x01 and b1 == 0x01:
            continue
        any_std = True
        h_res = (b0 + 31) * 8
        ratio = {0: "16:10", 1: "4:3", 2: "5:4", 3: "16:9"}[(b1 >> 6) & 0x03]
        refresh = (b1 & 0x3F) + 60
        v_res = {"16:10": h_res * 10 // 16, "4:3": h_res * 3 // 4, "5:4": h_res * 4 // 5, "16:9": h_res * 9 // 16}[ratio]
        out.append(f"  - {h_res}x{v_res} @ {refresh}Hz ({ratio})")
    if not any_std:
        out.append("  (none)")

    out.append(_sub("Descriptor blocks"))
    for i in range(4):
        decode_descriptor(e[54 + i * 18 : 72 + i * 18], i, out)

    out.append(_sub("Trailer"))
    out.append(f"  Extension blocks  : {e[126]}")
    out.append(f"  Checksum byte     : 0x{e[127]:02x}")


def _decode_audio_block(payload: bytes, out: list[str]) -> None:
    for i in range(0, len(payload) - 2, 3):
        sad = payload[i : i + 3]
        fmt_code = (sad[0] >> 3) & 0x0F
        channels = (sad[0] & 0x07) + 1
        fmt = AUDIO_FORMATS.get(fmt_code, f"reserved ({fmt_code})")
        rates = [f"{r}" for idx, r in enumerate(SAMPLE_RATES) if sad[1] & (1 << idx)]
        out.append(f"      Short Audio Descriptor #{i // 3 + 1}")
        out.append(f"        format       : {fmt}")
        out.append(f"        max channels : {channels}")
        out.append(f"        sample rates : {', '.join(rates)} kHz")
        if fmt_code == 1:
            depths = [d for idx, d in enumerate((16, 20, 24)) if sad[2] & (1 << idx)]
            out.append(f"        bit depths   : {', '.join(str(d) for d in depths)}-bit")
            peak = max(SAMPLE_RATES[i] for i in range(7) if sad[1] & (1 << i))
            out.append(
                f"        max bitrate  : {channels} ch x {peak} kHz x "
                f"{max(depths)} bit = {channels * peak * max(depths) / 1000:.2f} Mbit/s"
            )
        else:
            out.append(f"        max bitrate  : {sad[2] * 8} kbit/s")


def _decode_cea_data_block(block: bytes, out: list[str]) -> None:
    tag = (block[0] >> 5) & 0x07
    payload = block[1:]
    name = CEA_BLOCK_TAGS.get(tag, f"Reserved (tag {tag})")

    if tag == 7 and payload:
        ext = payload[0]
        name = EXTENDED_TAGS.get(ext, f"Extended tag {ext}")
        out.append(f"    {name}  (len {len(payload) - 1})")
        out.append(f"      raw: {payload[1:].hex()}")
        return

    out.append(f"    {name}  (len {len(payload)})")

    if tag == 1:
        _decode_audio_block(payload, out)
    elif tag == 2:
        for vic_byte in payload:
            vic = vic_byte & 0x7F
            native = " [NATIVE]" if vic_byte & 0x80 else ""
            out.append(f"      VIC {vic:3d}: {VIC_TABLE.get(vic, 'unknown')}{native}")
    elif tag == 3 and len(payload) >= 3:
        oui = f"{payload[2]:02X}-{payload[1]:02X}-{payload[0]:02X}"
        known = {"00-0C-03": "HDMI Licensing LLC (HDMI 1.4)", "C4-5D-D8": "HDMI Forum (HDMI 2.x)"}
        out.append(f"      IEEE OUI     : {oui}  {known.get(oui, '')}")
        if oui == "00-0C-03" and len(payload) >= 5:
            out.append(
                f"      CEC physical address: "
                f"{payload[3] >> 4}.{payload[3] & 0xF}.{payload[4] >> 4}.{payload[4] & 0xF}"
            )
        out.append(f"      raw payload  : {payload.hex()}")
    elif tag == 4 and payload:
        present = [s for idx, s in enumerate(SPEAKERS) if payload[0] & (1 << idx)]
        out.append(f"      speakers declared: {', '.join(present) if present else '(none)'}")
    else:
        out.append(f"      raw: {payload.hex()}")


def decode_cea_extension(e: bytes, block_no: int, out: list[str]) -> None:
    """Decode a 128-byte CEA-861 extension block."""
    out.append(_hdr(f"CEA-861 EXTENSION (block {block_no})"))
    out.append(f"  Revision          : {e[1]}")
    out.append(f"  Checksum valid    : {sum(e) % 256 == 0}")

    flags = e[3]
    out.append(_sub("Capability flags"))
    out.append(f"  Underscan supported (IT formats) : {bool(flags & 0x80)}")
    out.append(f"  BASIC AUDIO supported            : {bool(flags & 0x40)}   <-- DP audio sink")
    out.append(f"  YCbCr 4:4:4 supported            : {bool(flags & 0x20)}")
    out.append(f"  YCbCr 4:2:2 supported            : {bool(flags & 0x10)}")
    out.append(f"  Native detailed timing count     : {flags & 0x0F}")

    dtd_offset = e[2]
    out.append(_sub("Data block collection"))
    if dtd_offset <= 4:
        out.append("  (no data blocks)")
    else:
        pos = 4
        while pos < dtd_offset:
            length = e[pos] & 0x1F
            _decode_cea_data_block(e[pos : pos + length + 1], out)
            pos += length + 1

    out.append(_sub("Detailed timings in this block"))
    pos, index = dtd_offset, 0
    while pos + 18 <= 127 and e[pos] | e[pos + 1]:
        out.append(f"  [{index}] {parse_dtd(e[pos : pos + 18]).describe()}")
        pos += 18
        index += 1
    if index == 0:
        out.append("  (none)")


def decode(blob: bytes) -> str:
    """Decode a full EDID blob (base block plus any extensions)."""
    out: list[str] = []
    out.append(f"EDID blob: {len(blob)} bytes ({len(blob) // 128} block(s))")
    decode_base_block(blob, out)
    for block_no in range(1, len(blob) // 128):
        block = blob[block_no * 128 : (block_no + 1) * 128]
        if block[0] == 0x02:
            decode_cea_extension(block, block_no, out)
        else:
            out.append(_hdr(f"EXTENSION BLOCK {block_no} (tag 0x{block[0]:02x}, not decoded)"))
            out.append(f"  raw: {block.hex()}")
    return "\n".join(out)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    source = argv[1]
    if source == "-":
        blob = bytes.fromhex("".join(sys.stdin.read().split()))
    else:
        raw = Path(source).read_bytes()
        blob = raw if raw[:2] == b"\x00\xff" else bytes.fromhex(raw.decode().strip())
    print(decode(blob))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
