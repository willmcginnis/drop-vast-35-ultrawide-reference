// ddcprobe — read-only DDC/CI enumeration for Apple Silicon Macs.
//
// Talks to the display over the DisplayPort AUX I2C channel using Apple's
// private IOAVService API (the same path m1ddc / BetterDisplay / Lunar use).
// Everything here is READ-ONLY: it issues only "Get VCP Feature" (0x01) and
// "Capabilities Request" (0xF3). It never issues "Set VCP Feature" (0x03), so
// it cannot change a monitor setting.
//
// Build:  swiftc -O tools/ddcprobe.swift -o build/ddcprobe
// Usage:  build/ddcprobe list
//         build/ddcprobe caps
//         build/ddcprobe scan
//         build/ddcprobe get <hex-vcp-code>

import Foundation
import IOKit

typealias IOAVService = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> IOAVService?

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(
    _ service: IOAVService, _ chipAddress: UInt32, _ offset: UInt32,
    _ outputBuffer: UnsafeMutableRawPointer?, _ outputBufferSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(
    _ service: IOAVService, _ chipAddress: UInt32, _ dataAddress: UInt32,
    _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32
) -> IOReturn

// DDC/CI on the I2C bus: display slave 0x6E (8-bit) == 0x37 (7-bit),
// host source address 0x51.
let ddcChipAddress: UInt32 = 0x37
let ddcDataAddress: UInt32 = 0x51
let ddcDestination: UInt8 = 0x6E
let ddcSource: UInt8 = 0x51

// Per DDC/CI the host must pause between a request and its reply, and again
// before the next command. This monitor's DDC engine WEDGES under fast polling
// (it starts answering every code with a Null Message), so these are set well
// above the 40ms spec minimum and are deliberately conservative.
let replyDelay: UInt32 = 100_000  // microseconds
let interCommandDelay: UInt32 = 120_000

/// A code the monitor is known to answer, used as a positive control so a
/// wedged bus can never masquerade as "nothing is supported".
let controlVCPCode: UInt8 = 0x10

/// The VCP codes real desktop monitors actually implement. Probing this set
/// instead of all 256 cuts bus traffic by ~80%, which matters because this
/// display's DDC engine wedges under sustained polling.
let commonVCPCodes: [UInt8] = [
    0x02, 0x04, 0x05, 0x08, 0x0B, 0x0C, 0x0E, 0x10, 0x12, 0x14, 0x16, 0x18,
    0x1A, 0x1E, 0x20, 0x30, 0x3E, 0x52, 0x54, 0x60, 0x62, 0x63, 0x66, 0x68,
    0x6B, 0x6C, 0x6E, 0x70, 0x72, 0x86, 0x87, 0x8A, 0x8D, 0x90, 0xAA, 0xAC,
    0xAE, 0xB0, 0xB2, 0xB4, 0xB6, 0xC0, 0xC6, 0xC8, 0xC9, 0xCA, 0xCC, 0xD6,
    0xDA, 0xDC, 0xDF,
]

struct Discovered {
    let location: String
    let displayAttributes: String
    let service: IOAVService
}

func registryProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
}

/// Find every external DCPAVServiceProxy — one per attached external display.
func discoverServices() -> [Discovered] {
    var found: [Discovered] = []
    var iterator = io_iterator_t()
    let matching = IOServiceMatching("DCPAVServiceProxy")
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
    else {
        return found
    }
    var entry = IOIteratorNext(iterator)
    while entry != 0 {
        let location = registryProperty(entry, "Location") as? String ?? "(none)"
        var name = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(entry, &name)
        let entryName = String(cString: name)
        if location == "External", let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) {
            found.append(Discovered(location: location, displayAttributes: entryName, service: service))
        }
        IOObjectRelease(entry)
        entry = IOIteratorNext(iterator)
    }
    IOObjectRelease(iterator)
    return found
}

