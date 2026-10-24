import Foundation

/// Turns a TV on with a Wake-on-LAN magic packet, for brands with
/// `TVCapabilities.wakeOnLAN`. The TV usually needs a setting for it (`TVBrand.wakeHelp`).
public enum WakeOnLAN {
    /// Sends the magic packet every way a TV might hear it: the limited broadcast, each
    /// local network's own broadcast address, and straight to the TV's last known address,
    /// on ports 9 and 7. Some routers and Macs drop one kind but not the others.
    public static func send(mac: String, host: String) throws {
        guard let bytes = parseMAC(mac) else { throw TVError.badResponse("invalid MAC address \(mac)") }
        let packet = [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: bytes, count: 16).joined())

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw TVError.badResponse("cannot open a UDP socket") }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var targets = [in_addr(s_addr: INADDR_BROADCAST)] + broadcastAddresses()
        var direct = in_addr()
        if inet_pton(AF_INET, host, &direct) == 1 { targets.append(direct) }

        var sentAny = false
        for target in targets {
            for port: UInt16 in [9, 7] {
                var address = sockaddr_in()
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = port.bigEndian
                address.sin_addr = target
                let sent = packet.withUnsafeBytes { buffer in
                    withUnsafePointer(to: &address) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            let length = socklen_t(MemoryLayout<sockaddr_in>.size)
                            return sendto(fd, buffer.baseAddress, buffer.count, 0, $0, length)
                        }
                    }
                }
                if sent == packet.count { sentAny = true }
            }
        }
        guard sentAny else { throw TVError.badResponse("magic packet not sent") }
    }

    /// The six bytes of a MAC address written as six groups of one or two hex digits,
    /// separated by ":" or "-". Nil for anything else.
    static func parseMAC(_ mac: String) -> [UInt8]? {
        let separator: Character = mac.contains(":") ? ":" : "-"
        let groups = mac.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count == 6 else { return nil }
        var bytes: [UInt8] = []
        for group in groups {
            // ASCII only: isHexDigit alone also accepts fullwidth digits.
            guard (1...2).contains(group.count), group.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  let byte = UInt8(group, radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }

    /// The broadcast address of each active IPv4 network, such as 192.168.0.255.
    private static func broadcastAddresses() -> [in_addr] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var result: [in_addr] = []
        var next = list
        while let interface = next?.pointee {
            next = interface.ifa_next
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let broadcast = interface.ifa_dstaddr,
                  broadcast.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            result.append(broadcast.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr })
        }
        return result
    }

    /// Reads the TV's MAC address from the ARP table (only while the TV is on).
    public static func macAddress(for host: String) async -> String? {
        await Task.detached { readARP(host) }.value
    }

    private static func readARP(_ host: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        // Latin-1 decodes any byte, so a host name that is not UTF-8 can't hide the MAC.
        guard let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .isoLatin1) else {
            return nil
        }
        // arp drops leading zeros ("2:f:b5:..."); parseMAC accepts that, and the result is padded.
        let bytes = output.split(whereSeparator: \.isWhitespace).lazy.compactMap { parseMAC(String($0)) }.first
        return bytes?.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}
