import Foundation
import Testing
@testable import ConvetaKit

@Suite("Links and downloads")
struct DownloadTests {
    @Test("Links are found in pasted text")
    func links() {
        let text = """
        Watch this https://www.youtube.com/watch?v=abc and (https://vm.tiktok.com/xyz/)
        <https://www.instagram.com/reel/123/> not-a-link ftp://x.com/y mailto:a@b.c https://localhost
        """
        #expect(LinkDetector.links(in: text).map(\.absoluteString) == [
            "https://www.youtube.com/watch?v=abc", "https://vm.tiktok.com/xyz/", "https://www.instagram.com/reel/123/",
        ])
    }

    @Test("Known sites by host, including subdomains", arguments: [
        ("https://youtu.be/abc", "YouTube"), ("https://m.youtube.com/shorts/x", "YouTube"),
        ("https://www.tiktok.com/@a/video/1", "TikTok"), ("https://vm.tiktok.com/x", "TikTok"),
        ("https://www.instagram.com/p/x", "Instagram"), ("https://twitter.com/a/status/1", "X"),
    ])
    func sites(link: String, site: String) {
        #expect(LinkDetector.knownSite(for: URL(string: link)!) == site)
    }

    @Test("Unknown and look-alike hosts are not claimed")
    func lookalikes() {
        #expect(LinkDetector.knownSite(for: URL(string: "https://notyoutube.com/x")!) == nil)
        #expect(LinkDetector.knownSite(for: URL(string: "https://youtube.com.evil.example/x")!) == nil)
        #expect(LinkDetector.knownSite(for: URL(string: "https://example.org/video")!) == nil)
    }

    @Test("yt-dlp metadata becomes RemoteMedia")
    func metadata() throws {
        let json = """
        {"id":"jNQXAC9IVRw","title":"Me at the zoo","uploader":"jawed","duration":19,
         "thumbnail":"https://i.ytimg.com/vi/jNQXAC9IVRw/hq.jpg","webpage_url":"https://www.youtube.com/watch?v=jNQXAC9IVRw",
         "extractor_key":"Youtube","vcodec":"avc1.4d401e","width":320,"height":240}
        """
        let media = try DownloadEngine.media(from: Data(json.utf8), link: URL(string: "https://youtu.be/jNQXAC9IVRw")!)
        #expect(media.title == "Me at the zoo")
        #expect(media.site == "YouTube")
        #expect(media.kind == .video)
        #expect(media.details == "YouTube · jawed · 0:19 · up to 240p")
        #expect(media.pageURL.absoluteString == "https://www.youtube.com/watch?v=jNQXAC9IVRw")
    }

    @Test("Audio-only pages and playlists")
    func audioAndPlaylists() throws {
        let song = #"{"id":"1","title":"Song","extractor_key":"Soundcloud","vcodec":"none","webpage_url":"https://soundcloud.com/a/b"}"#
        #expect(try DownloadEngine.media(from: Data(song.utf8), link: URL(string: "https://soundcloud.com/a/b")!).kind == .audio)
        let list = #"{"_type":"playlist","id":"PL1","title":"Mix"}"#
        #expect(throws: DownloadError.playlist) { try DownloadEngine.media(from: Data(list.utf8), link: URL(string: "https://youtube.com/playlist?list=PL1")!) }
    }

    @Test("Titles become safe file names")
    func fileNames() {
        func name(_ title: String) -> String {
            RemoteMedia(link: URL(string: "https://x.com")!, pageURL: URL(string: "https://x.com")!, id: "42", title: title,
                        site: "X", hasVideo: true).fileBaseName
        }
        #expect(name("AC/DC: Live at River Plate") == "AC DC Live at River Plate")
        #expect(name("...hidden") == "hidden")
        #expect(name("line\nbreak") == "line break")
        #expect(name("   ") == "X 42")
        #expect(name(String(repeating: "a", count: 300)).count == 120)
    }

    @Test("Progress folds picture and sound into one bar")
    func progress() {
        #expect(DownloadProgress.fraction("conveta-progress 50 200 NA") == 0.25)
        #expect(DownloadProgress.fraction("conveta-progress 50 NA 100") == 0.5)
        #expect(DownloadProgress.fraction("conveta-progress 50 NA NA") == nil)
        #expect(DownloadProgress.fraction("[download] 50%") == nil)

        let seen = Recorder()
        let tracker = DownloadProgress(parts: 2) { seen.add($0) }
        for line in ["conveta-progress 50 100 NA", "conveta-progress 100 100 NA", "conveta-progress 10 100 NA", "conveta-progress 100 100 NA"] {
            tracker.consume(line)
        }
        #expect(seen.all == seen.all.sorted())
        #expect(abs((seen.all.last ?? 0) - 0.98) < 0.001)

        let forward = Recorder()
        let relay = ProgressRelay { forward.add($0) }
        for value in [0.1, 0.5, 0.3, 0.6, 0.6, 1.0] { relay.report(value) }
        #expect(forward.all == [0.1, 0.5, 0.6, 1.0])
    }

    @Test("Checksums are read from the release list and enforced")
    func checksums() throws {
        let sums = """
        0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa  yt-dlp_macos
        1111111111111111111111111111111111111111111111111111111111111111  yt-dlp_macos.zip
        """
        #expect(DownloadEngine.checksum(for: "yt-dlp_macos", in: sums) == "0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa")
        #expect(DownloadEngine.checksum(for: "yt-dlp", in: sums) == nil)

        let file = FileManager.default.temporaryDirectory.appending(path: "sum-\(UUID().uuidString)")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try DownloadEngine.verify(file, sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(throws: DownloadError.checksumMismatch) { try DownloadEngine.verify(file, sha256: String(repeating: "0", count: 64)) }
    }

    @Test("Download arguments: strict height, container-specific codec preference")
    func arguments() {
        let mp4 = DownloadEngine.downloadArguments(container: .mp4, maxHeight: 720, folder: URL(filePath: "/w")).joined(separator: " ")
        #expect(mp4.contains("-f bv*[height<=720]+ba/b[height<=720]/bv*+ba/b"))
        #expect(mp4.contains("-S res,vcodec:h264,acodec:aac"))
        #expect(mp4.contains("--merge-output-format mp4"))
        #expect(mp4.contains("--no-simulate"))
        let best = DownloadEngine.downloadArguments(container: .webm, maxHeight: nil, folder: URL(filePath: "/w")).joined(separator: " ")
        #expect(best.contains("-f bv*+ba/b/bv*+ba/b"))
        #expect(best.contains("vcodec:vp9"))
        #expect(best.contains("--merge-output-format webm"))
        let audio = DownloadEngine.downloadArguments(container: .audio, maxHeight: nil, folder: URL(filePath: "/w")).joined(separator: " ")
        #expect(audio.contains("-f ba/b"))
        #expect(!audio.contains("merge-output"))
    }

    @Test("Containers follow the chosen format")
    func containers() {
        #expect(DownloadService.container(for: .mp4, hasVideo: true) == .mp4)
        #expect(DownloadService.container(for: .mov, hasVideo: true) == .mp4)
        #expect(DownloadService.container(for: .webm, hasVideo: true) == .webm)
        #expect(DownloadService.container(for: .mkv, hasVideo: true) == .mkv)
        #expect(DownloadService.container(for: .mp3, hasVideo: true) == .audio)
        #expect(DownloadService.container(for: .mp4, hasVideo: false) == .audio)
    }

    func info(_ codec: String, audio: String = "AAC", apple: Bool = true, height: Int = 1080) -> MediaInfo {
        var info = MediaInfo(kind: .video, contentType: .mpeg4Movie, fileSize: 1)
        info.codec = codec
        info.audioCodec = audio
        info.hasAudio = true
        info.readableByApple = apple
        info.pixelSize = CGSize(width: height * 16 / 9, height: height)
        return info
    }

    @Test("A download is kept as is only when it plays everywhere")
    func readiness() {
        let mp4 = ConversionSettings(format: .mp4)
        #expect(DownloadService.isReady(info("H.264"), downloadedAs: "mp4", for: mp4))
        #expect(DownloadService.isReady(info("HEVC"), downloadedAs: "mp4", for: mp4))
        // The bug: VP9 inside an MP4 plays as a frozen picture in QuickTime.
        #expect(!DownloadService.isReady(info("VP9", apple: false), downloadedAs: "mp4", for: mp4))
        #expect(!DownloadService.isReady(info("AV1", apple: false), downloadedAs: "mp4", for: mp4))
        #expect(!DownloadService.isReady(info("H.264", audio: "Opus"), downloadedAs: "mp4", for: mp4))
        #expect(DownloadService.isReady(info("VP9", audio: "Opus", apple: false), downloadedAs: "webm", for: ConversionSettings(format: .webm)))
        #expect(!DownloadService.isReady(info("H.264"), downloadedAs: "mp4", for: ConversionSettings(format: .mov)))
    }

    @Test("Converting a download: tall pictures become HEVC at high quality")
    func conversionSettings() {
        var settings = ConversionSettings(format: .mp4)
        settings.video.resolution = .p720
        let tall = DownloadService.conversionSettings(for: settings, info: info("VP9", apple: false, height: 1440))
        #expect(tall.video.codec == .hevc)
        #expect(tall.video.quality == .high)
        #expect(tall.video.resolution == .original)
        let regular = DownloadService.conversionSettings(for: settings, info: info("VP9", apple: false, height: 1080))
        #expect(regular.video.codec == .h264)
    }

    @Test("Qualities: every height once, tallest first, with sizes")
    func qualities() throws {
        let json = """
        {"id":"x","title":"T","duration":100,"extractor_key":"Youtube","webpage_url":"https://www.youtube.com/watch?v=x",
         "formats":[
          {"format_id":"251","vcodec":"none","acodec":"opus","filesize":1000000},
          {"format_id":"140","vcodec":"none","acodec":"mp4a.40.2","filesize":1600000},
          {"format_id":"137","vcodec":"avc1.640028","acodec":"none","height":1080,"filesize":50000000},
          {"format_id":"248","vcodec":"vp9","acodec":"none","height":1080,"filesize":40000000},
          {"format_id":"271","vcodec":"vp9","acodec":"none","height":1440,"filesize_approx":90000000.0},
          {"format_id":"18","vcodec":"avc1","acodec":"mp4a","height":360,"tbr":500.5},
          {"format_id":"sb0","vcodec":"none","acodec":"none","height":90},
          {"format_id":"x","vcodec":"avc1","height":"weird"}
         ]}
        """
        let media = try DownloadEngine.media(from: Data(json.utf8), link: URL(string: "https://youtu.be/x")!)
        #expect(media.qualities.map(\.height) == [1440, 1080, 360])
        // 1440p only has VP9; 1080p prefers the H.264 stream; AAC sound (1.6 MB) is added to video-only streams.
        #expect(media.qualities[0].estimatedBytes == 91_600_000)
        #expect(media.qualities[1].estimatedBytes == 51_600_000)
        #expect(media.qualities[2].estimatedBytes == 6_256_250)
        let vp9First = """
        {"id":"y","title":"T","duration":10,"webpage_url":"https://youtu.be/y","formats":[
          {"vcodec":"vp9","acodec":"none","height":720,"filesize":9000000},
          {"vcodec":"avc1","acodec":"none","height":720,"filesize":3000000}]}
        """
        let picked = try DownloadEngine.media(from: Data(vp9First.utf8), link: URL(string: "https://youtu.be/y")!)
        #expect(picked.qualities.first?.estimatedBytes == 3_000_000)
        #expect(media.qualities[0].label == "1440p")
        #expect(media.details.hasSuffix("up to 1440p"))
        #expect(RemoteMedia.Quality(height: 2160, estimatedBytes: nil).label == "4K")
    }

    @Test("Errors read like sentences")
    func errors() {
        let tiktok = URL(string: "https://www.tiktok.com/@a/video/1")!
        #expect(DownloadEngine.explain("ERROR: Unsupported URL: https://x", link: tiktok) == .unsupportedLink)
        #expect(DownloadEngine.explain("ERROR: [TikTok] 1: This post may not be comfortable for some audiences. Log in for access", link: tiktok) == .loginRequired(site: "TikTok"))
        #expect(DownloadEngine.explain("ERROR: [youtube] x: Video unavailable", link: tiktok).errorDescription?.contains("isn’t available") == true)
    }
}

