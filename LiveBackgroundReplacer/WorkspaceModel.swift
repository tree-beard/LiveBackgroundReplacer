import SwiftUI
import CoreImage
import Metal
import UniformTypeIdentifiers
import ImageIO

struct SnapshotDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackgroundOption: Identifiable {
    let id: String
    let name: String
    let image: CIImage
    let thumbnail: NSImage
}

@MainActor
final class WorkspaceModel: ObservableObject {
    enum Effect: Hashable {
        case original
        case blur
        case background(String)
    }

    @Published private(set) var state: VideoCameraController.State = .stopped
    @Published private(set) var metrics: VideoCameraController.Metrics?
    @Published private(set) var warning: String?
    @Published private(set) var requestedRunning = false
    @Published var isExportingSnapshot = false
    @Published private(set) var snapshotDocument: SnapshotDocument?
    @Published private(set) var snapshotFilename = "Snapshot"
    @Published var snapshotError: String?
    @Published var effect: Effect = .background("alpine_lake") { didSet { updateMode() } }
    @Published private(set) var backgrounds: [BackgroundOption] = []
    @Published private(set) var isLoadingBackground = false
    @Published var backgroundImportError: String?
    @Published var blurRadius = 15.0 { didSet { updateMode() } }
    @Published var mirrored = true { didSet { renderer?.mirrored = mirrored } }
    let renderer: Renderer?
    private let camera: VideoCameraController
    private let backgroundQueue = DispatchQueue(label: "background.import", qos: .userInitiated)
    private let preview: Bool
    private var requestID = UUID()

    init(preview: Bool = false) {
        self.preview = preview
        camera = VideoCameraController()
        backgrounds = [
            ("alpine_lake", "Alpine Lake"),
            ("background_office", "Bright Office"),
            ("background_living_room", "Cozy Living Room")
        ].compactMap { id, name in
            guard let thumbnail = NSImage(named: id),
                  let data = thumbnail.tiffRepresentation,
                  let image = CIImage(data: data) else { return nil }
            return BackgroundOption(id: id, name: name, image: image, thumbnail: thumbnail)
        }
        do {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw Renderer.RendererError.unavailable
            }
            renderer = try Renderer(device: device)
        } catch {
            renderer = nil
            state = .failed(error.localizedDescription)
        }
        camera.onFrame = { [weak renderer] frame in renderer?.submit(frame) }
        camera.onState = { [weak self] requestID, state in
            guard let self, self.requestID == requestID else {
                return
            }
            self.state = state
            switch state {
            case .failed, .denied, .restricted:
                self.requestedRunning = false
                self.renderer?.setAcceptingFrames(false)
            default: break
            }
        }
        camera.onMetrics = { [weak self] metrics in
            guard let self, self.requestedRunning else {
                return
            }
            self.metrics = metrics
        }
        updateMode()
    }

    func start() {
        guard !preview, renderer != nil else {
            return
        }
        requestedRunning = true
        requestID = UUID()
        metrics = nil
        renderer?.setAcceptingFrames(true)
        camera.startCamera(requestID: requestID)
    }

    func stop() {
        guard renderer != nil else {
            return
        }
        requestedRunning = false
        requestID = UUID()
        renderer?.setAcceptingFrames(false)
        metrics = nil
        camera.stopCamera(requestID: requestID)
    }

    func captureSnapshot() {
        guard !isExportingSnapshot else {
            return
        }
        guard let data = renderer?.snapshotPNG() else {
            snapshotError = "No frame is available yet. Start the camera and try again."
            return
        }
        // Encode now so the saved image cannot change while the dialog is open.
        snapshotDocument = SnapshotDocument(data: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        snapshotFilename = "Snapshot-\(formatter.string(from: Date()))"
        isExportingSnapshot = true
    }

    func finishSnapshotExport(_ result: Result<URL, Error>) {
        snapshotDocument = nil
        if case .failure(let error) = result {
            snapshotError = error.localizedDescription
        }
    }

    func importBackground(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                backgroundImportError = error.localizedDescription
            }
        case .success(let url):
            guard !isLoadingBackground else {
                return
            }
            isLoadingBackground = true
            backgroundQueue.async { [weak self] in
                let loaded = Result { try Self.loadBackground(from: url) }
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }
                    self.isLoadingBackground = false
                    switch loaded {
                    case .success(let background):
                        self.backgrounds.append(background)
                        self.effect = .background(background.id)
                    case .failure(let error):
                        self.backgroundImportError = error.localizedDescription
                    }
                }
            }
        }
    }

    private nonisolated static func loadBackground(from url: URL) throws -> BackgroundOption {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw BackgroundImportError.invalidImage
        }
        // Decode off the main thread and bound large images; honor EXIF orientation.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2560,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw BackgroundImportError.invalidImage
        }
        var thumbnailOptions = options
        thumbnailOptions[kCGImageSourceThumbnailMaxPixelSize] = 192
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) ?? image
        return BackgroundOption(id: UUID().uuidString,
                                name: url.deletingPathExtension().lastPathComponent,
                                image: CIImage(cgImage: image),
                                thumbnail: NSImage(cgImage: thumbnail, size: .zero))
    }

    private enum BackgroundImportError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "Unable to open this image. Choose a valid PNG, JPEG, HEIC, or TIFF file." }
    }

    private func updateMode() {
        warning = nil
        switch effect {
        case .original: camera.setMode(.original)
        case .blur: camera.setMode(.blur(radius: blurRadius))
        case .background(let id):
            if let background = backgrounds.first(where: { $0.id == id }) {
                camera.setMode(.image(background.image))
            } else {
                warning = "Unable to load the background. Showing the original frame."
                camera.setMode(.original)
            }
        }
    }
}