/// The only DDC/CI opcodes this tool is permitted to transmit. Get VCP Feature
/// and Capabilities Request are both reads; Set VCP Feature (0x03) would change
/// a monitor setting and is deliberately absent.
let permittedOpcodes: Set<UInt8> = [0x01, 0xF3]

/// Frame a DDC/CI payload and write it to the display.
///
/// The guard below is what makes "read-only by construction" literally true
/// rather than merely true today: any future edit that tries to transmit a Set
/// VCP Feature (0x03) aborts here instead of silently changing the display.
@discardableResult
func ddcWrite(_ service: IOAVService, payload: [UInt8]) -> IOReturn {
    guard let opcode = payload.first, permittedOpcodes.contains(opcode) else {
        var refusal = "REFUSING to transmit DDC opcode "
        refusal += "0x\(String(format: "%02X", payload.first ?? 0)) — this tool is "
        refusal += "read-only and may only send 0x01 (Get VCP) or 0xF3 (Capabilities).\n"
        FileHandle.standardError.write(Data(refusal.utf8))
        return kIOReturnNotPermitted
    }
    var packet: [UInt8] = [0x80 | UInt8(payload.count)]
    packet.append(contentsOf: payload)
    var checksum: UInt8 = ddcDestination ^ ddcSource
    for byte in packet { checksum ^= byte }
    packet.append(checksum)
    return IOAVServiceWriteI2C(service, ddcChipAddress, ddcDataAddress, &packet, UInt32(packet.count))
}

func ddcRead(_ service: IOAVService, count: Int) -> (IOReturn, [UInt8]) {
    var buffer = [UInt8](repeating: 0, count: count)
    let result = IOAVServiceReadI2C(service, ddcChipAddress, ddcDataAddress, &buffer, UInt32(count))
    return (result, buffer)
}

struct VCPReply {
    let resultCode: UInt8
    let vcpCode: UInt8
    let vcpType: UInt8
    let maximum: UInt16
    let current: UInt16
    let raw: [UInt8]

    var supported: Bool { resultCode == 0x00 }
    var typeName: String { vcpType == 0x01 ? "momentary" : "set-parameter" }
}

/// Issue "Get VCP Feature" and parse the 11-byte reply. Retries because the
/// AUX channel drops occasional transactions.
func getVCP(_ service: IOAVService, code: UInt8, attempts: Int = 3) -> VCPReply? {
    for _ in 0..<attempts {
        guard ddcWrite(service, payload: [0x01, code]) == KERN_SUCCESS else {
            usleep(interCommandDelay)
            continue
        }
        usleep(replyDelay)
        let (status, buffer) = ddcRead(service, count: 11)
        guard status == KERN_SUCCESS else {
            usleep(interCommandDelay)
            continue
        }
        // Null Message: the display explicitly declines this code. Return it
        // as an unsupported reply rather than retrying — it is a real answer.
        if buffer.count >= 3, buffer[0] == 0x6E, buffer[1] == 0x80, buffer[2] == 0xBE {
            return VCPReply(resultCode: 0x01, vcpCode: code, vcpType: 0,
                            maximum: 0, current: 0, raw: buffer)
        }
        // Canonical layout is `6e 88 02 ...`; fall back to a search because
        // implementations differ on whether the destination byte is returned.
        let opcodeIndex: Int
        if buffer.count >= 11, buffer[0] == 0x6E, buffer[2] == 0x02, buffer[4] == code {
            opcodeIndex = 2
        } else if let found = buffer.firstIndex(of: 0x02), found + 7 < buffer.count,
                  buffer[found + 2] == code {
            opcodeIndex = found
        } else {
            usleep(interCommandDelay)
            continue
        }
        let base = opcodeIndex
        return VCPReply(
            resultCode: buffer[base + 1],
            vcpCode: buffer[base + 2],
            vcpType: buffer[base + 3],
            maximum: (UInt16(buffer[base + 4]) << 8) | UInt16(buffer[base + 5]),
            current: (UInt16(buffer[base + 6]) << 8) | UInt16(buffer[base + 7]),
            raw: buffer
        )
    }
    return nil
}

