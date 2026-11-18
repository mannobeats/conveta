import AudioToolbox
import Foundation

/// Repackages Opus packets from a CAF file into a standard Ogg Opus file (RFC 7845).
///
/// Core Audio encodes Opus well but can't write the Ogg container, which is what every player
/// expects from a `.opus` file. So the encoder writes CAF and this copies the packets into Ogg pages.
enum OggOpusMuxer {
    static func mux(caf source: URL, into destination: URL) throws {
        var file: AudioFileID?
        try check(AudioFileOpenURL(source as CFURL, .readPermission, kAudioFileCAFType, &file), "read the Opus stream")
        guard let file else { throw ConversionError.unreadable }
        defer { AudioFileClose(file) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format), "read the Opus format")
        var packetCount: UInt64 = 0
        size = UInt32(MemoryLayout<UInt64>.size)
        try check(AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &size, &packetCount), "count Opus packets")
        var table = AudioFilePacketTableInfo()
        size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
        let hasTable = AudioFileGetProperty(file, kAudioFilePropertyPacketTableInfo, &size, &table) == noErr

        let framesPerPacket = Int64(format.mFramesPerPacket > 0 ? format.mFramesPerPacket : 960)
        let preSkip = hasTable ? Int64(table.mPrimingFrames) : 312
        let validFrames = hasTable ? table.mNumberValidFrames : Int64(packetCount) * framesPerPacket - preSkip

        var writer = OggPageWriter(serial: UInt32.random(in: 1...UInt32.max))
        writer.writePage(packets: [opusHead(channels: Int(format.mChannelsPerFrame), preSkip: UInt16(clamping: preSkip))],
                         granule: 0, flags: 0x02)
        writer.writePage(packets: [opusTags()], granule: 0, flags: 0)

        var maxPacket: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioFileGetProperty(file, kAudioFilePropertyMaximumPacketSize, &size, &maxPacket), "read the Opus stream")
        let chunk = 40  // 0.8 s of 20 ms packets; even 1275-byte packets fit the 255-segment page limit
        var buffer = [UInt8](repeating: 0, count: Int(max(maxPacket, 1)) * chunk)
        var descriptions = [AudioStreamPacketDescription](repeating: .init(), count: chunk)
        var packetIndex: Int64 = 0

        while packetIndex < Int64(packetCount) {
            var bytes = UInt32(buffer.count)
            var count = UInt32(min(Int64(chunk), Int64(packetCount) - packetIndex))
            try check(AudioFileReadPacketData(file, false, &bytes, &descriptions, packetIndex, &count, &buffer), "read Opus packets")
            guard count > 0 else { break }
            let packets = (0..<Int(count)).map { index -> [UInt8] in
                let description = descriptions[index]
                let start = Int(description.mStartOffset)
                return Array(buffer[start..<start + Int(description.mDataByteSize)])
            }
            packetIndex += Int64(count)
            let isLast = packetIndex >= Int64(packetCount)
            let granule = isLast ? preSkip + validFrames : packetIndex * framesPerPacket
            writer.writePage(packets: packets, granule: granule, flags: isLast ? 0x04 : 0)
        }
        try writer.data.write(to: destination)
    }

    private static func opusHead(channels: Int, preSkip: UInt16) -> [UInt8] {
        var head = Array("OpusHead".utf8)
        head.append(1)                                  // version
        head.append(UInt8(channels))
        head += withUnsafeBytes(of: preSkip.littleEndian, Array.init)
        head += withUnsafeBytes(of: UInt32(48_000).littleEndian, Array.init)  // original rate, informational
        head += [0, 0]                                  // output gain
        head.append(0)                                  // channel mapping family: mono or stereo
        return head
    }

    private static func opusTags() -> [UInt8] {
        let vendor = Array("Conveta".utf8)
        var tags = Array("OpusTags".utf8)
        tags += withUnsafeBytes(of: UInt32(vendor.count).littleEndian, Array.init)
        tags += vendor
        tags += withUnsafeBytes(of: UInt32(0).littleEndian, Array.init)  // no comments
        return tags
    }
}

/// Writes Ogg pages (RFC 3533). Each call writes one page holding whole packets.
struct OggPageWriter {
    let serial: UInt32
    private(set) var data = Data()
    private var sequence: UInt32 = 0

    init(serial: UInt32) { self.serial = serial }

    mutating func writePage(packets: [[UInt8]], granule: Int64, flags: UInt8) {
        var segments: [UInt8] = []
        for packet in packets {
            segments += Array(repeating: 255, count: packet.count / 255)
            segments.append(UInt8(packet.count % 255))
        }
        precondition(segments.count <= 255, "too many packets for one Ogg page")

        var page = Array("OggS".utf8)
        page.append(0)  // version
        page.append(flags)
        page += withUnsafeBytes(of: granule.littleEndian, Array.init)
        page += withUnsafeBytes(of: serial.littleEndian, Array.init)
        page += withUnsafeBytes(of: sequence.littleEndian, Array.init)
        page += [0, 0, 0, 0]  // checksum, filled below
        page.append(UInt8(segments.count))
        page += segments
        for packet in packets { page += packet }

        let crc = Self.crc(page)
        page.replaceSubrange(22..<26, with: withUnsafeBytes(of: crc.littleEndian, Array.init))
        data.append(contentsOf: page)
        sequence += 1
    }

    /// Ogg's CRC-32: polynomial 0x04C11DB7, not reflected, starting at zero.
    static func crc(_ bytes: [UInt8]) -> UInt32 {
        bytes.reduce(UInt32(0)) { crc, byte in (crc << 8) ^ table[Int(((crc >> 24) ^ UInt32(byte)) & 0xFF)] }
    }

    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index) << 24) { value, _ in
            value & 0x8000_0000 != 0 ? (value << 1) ^ 0x04C1_1DB7 : value << 1
        }
    }
}
