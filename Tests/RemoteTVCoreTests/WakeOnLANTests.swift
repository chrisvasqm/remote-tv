import Testing
@testable import RemoteTVCore

struct WakeOnLANTests {
    @Test(arguments: [
        "aa:bb:cc:dd:ee:ff",
        "AA:BB:CC:DD:EE:FF",
        "aa-bb-cc-dd-ee-ff",
    ])
    func parsesSixHexGroups(_ mac: String) {
        #expect(WakeOnLAN.parseMAC(mac) == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    }

    @Test func acceptsGroupsWithoutLeadingZero() {
        #expect(WakeOnLAN.parseMAC("2:f:b5:0:1:a") == [0x02, 0x0F, 0xB5, 0x00, 0x01, 0x0A])
    }

    @Test(arguments: [
        "",
        "aa:bb:cc:dd:ee",           // five groups
        "aa:bb:cc:dd:ee:ff:00",     // seven groups
        "aa:bb:cc:dd:ee:ff:zz",     // the invalid group was dropped before the fix
        "aa:bb:cc:dd:ee:zz",        // not hex
        "aa:bb:cc:dd:ee:fff",       // three digits
        "aa:bb:cc:dd::ff",          // empty group
        "aa:bb:cc:dd:ee:ff:",       // trailing separator
        "aa:bb:cc-dd-ee-ff",        // mixed separators
        "aa:bb:cc:dd:ee:+f",        // sign
        "aa:bb:cc:dd:ee:ｆｆ",        // fullwidth digits
        "aabbccddeeff",             // no separators
        "aa bb cc dd ee ff",        // spaces
    ])
    func rejectsAnythingElse(_ mac: String) {
        #expect(WakeOnLAN.parseMAC(mac) == nil)
    }

    @Test func sendThrowsForAnInvalidMACBeforeSending() {
        #expect(throws: TVError.self) {
            try WakeOnLAN.send(mac: "aa:bb:cc:dd:ee:ff:zz", host: "192.0.2.1")
        }
    }
}
