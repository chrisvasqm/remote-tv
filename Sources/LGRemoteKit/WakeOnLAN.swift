import Foundation

/// Turns the TV on with a Wake-on-LAN magic packet. The TV must have
/// "TV On With Mobile > Turn on via Wi-Fi" switched on.
public enum WakeOnLAN {
    public static func send(mac: String) throws {
        let bytes = mac.split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { throw TVError.badResponse("invalid MAC address \(mac)") }
        let packet = [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: bytes, count: 16).joined())

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw TVError.badResponse("cannot open a UDP socket") }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(9).bigEndian
        address.sin_addr.s_addr = INADDR_BROADCAST
        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw TVError.badResponse("magic packet not sent") }
    }

    /// Reads the TV's MAC address from the ARP table (only while the TV is on).
    public static func macAddress(for host: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let range = output.range(of: #"([0-9a-fA-F]{1,2}:){5}[0-9a-fA-F]{1,2}"#, options: .regularExpression) else {
            return nil
        }
        // arp drops leading zeros ("2:f:b5:..."); pad each part back to two digits.
        return output[range].split(separator: ":").map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ":")
    }
}