/// Pull the full VCP capabilities string, 32 bytes at a time.
func readCapabilities(_ service: IOAVService) -> String {
    var assembled = [UInt8]()
    var offset: UInt16 = 0
    var emptyReplies = 0

    while offset < 8192 && emptyReplies < 4 {
        let payload: [UInt8] = [0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)]
        guard ddcWrite(service, payload: payload) == KERN_SUCCESS else {
            emptyReplies += 1
            usleep(interCommandDelay)
            continue
        }
        usleep(replyDelay)
        let (status, buffer) = ddcRead(service, count: 64)
        // A DDC/CI Null Message (6e 80 be) is an explicit "feature not
        // implemented" from the display — distinct from silence on the bus.
        if status == KERN_SUCCESS, buffer.count >= 3,
           buffer[0] == 0x6E, buffer[1] == 0x80, buffer[2] == 0xBE {
            FileHandle.standardError.write(
                Data("display returned a DDC/CI Null Message: VCP 0xF3 (capabilities) not implemented\n".utf8))
            return ""
        }
        guard status == KERN_SUCCESS, let opcodeIndex = buffer.firstIndex(of: 0xE3),
              opcodeIndex >= 1
        else {
            emptyReplies += 1
            usleep(interCommandDelay)
            continue
        }
        let lengthByte = buffer[opcodeIndex - 1]
        let payloadLength = Int(lengthByte & 0x7F)
        // payload = 0xE3 + 2 offset bytes + fragment
        let fragmentLength = payloadLength - 3
        guard fragmentLength > 0, opcodeIndex + 3 + fragmentLength <= buffer.count else {
            break  // zero-length fragment marks the end of the string
        }
        assembled.append(contentsOf: buffer[(opcodeIndex + 3)..<(opcodeIndex + 3 + fragmentLength)])
        offset += UInt16(fragmentLength)
        emptyReplies = 0
        usleep(interCommandDelay)
    }
    return String(decoding: assembled, as: UTF8.self)
}

// MARK: - VCP code names (VESA MCCS 2.2 / 3.0)

