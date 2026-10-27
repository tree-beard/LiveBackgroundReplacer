import AVFoundation
import CoreImage

final class VideoCameraController: NSObject {
    enum State: Equatable {
        case stopped, requestingAccess, starting, running, denied, restricted
        case failed(String)

        var message: String {
            switch self {
            case .stopped: return "Camera stopped"
            case .requestingAccess: return "Waiting for camera access…"
            case .starting: return "Starting camera…"
            case .running: return "Camera running"
            case .denied: return "Allow camera access in System Settings → Privacy & Security → Camera."
            case .restricted: return "Camera access is restricted by the system."
            case .failed(let message): return message
            }
        }
    }

    struct Metrics {
        let processedFPS: Double
        let visionMilliseconds: Double
        let droppedFrames: Int
        let warning: String?
    }

    // Callbacks are installed before start and never replaced while capturing.
    var onState: ((UUID, State) -> Void)? // Main queue; identifies the start/stop request.
    var onFrame: ((CIImage) -> Void)? // Processing queue; receiver must be thread safe.
    var onMetrics: ((Metrics) -> Void)? // Main queue, at most once per second.

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let processingQueue = DispatchQueue(label: "camera.processing", qos: .userInitiated)
    private let processor = FrameProcessor()
    private var configured = false
    private var wantsRunning = false
    private var requestingAccess = false
    private var requestID = UUID()
    private var observers: [NSObjectProtocol] = []
    // Metrics belong exclusively to processingQueue.
    private var intervalStart = ProcessInfo.processInfo.systemUptime
    private var processedFrames = 0
    private var droppedFrames = 0
    private var visionTotal = 0.0

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let message = error?.localizedDescription ?? "Camera session error."
            self?.sessionQueue.async { [weak self] in
                guard let self, self.wantsRunning else { return }
                self.fail(message)
            }
        })
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.didStopRunningNotification] {
            observers.append(center.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in
                    guard let self, self.wantsRunning else { return }
                    // Ignore delayed notifications from a previous stop/restart.
                    let stillInterrupted = name == AVCaptureSession.wasInterruptedNotification
                        || !self.session.isRunning
                    guard stillInterrupted else { return }
                    self.fail("Camera capture was interrupted. Try starting again when the camera is available.")
                }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        // Capture the session, not the controller, for asynchronous cleanup.
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func setMode(_ mode: BackgroundMode) {
        processingQueue.async { [weak self] in self?.processor.mode = mode }
    }

    func startCamera(requestID: UUID) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.requestID = requestID
            self.wantsRunning = true
            self.startIfAuthorized()
        }
    }

    func stopCamera(requestID: UUID) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.requestID = requestID
            self.wantsRunning = false
            if self.session.isRunning { self.session.stopRunning() }
            self.publish(.stopped)
        }
    }

    private func startIfAuthorized() {
        guard wantsRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            guard !session.isRunning else { publish(.running); return }
            publish(.starting)
            do {
                if !configured { try configure() }
                processingQueue.async { [weak self] in
                    guard let self else { return }
                    self.intervalStart = ProcessInfo.processInfo.systemUptime
                    self.processedFrames = 0
                    self.droppedFrames = 0
                    self.visionTotal = 0
                }
                session.startRunning()
                if session.isRunning { publish(.running) }
                else { fail("Unable to start the camera.") }
            } catch {
                fail(error.localizedDescription)
            }
        case .notDetermined:
            guard !requestingAccess else { return }
            requestingAccess = true
            publish(.requestingAccess)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in
                    guard let self else { return }
                    self.requestingAccess = false
                    self.startIfAuthorized()
                }
            }
        case .denied:
            wantsRunning = false
            publish(.denied)
        case .restricted:
            wantsRunning = false
            publish(.restricted)
        @unknown default: publish(.failed("Unknown camera authorization status."))
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraError.configuration("No camera found. Connect a camera and try again.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: processingQueue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw CameraError.configuration("Unable to add the camera input.") }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CameraError.configuration("Unable to configure video output.")
        }
        session.addOutput(output)
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        // Mirror the final composite in the renderer, keeping Vision and source aligned.
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        configured = true
    }

    private func publish(_ state: State) {
        let requestID = requestID
        DispatchQueue.main.async { [weak self] in self?.onState?(requestID, state) }
    }

    private func fail(_ message: String) {
        wantsRunning = false
        session.stopRunning()
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        configured = false
        publish(.failed(message))
    }

    private enum CameraError: LocalizedError {
        case configuration(String)
        var errorDescription: String? {
            switch self { case .configuration(let message): return message }
        }
    }
}

extension VideoCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            guard let result = processor.process(sampleBuffer) else { return }
            onFrame?(result.image)
            processedFrames += 1
            visionTotal += result.visionMilliseconds
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - intervalStart
            if elapsed >= 1 {
                let metrics = Metrics(processedFPS: Double(processedFrames) / elapsed,
                                      visionMilliseconds: visionTotal / Double(processedFrames),
                                      droppedFrames: droppedFrames, warning: result.warning)
                DispatchQueue.main.async { [weak self] in self?.onMetrics?(metrics) }
                intervalStart = now
                processedFrames = 0
                visionTotal = 0
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        droppedFrames += 1
    }
}