/// Real downloads. Run with CONVETA_NETWORK_TESTS=1; uses the engine at CONVETA_YTDLP, else the one the app installed.
@Suite("Downloads over the network", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["CONVETA_NETWORK_TESTS"] == "1"))
struct NetworkDownloadTests {
    let engine = DownloadEngine(
        executable: URL(filePath: ProcessInfo.processInfo.environment["CONVETA_YTDLP"]
            ?? NSHomeDirectory() + "/Library/Application Support/Conveta/Engines/yt-dlp"),
        ffmpegFolder: testTools?.ffmpeg.deletingLastPathComponent())
    let link = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!

    @Test("Inspect, then download as MP4 (no conversion) and as MP3 (converted)")
    func youtube() async throws {
        let fixtures = try Fixtures()
        defer { fixtures.remove() }
        let media = try await engine.inspect(link)
        #expect(media.title == "Me at the zoo")
        #expect(media.site == "YouTube")

        let service = DownloadService(engine: engine, conversion: ConversionService(tools: testTools))
        var settings = ConversionSettings(format: .mp4)
        settings.video.resolution = .p480
        let values = Recorder()
        let mp4 = try await service.download(media, settings: settings, into: fixtures.folder) { values.add($0) }
        #expect(mp4.lastPathComponent == "Me at the zoo.mp4")
        #expect(values.all.last == 1 || (values.all.last ?? 0) > 0.9)
        let info = try await MediaProbe.probe(mp4)
        #expect(info.hasAudio && (info.duration ?? 0) > 18)

        let mp3 = try await service.download(media, settings: ConversionSettings(format: .mp3), into: fixtures.folder)
        #expect(mp3.lastPathComponent == "Me at the zoo.mp3")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixtures.folder.path).filter { $0.hasPrefix(".conveta-") }.isEmpty)
    }

    @Test("Engine installs from the official release with a verified checksum")
    func install() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "engine-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let fresh = DownloadEngine(executable: folder.appending(path: "yt-dlp"), ffmpegFolder: nil)
        try await fresh.install()
        let version = await fresh.version()
        #expect(version == (try await DownloadEngine.latestVersion()))
    }
}