let vcpNames: [UInt8: String] = [
    0x01: "Degauss", 0x02: "New Control Value", 0x03: "Soft Controls",
    0x04: "Restore Factory Defaults", 0x05: "Restore Factory Brightness/Contrast",
    0x06: "Restore Factory Geometry", 0x08: "Restore Factory Colour Defaults",
    0x0A: "Restore Factory TV Defaults", 0x0B: "Colour Temperature Increment",
    0x0C: "Colour Temperature Request", 0x0E: "Clock",
    0x10: "Brightness / Luminance", 0x11: "Flesh Tone Enhancement",
    0x12: "Contrast", 0x13: "Backlight Control", 0x14: "Select Colour Preset",
    0x16: "Video Gain: Red", 0x17: "User Colour Vision Compensation",
    0x18: "Video Gain: Green", 0x1A: "Video Gain: Blue", 0x1C: "Focus",
    0x1E: "Auto Setup", 0x1F: "Auto Colour Setup", 0x20: "Horizontal Position",
    0x22: "Horizontal Size", 0x24: "Horizontal Pincushion", 0x26: "Horizontal Pincushion Balance",
    0x28: "Horizontal Convergence R/B", 0x2A: "Horizontal Convergence M/G",
    0x2C: "Horizontal Linearity", 0x2E: "Horizontal Linearity Balance",
    0x30: "Vertical Position", 0x32: "Vertical Size", 0x34: "Vertical Pincushion",
    0x3E: "Clock Phase", 0x40: "Horizontal Parallelogram", 0x41: "Vertical Parallelogram",
    0x42: "Horizontal Keystone", 0x43: "Vertical Keystone", 0x44: "Rotation",
    0x46: "Top Corner Flare", 0x52: "Active Control", 0x54: "Performance Preservation",
    0x56: "Horizontal Moire", 0x58: "Vertical Moire", 0x59: "6-Axis Saturation: Red",
    0x5A: "6-Axis Saturation: Yellow", 0x5B: "6-Axis Saturation: Green",
    0x5C: "6-Axis Saturation: Cyan", 0x5D: "6-Axis Saturation: Blue",
    0x5E: "6-Axis Saturation: Magenta", 0x60: "Input Source Select",
    0x62: "Audio: Speaker Volume", 0x63: "Audio: Speaker Pair Select",
    0x64: "Audio: Microphone Volume", 0x65: "Audio: Jack Connection Status",
    0x66: "Ambient Light Sensor", 0x68: "Audio: Line In Volume",
    0x6B: "Backlight Level: White", 0x6C: "Video Black Level: Red",
    0x6D: "Backlight Level: Red", 0x6E: "Video Black Level: Green",
    0x6F: "Backlight Level: Green", 0x70: "Video Black Level: Blue",
    0x71: "Backlight Level: Blue", 0x72: "Gamma", 0x73: "LUT Size",
    0x7C: "Adjust Zoom", 0x82: "Horizontal Mirror / Flip", 0x84: "Vertical Mirror / Flip",
    0x86: "Display Scaling", 0x87: "Sharpness", 0x88: "Velocity Scan Modulation",
    0x8A: "Colour Saturation", 0x8B: "TV Channel Up/Down", 0x8C: "TV Sharpness",
    0x8D: "Audio: Mute / Screen Blank", 0x8E: "TV Contrast", 0x8F: "Audio: Treble",
    0x90: "Hue", 0x91: "Audio: Bass", 0x92: "TV Black Level / Luminance",
    0x93: "Audio: Balance L/R", 0x94: "Audio: Stereo Mode", 0x95: "Window Position TL_X",
    0x96: "Window Position TL_Y", 0x97: "Window Position BR_X", 0x98: "Window Position BR_Y",
    0x9A: "Window Background", 0x9B: "6-Axis Hue: Red", 0x9C: "6-Axis Hue: Yellow",
    0x9D: "6-Axis Hue: Green", 0x9E: "6-Axis Hue: Cyan", 0x9F: "6-Axis Hue: Blue",
    0xA0: "6-Axis Hue: Magenta", 0xA2: "Auto Setup On/Off", 0xA4: "Window Mask Control",
    0xA5: "Change the Selected Window", 0xAA: "Screen Orientation",
    0xAC: "Horizontal Frequency", 0xAE: "Vertical Frequency",
    0xB0: "Settings (save/restore)", 0xB2: "Flat Panel Sub-Pixel Layout",
    0xB4: "Source Timing Mode", 0xB6: "Display Technology Type",
    0xB7: "Monitor Status", 0xB8: "Packet Count", 0xB9: "Monitor X Origin",
    0xBA: "Monitor Y Origin", 0xBB: "Header Error Count", 0xBC: "Bad CRC Error Count",
    0xBD: "Client ID", 0xBE: "Link Control", 0xC0: "Display Usage Time",
    0xC2: "Display Descriptor Length", 0xC3: "Transmit Display Descriptor",
    0xC4: "Enable Display of Descriptor", 0xC6: "Application Enable Key",
    0xC8: "Display Controller Type", 0xC9: "Display Firmware Level",
    0xCA: "OSD / OSD Button Control", 0xCC: "OSD Language", 0xCD: "Status Indicators",
    0xCE: "Auxiliary Display Size", 0xCF: "Auxiliary Display Data",
    0xD0: "Output Select", 0xD2: "Asset Tag", 0xD4: "Stereo Video Mode",
    0xD6: "Power Mode (DPM/DPMS)", 0xD7: "Auxiliary Power Output",
    0xDA: "Scan Mode", 0xDB: "Image Mode", 0xDC: "Display Application / Picture Mode",
    0xDE: "Scratch Pad", 0xDF: "VCP Version",
]

