import AppKit
import ConvetaKit
import Foundation
import Observation
import QuickLookThumbnailing

/// The list of files and the engine that works through it.
@Observable
final class ConversionQueue {
    private(set) var jobs: [ConversionJob] = []
    var selection: Set<ConversionJob.ID> = []
    /// Set while a batch runs; drives the toolbar, Dock tile and menu.
    private(set) var isRunning = false

    let preferences: Preferences
    let access: FolderAccess
    let downloader: Downloader
    @ObservationIgnored let tools = FFmpegTools.bundled()
    @ObservationIgnored private lazy var service = ConversionService(tools: tools)
    @ObservationIgnored private var tasks: [ConversionJob.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var batch: [ConversionJob.ID] = []
    @ObservationIgnored var onBatchFinished: (([ConversionJob]) -> Void)?

    init(preferences: Preferences, access: FolderAccess, downloader: Downloader) {
        self.preferences = preferences
        self.access = access
        self.downloader = downloader
    }

    // MARK: Reading

    func job(_ id: ConversionJob.ID) -> ConversionJob? { jobs.first { $0.id == id } }

    var selectedJobs: [ConversionJob] { jobs.filter { selection.contains($0.id) } }

    /// What the inspector edits: the selected files that can still change, or, with nothing
    /// selected, every file that can.
    var editingTargets: [ConversionJob] {
        let pool = selection.isEmpty ? jobs : selectedJobs
        return pool.filter { $0.state.isEditable && $0.kind != nil }
    }

    var startableJobs: [ConversionJob] { jobs.filter(\.state.isStartable) }
    var finishedJobs: [ConversionJob] { jobs.filter(\.state.isFinished) }
    var canConvert: Bool { !isRunning && !startableJobs.isEmpty }

    /// Progress of the running batch, 0...1.
    var batchProgress: Double {
        let members = batch.compactMap(job)
        guard !members.isEmpty else { return 0 }
        return members.reduce(0) { $0 + ($1.state == .converting ? $1.progress : ($1.state.isActive ? 0 : 1)) } / Double(members.count)
    }

    // MARK: Adding

    /// Adds files (folders are searched for media). With `format`, files that can become it use it;
    /// with `start`, they convert as soon as they are read.
    /// Adds files and converts them with a preset (from Finder or Shortcuts). Files the preset doesn't suit wait.
    func add(_ urls: [URL], preset: Preset) {
        let added = add(urls, format: preset.settings.format, start: false)
        Task {
            while added.contains(where: { $0.state == .probing }) { try? await Task.sleep(for: .milliseconds(50)) }
            let suitable = added.filter { $0.kind.map(preset.applies(to:)) == true }
            for job in suitable { job.settings = preset.apply(to: job.settings) }
            convert(Array(suitable))
        }
    }

    @discardableResult
    func add(_ urls: [URL], format: OutputFormat? = nil, start: Bool = false) -> [ConversionJob] {
        let links = urls.filter(LinkDetector.isWebLink)
        if !links.isEmpty { addLinks(links, format: format, start: start) }
        let known = Set(jobs.filter { !$0.state.isFinished }.map(\.source.standardizedFileURL))
        let files = Self.expand(urls.filter(\.isFileURL)).filter { !known.contains($0.standardizedFileURL) }
        guard !files.isEmpty else { return [] }

        let added = files.map { url in
            ConversionJob(source: url, settings: ConversionSettings(format: format ?? .mp4))
        }
        jobs.append(contentsOf: added)
        let start = start || preferences.startImmediately
        Task {
            // Read every file first, so a batch asks for folder access once and starts together.
            await withDiscardingTaskGroup { group in
                for job in added { group.addTask { await self.prepare(job, format: format) } }
            }
            if start { convert(added) }
            for job in added { job.thumbnail = await Self.thumbnail(for: job.source) }
        }
        return added
    }

    private func prepare(_ job: ConversionJob, format: OutputFormat?) async {
        do {
            let info = try await MediaProbe.probe(job.source, tools: tools)
            job.info = info
            var settings = preferences.settings(for: info.kind)
            if let format, info.kind.outputFormats.contains(format) { settings.format = format }
            job.settings = settings
            job.state = .ready
        } catch {
            job.state = .unsupported(error.localizedDescription)
        }
    }

    /// Adds web links (YouTube, Instagram, TikTok and more). Each is read for its title and
    /// thumbnail, then downloads like a file converts. The engine installs on first use.
    func addLinks(_ links: [URL], format: OutputFormat? = nil, height: Int? = nil, start: Bool = false) {
        let known = Set(jobs.filter { !$0.state.isFinished }.map(\.source.absoluteString))
        let fresh = links.filter { !known.contains($0.absoluteString) }
        guard !fresh.isEmpty else { return }
        let added = fresh.map { ConversionJob(source: $0, settings: ConversionSettings(format: format ?? .mp4)) }
        jobs.append(contentsOf: added)
        let start = start || preferences.startImmediately
        Task {
            do {
                try await downloader.ensureReady()
            } catch {
                for job in added { job.state = .unsupported(error.localizedDescription) }
                return
            }
            await withDiscardingTaskGroup { group in
                for job in added { group.addTask { await self.prepareLink(job, format: format, height: height) } }
            }
            if start { convert(added) }
        }
    }

    /// Adds a link that was already read (by the link sheet): one download per chosen height,
    /// named "Title (1080p)" when there are several. Starts at once.
    func addDownloads(_ media: RemoteMedia, heights: [Int?], format: OutputFormat) {
        addDownloads([media], heights: heights, format: format)
    }

    /// Several videos (a playlist), each at the given heights, all starting together.
    func addDownloads(_ items: [RemoteMedia], heights: [Int?], format: OutputFormat) {
        let several = heights.count > 1
        let added = items.flatMap { media in heights.map { height -> ConversionJob in
            var settings = preferences.settings(for: media.kind)
            if media.kind.outputFormats.contains(format) { settings.format = format }
            settings.downloadHeight = height
            settings.subtitles = preferences.subtitles
            let job = ConversionJob(source: media.link, settings: settings)
            job.remote = media
            job.info = media.plannedInfo
            if several, let height { job.nameSuffix = " (\(RemoteMedia.Quality(height: height, estimatedBytes: nil).label))" }
            job.state = .ready
            return job
        } }
        jobs.append(contentsOf: added)
        convert(added)
        Task {
            // One fetch per distinct thumbnail, a few at a time.
            for job in added where job.thumbnail == nil {
                guard let url = job.remote?.thumbnail else { continue }
                let image = await Self.image(at: url)
                for twin in added where twin.remote?.thumbnail == url { twin.thumbnail = image }
            }
        }
    }

    private func prepareLink(_ job: ConversionJob, format: OutputFormat?, height: Int?) async {
        do {
            let media = try await downloader.engine.inspect(job.source)
            job.remote = media
            job.info = media.plannedInfo
            var settings = preferences.settings(for: media.kind)
            if let format, media.kind.outputFormats.contains(format) { settings.format = format }
            settings.downloadHeight = height
            settings.subtitles = preferences.subtitles
            job.settings = settings
            job.state = .ready
            if let thumbnail = media.thumbnail { job.thumbnail = await Self.image(at: thumbnail) }
        } catch {
            job.state = .unsupported(error.localizedDescription)
        }
    }

    static func image(at url: URL) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    /// Files inside folders, skipping hidden files and packages.
    static func expand(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return [url] }
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
            return (enumerator?.allObjects as? [URL] ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                .filter { MediaKind(url: $0) != nil }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 80, height: 80),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    // MARK: Editing

    /// Applies a change to every job the inspector edits (only those of `kind`, if given),
    /// and remembers it for files of the same kind.
    func updateSettings(kind: MediaKind? = nil, _ change: (inout ConversionSettings) -> Void) {
        for job in editingTargets where kind == nil || job.kind == kind {
            change(&job.settings)
            if let kind = job.kind { preferences.remember(job.settings, for: kind) }
        }
    }

    func remove(_ ids: Set<ConversionJob.ID>) {
        for id in ids { tasks[id]?.cancel() }
        jobs.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func clearFinished() {
        remove(Set(jobs.filter { $0.state.isFinished || $0.state == .cancelled || $0.state.isUnsupported }.map(\.id)))
    }

    // MARK: Converting

    /// Starts the selected files, or everything waiting when nothing startable is selected.
    func convertSelectionOrAll() {
        let selected = selectedJobs.filter(\.state.isStartable)
        convert(selected.isEmpty ? startableJobs : selected)
    }

    func convert(_ candidates: [ConversionJob]) {
        let startable = candidates.filter(\.state.isStartable)
        guard !startable.isEmpty else { return }
        if !isRunning { batch = [] }
        // Queue first: the access panel below is modal, and a second Convert arriving while it is
        // open (menu, URL, Shortcuts) must find these jobs already taken.
        for job in startable {
            job.state = .queued
            job.progress = 0
            job.output = nil
            batch.append(job.id)
        }
        isRunning = true
        requestMissingAccess(for: startable)
        pump()
    }

    func cancel(_ ids: Set<ConversionJob.ID>) {
        for job in jobs where ids.contains(job.id) {
            if job.state == .queued { job.state = .cancelled }
            tasks[job.id]?.cancel()
        }
        finishIfIdle()
    }

    func cancelAll() {
        cancel(Set(jobs.filter(\.state.isActive).map(\.id)))
    }

    /// Starts queued jobs until the parallel limit is reached.
    private func pump() {
        let running = jobs.filter { $0.state == .converting }.count
        let free = max(1, preferences.parallelJobs) - running
        for job in jobs.filter({ $0.state == .queued }).prefix(max(0, free)) {
            run(job)
        }
        finishIfIdle()
    }

    private func run(_ job: ConversionJob) {
        guard let info = job.info else { job.state = .failed("The file couldn’t be read."); return }
        guard let folder = outputFolder(for: job) else {
            job.state = .failed("Choose an output folder in Settings.")
            return
        }
        job.state = .converting
        job.startedAt = .now
        let settings = job.settings
        let source = job.source
        let service = service
        let remote = job.remote
        let suffix = job.nameSuffix
        let downloads = remote.map { _ in DownloadService(engine: downloader.engine, conversion: service) }

        tasks[job.id] = Task {
            do {
                let report: ProgressHandler = { value in
                    Task { @MainActor in if job.state == .converting { job.progress = value } }
                }
                guard access.canWrite(to: folder) else { throw ConversionError.noWriteAccess(folder) }
                let output: URL
                if let remote, let downloads {
                    output = try await downloads.download(remote, settings: settings, into: folder, nameSuffix: suffix, progress: report)
                } else {
                    guard access.canRead(source) else { throw ConversionError.unreadable }
                    output = try await service.convert(source, info: info, settings: settings, into: folder, progress: report)
                }
                job.output = output
                job.outputSize = Self.size(of: output)
                job.progress = 1
                job.state = .done
            } catch is CancellationError {
                job.state = .cancelled
            } catch {
                job.state = .failed(error.localizedDescription)
            }
            job.finishedAt = .now
            tasks[job.id] = nil
            pump()
        }
    }

    /// Asks once, before a batch starts, for the folders the sandbox doesn't allow yet.
    /// The panel opens at the deepest folder they share, so one choice usually covers all of them.
    private func requestMissingAccess(for jobs: [ConversionJob]) {
        var missing: [URL] = []
        for job in jobs {
            if !job.isDownload, !access.canRead(job.source) { missing.append(job.source.deletingLastPathComponent()) }
            if let folder = outputFolder(for: job), !access.canWrite(to: folder) { missing.append(folder) }
        }
        guard let shared = FolderAccess.commonAncestor(of: missing) else { return }
        let name = shared.path == "/" ? "these folders" : "“\(shared.lastPathComponent)”"
        access.requestAccess(to: shared, reason: "Conveta needs permission to read and save files in \(name). Choosing your home folder covers every folder inside it.")
    }

    func outputFolder(for job: ConversionJob) -> URL? {
        switch preferences.destination {
        case .nextToOriginal where !job.isDownload:
            return job.source.deletingLastPathComponent()
        case .nextToOriginal, .downloads:  // a download has no original folder
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .folder:
            guard let bookmark = preferences.customFolder else { return nil }
            var stale = false
            return (try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale))
                ?? (try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        }
    }

    private func finishIfIdle() {
        guard isRunning, !jobs.contains(where: \.state.isActive) else { return }
        isRunning = false
        let finished = batch.compactMap(job)
        batch = []
        onBatchFinished?(finished)
    }

    private static func size(of url: URL) -> Int64? {
        let manager = FileManager.default
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        }
        let files = manager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? []
        return files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
    }

    // MARK: Finder

    func revealOutputs(of ids: Set<ConversionJob.ID>) {
        let urls = jobs.filter { ids.contains($0.id) }.compactMap(\.output)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    /// Shows original files in Finder, and opens the pages of downloads in the browser.
    func revealSources(of ids: Set<ConversionJob.ID>) {
        let selected = jobs.filter { ids.contains($0.id) }
        let files = selected.filter { !$0.isDownload }.map(\.source)
        if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
        for job in selected where job.isDownload { NSWorkspace.shared.open(job.remote?.pageURL ?? job.source) }
    }
}

extension ConversionJob.State {
    var isUnsupported: Bool {
        if case .unsupported = self { true } else { false }
    }
}

import UniformTypeIdentifiers
