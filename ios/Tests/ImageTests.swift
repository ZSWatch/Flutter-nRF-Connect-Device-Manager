import Foundation

@main struct ImageTests {
  static func main() throws {
    func image() -> Data {
      var bytes = Data(repeating: 0, count: 88)
      func put(_ value: UInt32, _ at: Int, _ width: Int) { for i in 0..<width { bytes[at + i] = UInt8((value >> (8 * i)) & 255) } }
      put(0x96f3b83d, 0, 4); put(32, 8, 2); put(16, 12, 4)
      put(0x6907, 48, 2); put(40, 50, 2); put(0x10, 52, 1); put(32, 54, 2)
      for i in 56..<88 { bytes[i] = UInt8(i) }
      return bytes
    }
    let valid = image()
    let parsed = try McuMgrImage(data: valid)
    precondition(parsed.hash == valid.subdata(in: 56..<88))
    for count in 0..<32 {
      do { _ = try McuMgrImage(data: valid.prefix(count)); fatalError("Short image header accepted") } catch {}
    }
    var variants: [Data] = []
    var oversizedBody = valid; oversizedBody[15] = 0xff; variants.append(oversizedBody)
    var oversizedTable = valid; oversizedTable[51] = 0xff; variants.append(oversizedTable)
    var oversizedEntry = valid; oversizedEntry[54] = 128; variants.append(oversizedEntry)
    var shortTable = valid; shortTable[50] = 8; variants.append(shortTable)
    for bytes in variants {
      do { _ = try McuMgrImage(data: bytes); fatalError("Malformed image/table accepted") } catch {}
    }
    let unaligned = Data([0xaa, 4, 3, 2, 1])
    let value: UInt32 = unaligned.read(offset: 1); precondition(value == 0x01020304)
    print("PASS: Nordic image parsing rejects short/out-of-bounds headers and TLVs; unaligned reads are safe")
  }
}