/// Human-readable meaning for the well-known enumerated (non-continuous) codes.
func decodeEnumValue(code: UInt8, value: UInt16) -> String? {
    let v = UInt8(truncatingIfNeeded: value)
    switch code {
    case 0x60:
        let sources: [UInt8: String] = [
            0x01: "VGA-1", 0x02: "VGA-2", 0x03: "DVI-1", 0x04: "DVI-2",
            0x05: "Composite-1", 0x06: "Composite-2", 0x07: "S-Video-1",
            0x08: "S-Video-2", 0x09: "Tuner-1", 0x0A: "Tuner-2", 0x0B: "Tuner-3",
            0x0C: "Component-1", 0x0D: "Component-2", 0x0E: "Component-3",
            0x0F: "DisplayPort-1", 0x10: "DisplayPort-2", 0x11: "HDMI-1", 0x12: "HDMI-2",
            0x1B: "USB-C (vendor-specific)",
        ]
        return sources[v]
    case 0x14:
        let presets: [UInt8: String] = [
            0x01: "sRGB", 0x02: "Display native", 0x03: "4000 K", 0x04: "5000 K",
            0x05: "6500 K", 0x06: "7500 K", 0x07: "8200 K", 0x08: "9300 K",
            0x09: "10000 K", 0x0A: "11500 K", 0x0B: "User 1", 0x0C: "User 2", 0x0D: "User 3",
        ]
        return presets[v]
    case 0xD6:
        let modes: [UInt8: String] = [
            0x01: "On", 0x02: "Standby", 0x03: "Suspend",
            0x04: "Off (reduced power)", 0x05: "Off (power cut)",
        ]
        return modes[v]
    case 0x8D:
        return [0x01: "Mute", 0x02: "Unmute"][v]
    case 0xCC:
        let langs: [UInt8: String] = [
            0x01: "Chinese", 0x02: "English", 0x03: "French", 0x04: "German",
            0x05: "Italian", 0x06: "Japanese", 0x07: "Korean", 0x08: "Portuguese",
            0x09: "Russian", 0x0A: "Spanish",
        ]
        return langs[v]
    case 0xDC:
        let modes: [UInt8: String] = [
            0x00: "Standard/Default", 0x01: "Productivity", 0x02: "Mixed",
            0x03: "Movie", 0x04: "User-defined", 0x05: "Games", 0x06: "Sports",
            0x07: "Professional", 0x08: "Standard with hardware calibration", 0x09: "Dynamic contrast",
        ]
        return modes[v]
    case 0xCA:
        return [0x01: "OSD disabled", 0x02: "OSD enabled", 0xFF: "Display cannot supply"][v]
    case 0xB2:
        let layouts: [UInt8: String] = [
            0x00: "Undefined", 0x01: "RGB vertical stripe", 0x02: "RGB horizontal stripe",
            0x03: "BGR vertical stripe", 0x04: "BGR horizontal stripe",
            0x05: "Quad quincunx (RGGB)", 0x06: "Quad quincunx (GBRG)", 0x07: "Delta triad",
            0x08: "Mosaic",
        ]
        return layouts[v]
    case 0xB6:
        let tech: [UInt8: String] = [
            0x01: "CRT (shadow mask)", 0x02: "CRT (aperture grill)", 0x03: "LCD (active matrix)",
            0x04: "LCoS", 0x05: "Plasma", 0x06: "OLED", 0x07: "EL", 0x08: "MEM",
        ]
        return tech[v]
    case 0x86:
        let scaling: [UInt8: String] = [
            0x01: "No scaling", 0x02: "Max image, no aspect distortion",
            0x03: "Max vertical, no aspect distortion", 0x04: "Max horizontal, no aspect distortion",
            0x05: "Max vertical with aspect distortion", 0x06: "Max horizontal with aspect distortion",
            0x07: "Linear expansion (aspect preserved)", 0x08: "Linear expansion (horizontal)",
            0x09: "Squeeze", 0x0A: "Non-linear expansion",
        ]
        return scaling[v]
    default:
        return nil
    }
}

