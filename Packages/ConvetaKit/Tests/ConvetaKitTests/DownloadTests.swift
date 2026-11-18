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

    @Test("Download arguments: H.264 MP4 within the size limit, or best audio")
    func arguments() {
        let video = DownloadEngine.downloadArguments(audioOnly: false, maxHeight: 720, folder: URL(filePath: "/w")).joined(separator: " ")
        #expect(video.contains("-S res:720,vcodec:h264,acodec:aac"))
        #expect(video.contains("--merge-output-format mp4"))
        #expect(video.contains("--no-simulate"))
        let audio = DownloadEngine.downloadArguments(audioOnly: true, maxHeight: nil, folder: URL(filePath: "/w")).joined(separator: " ")
        #expect(audio.contains("-f ba/b"))
        #expect(!audio.contains("merge-output"))
    }

    @Test("A download skips conversion only when it already matches")
    func readiness() {
        #expect(DownloadService.isReady(downloadedAs: "mp4", for: ConversionSettings(format: .mp4)))
        var settings = ConversionSettings(format: .mp4)
        settings.video.codec = .hevc
        #expect(!DownloadService.isReady(downloadedAs: "mp4", for: settings))
        #expect(!DownloadService.isReady(downloadedAs: "mp4", for: ConversionSettings(format: .mov)))
        #expect(DownloadService.isReady(downloadedAs: "m4a", for: ConversionSettings(format: .m4a)))
        #expect(!DownloadService.isReady(downloadedAs: "m4a", for: ConversionSettings(format: .mp3)))
    }

    @Test("Errors read like sentences")
    func errors() {
        let tiktok = URL(string: "https://www.tiktok.com/@a/video/1")!
        #expect(DownloadEngine.explain("ERROR: Unsupported URL: https://x", link: tiktok) == .unsupportedLink)
        #expect(DownloadEngine.explain("ERROR: [TikTok] 1: This post may not be comfortable for some audiences. Log in for access", link: tiktok) == .loginRequired(site: "TikTok"))
        #expect(DownloadEngine.explain("ERROR: [youtube] x: Video unavailable", link: tiktok).errorDescription?.contains("isn’t available") == true)
    }
}

/// Real downloads. Run with CONVETA_NETWORK_TESTS=1 and an engine at CONVETA_YTDLP (default /tmp/ytdlp-test/yt-dlp).
@Suite("Downloads over the network", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["CONVETA_NETWORK_TESTS"] == "1"))
struct NetworkDownloadTests {
    let engine = DownloadEngine(
        executable: URL(filePath: ProcessInfo.processInfo.environment["CONVETA_YTDLP"] ?? "/tmp/ytdlp-test/yt-dlp"),
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