// MARK: - Commands

func printUsage() {
    print("""
    ddcprobe — read-only DDC/CI enumeration (Apple Silicon)

      list       Show external displays reachable over the AUX I2C channel
      caps       Read the monitor's VCP capabilities string (VCP 0xF3)
      quickscan  Probe the ~50 VCP codes monitors actually implement (gentle)
      scan       Probe all 256 VCP codes (heavy; can wedge a fragile display)
      get <hex>  Read one VCP code, e.g. `get 10` for brightness
      selftest [n]  Read the control code n times in ONE process — separates a
                    single-shot display from per-process handle teardown
      patience   Escalate the inter-command gap (2/5/10/20/40/80s) — separates
                 a merely SLOW bus from a genuinely single-shot one
      capsdebug  Dump raw replies to a capabilities request, for diagnosis

    All commands are READ-ONLY: this tool never issues Set VCP Feature (0x03).

    On a multi-display Mac, every command except `list` operates on the FIRST
    external display found, and prints which one it selected before probing.
    """)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    printUsage()
    exit(2)
}

let services = discoverServices()
guard let target = services.first else {
    print("No external DCPAVServiceProxy found — is a display attached?")
    exit(1)
}

// Say WHICH display is being probed. On a multi-display Mac a silent
// services.first would report another monitor's values while looking correct.
if arguments[1] != "list" {
    var banner = "probing external display [0] of \(services.count): "
    banner += "\(target.displayAttributes) (location=\(target.location))\n"
    if services.count > 1 {
        banner += "  NOTE: \(services.count - 1) other external display(s) present, NOT probed.\n"
    }
    FileHandle.standardError.write(Data(banner.utf8))
}

switch arguments[1] {
case "list":
    print("External display AV services found: \(services.count)")
    for (index, item) in services.enumerated() {
        print("  [\(index)] IORegistry name=\(item.displayAttributes) location=\(item.location)")
    }

case "capsdebug":
    // Instrumentation: show exactly what comes back for a capabilities request,
    // across several reply delays and read sizes, so an empty result can be
    // attributed to the monitor rather than to this parser.
    for delayMs in [50, 100, 200, 400] {
        for readSize in [64, 40, 38, 32] {
            let payload: [UInt8] = [0xF3, 0x00, 0x00]
            let writeStatus = ddcWrite(target.service, payload: payload)
            usleep(UInt32(delayMs) * 1000)
            let (readStatus, buffer) = ddcRead(target.service, count: readSize)
            let hex = buffer.map { String(format: "%02x", $0) }.joined(separator: " ")
            let nonZero = buffer.contains { $0 != 0 }
            print("delay=\(delayMs)ms size=\(readSize) write=\(writeStatus) read=\(readStatus) nonzero=\(nonZero)")
            print("  \(hex)")
            usleep(interCommandDelay)
        }
    }

case "caps":
    let capabilities = readCapabilities(target.service)
    if capabilities.isEmpty {
        print("(empty — the display did not answer the capabilities request)")
        exit(1)
    }
    print(capabilities)

case "patience":
    // `selftest` showed the display answers exactly one Get VCP and then
    // Null-Messages everything, at ~120ms spacing. The remaining untested
    // variable is TIME: some scalers need far longer between transactions
    // than the 40ms DDC/CI minimum (ddcutil ships "sleep multipliers" for
    // exactly this). This escalates the gap to see whether the bus is slow
    // rather than single-shot. Run FIRST after a power cycle.
    print("Escalating-delay probe of VCP 0x\(String(format: "%02X", controlVCPCode))")
    print("Establishing the baseline read first, then retrying with growing gaps.")
    print("")
    let baseline = getVCP(target.service, code: controlVCPCode, attempts: 1)
    let baselineOK = baseline?.supported == true
    print("  baseline      : \(baselineOK ? "OK" : "FAIL") "
          + (baseline.map { "cur=\($0.current) max=\($0.maximum)" } ?? "no reply"))
    if !baselineOK {
        print("")
        print("The baseline already failed, so the single shot was spent before this")
        print("ran. Power-cycle the monitor and run `patience` FIRST.")
        exit(1)
    }
    var recovered = false
    for gapSeconds in [2, 5, 10, 20, 40, 80] {
        sleep(UInt32(gapSeconds))
        let reply = getVCP(target.service, code: controlVCPCode, attempts: 1)
        let ok = reply?.supported == true
        print("  after \(String(format: "%3d", gapSeconds))s gap : \(ok ? "OK" : "FAIL") "
              + (reply.map { "cur=\($0.current) max=\($0.maximum)" } ?? "no reply"))
        if ok { recovered = true; break }
    }
    print("")
    if recovered {
        print("VERDICT: the bus is SLOW, not single-shot. DDC/CI is usable if paced")
        print("at the gap above. Enumeration is practical; raise interCommandDelay.")
    } else {
        print("VERDICT: no recovery even after 80s idle. Combined with selftest, the")
        print("display answers ONE DDC transaction per power event regardless of")
        print("pacing. DDC/CI is not practically usable on this monitor — read the")
        print("settings from the OSD instead.")
    }

case "selftest":
    // Discriminating experiment. This monitor answered exactly one DDC
    // transaction after a power cycle and then returned Null Messages
    // forever. Two explanations fit that:
    //   (a) the display's DDC engine is genuinely single-shot, or
    //   (b) tearing down and recreating the IOAVService per process is what
    //       breaks it, and one long-lived handle would be fine.
    // Running N reads inside ONE process separates them: all-pass means (b),
    // first-only-passes means (a). Run this FIRST after a power cycle, before
    // anything else touches the bus, or the single shot is already spent.
    let iterations = arguments.count >= 3 ? (Int(arguments[2]) ?? 10) : 10
    print("Reading VCP 0x\(String(format: "%02X", controlVCPCode)) \(iterations)x within a single process")
    print("(one IOAVService handle, \(replyDelay / 1000)ms reply delay, \(interCommandDelay / 1000)ms between)")
    print("")
    var passes = 0
    for iteration in 1...iterations {
        let reply = getVCP(target.service, code: controlVCPCode, attempts: 1)
        let ok = reply?.supported == true
        if ok { passes += 1 }
        let detail = reply.map { "cur=\($0.current) max=\($0.maximum)" } ?? "no parseable reply"
        print("  read \(String(format: "%2d", iteration)): \(ok ? "OK  " : "FAIL") \(detail)")
        usleep(interCommandDelay)
    }
    print("")
    print("Passed \(passes)/\(iterations) within one process.")
    if passes == iterations {
        print("VERDICT: the bus is stable inside one process — per-invocation")
        print("service teardown was the problem, not the display. Enumerate from")
        print("a single long-lived process.")
    } else if passes <= 1 {
        print("VERDICT: the display's DDC engine really is effectively single-shot")
        print("per power cycle. Probing enumeration is impractical; use the OSD.")
    } else {
        print("VERDICT: partial — the bus tolerates \(passes) transactions then stops.")
        print("Enumeration is possible but must be chunked across power cycles.")
    }

case "scan", "quickscan":
    let codesToProbe: [UInt8] =
        arguments[1] == "quickscan" ? commonVCPCodes : (0...255).map { UInt8($0) }

    /// Confirm the bus still answers the control code, waiting out a wedge.
    func controlResponds(patience: Int) -> Bool {
        for attempt in 0..<patience {
            if let reply = getVCP(target.service, code: controlVCPCode, attempts: 2), reply.supported {
                return true
            }
            FileHandle.standardError.write(
                Data("  control 0x10 not answering (attempt \(attempt + 1)/\(patience)); waiting 5s\n".utf8))
            sleep(5)
        }
        return false
    }

    guard controlResponds(patience: 12) else {
        print("ABORT: the positive control (VCP 0x10) never answered, so the DDC bus")
        print("is wedged or unreachable. A scan run now would report every code as")
        print("unsupported, which would be a false negative, not a measurement.")
        print("Recovery: leave the display idle for a minute, or sleep/wake it.")
        exit(1)
    }
    FileHandle.standardError.write(Data("control 0x10 answered — starting scan\n".utf8))

    func pad(_ text: String, _ width: Int) -> String {
        text.count >= width
            ? String(text.prefix(width))
            : text + String(repeating: " ", count: width - text.count)
    }

    print("code  \(pad("name", 38))  cur /   max   type           notes")
    print(String(repeating: "-", count: 100))
    var supportedCount = 0
    var wedgeEvents = 0
    var probedCount = 0

    for code in codesToProbe {
        // Re-verify the control periodically; a mid-scan wedge would otherwise
        // silently turn every remaining code into a false "unsupported".
        if probedCount > 0 && probedCount % 16 == 0 && code != controlVCPCode {
            if getVCP(target.service, code: controlVCPCode, attempts: 2)?.supported != true {
                wedgeEvents += 1
                FileHandle.standardError.write(
                    Data("  wedge detected at code 0x\(String(format: "%02X", code)); backing off\n".utf8))
                if !controlResponds(patience: 12) {
                    print(String(repeating: "-", count: 100))
                    print("ABORT at code 0x\(String(format: "%02X", code)): bus wedged and did not recover.")
                    print("Results above are PARTIAL — codes from here on were never measured.")
                    exit(1)
                }
            }
        }

        probedCount += 1
        guard let reply = getVCP(target.service, code: code, attempts: 2), reply.supported else {
            usleep(interCommandDelay)
            continue
        }
        supportedCount += 1
        let name = vcpNames[code] ?? "(unknown / vendor-specific)"
        let note = decodeEnumValue(code: code, value: reply.current) ?? ""
        print("0x\(String(format: "%02X", code))  \(pad(name, 38)) "
              + String(format: "%5d / %5d   ", reply.current, reply.maximum)
              + "\(pad(reply.typeName, 13))  \(note)")
        usleep(interCommandDelay)
    }

    print(String(repeating: "-", count: 100))
    let finalControl = controlResponds(patience: 6)
    print("Supported VCP codes : \(supportedCount) of \(codesToProbe.count) probed")
    print("Wedge/backoff events: \(wedgeEvents)")
    print("Control still alive : \(finalControl)")
    if !finalControl {
        print("WARNING: the control stopped answering by the end of the scan, so")
        print("later codes may be false negatives. Re-run after the bus settles.")
    }

case "get":
    guard arguments.count >= 3, let code = UInt8(arguments[2], radix: 16) else {
        printUsage()
        exit(2)
    }
    guard let reply = getVCP(target.service, code: code) else {
        print("No valid reply for VCP 0x\(String(format: "%02X", code))")
        exit(1)
    }
    let name = vcpNames[code] ?? "(unknown)"
    print("VCP 0x\(String(format: "%02X", code)) — \(name)")
    print("  supported : \(reply.supported)  (result byte 0x\(String(format: "%02X", reply.resultCode)))")
    print("  type      : \(reply.typeName)")
    print("  current   : \(reply.current)")
    print("  maximum   : \(reply.maximum)")
    if let meaning = decodeEnumValue(code: code, value: reply.current) {
        print("  meaning   : \(meaning)")
    }
    print("  raw reply : \(reply.raw.map { String(format: "%02x", $0) }.joined(separator: " "))")

default:
    printUsage()
    exit(2)
}
