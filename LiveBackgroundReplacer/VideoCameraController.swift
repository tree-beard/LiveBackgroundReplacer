//
//  VideoCameraController.swift
//  LiveBackgroundReplacer
//
//  Created by David Arakelyan on 21.08.2024.
//

import Foundation
import AVFoundation
import CoreImage

class VideoCameraController: NSObject {

    public var frameProcessor: FrameProcessor?

    @objc dynamic private let captureSession = AVCaptureSession()
    private let captureSessionQueue = DispatchQueue(label: "VideoCameraController_capture_session_queue",
                                                    attributes: [])
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var setupComplete = false

    init(_ frameProcessor: FrameProcessor? = nil) {
        super.init()
        self.frameProcessor = frameProcessor

        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            self.captureSessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: AVMediaType.video) {
                (granted: Bool) -> Void in
                guard granted else {
                    // Report an error. We didn't get access to hardware.
                    return
                }
                self.captureSessionQueue.resume()
            }
        }

        // All good, access granted.
        self.setupCamera(for: .back)
    }

    // Use a separate queue for handling all camera-related actions
    private func setupCamera(for cameraPosition: AVCaptureDevice.Position) {
        captureSessionQueue.async {
            self.prepareInput(for: cameraPosition)
            self.setupOutputs()

            if self.captureSession.canSetSessionPreset(.photo) {
                self.captureSession.sessionPreset = .photo
            }
            self.setupComplete = true
            self.startCamera()

        }
    }

    // Setup input (camera device)
    private func prepareInput(for cameraPosition: AVCaptureDevice.Position) {

        guard let videoDevice = captureDevice(with: AVMediaType.video.rawValue, position: cameraPosition) else {
            return
        }
        let videoDeviceInput: AVCaptureDeviceInput!
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            fatalError(error.localizedDescription)
        }

        if self.captureSession.canAddInput(videoDeviceInput) {
            self.captureSession.addInput(videoDeviceInput)
            self.videoInput = videoDeviceInput
        }
    }

    // Video camera controller will use video data output. The output will call the delegate every time the sample buffer is ready
    private func setupOutputs() {
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: self.captureSessionQueue)
        if self.captureSession.canAddOutput(videoDataOutput) {
            self.captureSession.addOutput(videoDataOutput)
            self.videoOutput = videoDataOutput
        }
    }

    // The camera can be started and will begin to produce an output buffer
    func startCamera() {
        if !setupComplete {
            return
        }

        if captureSession.isRunning {
            return
        }

        captureSessionQueue.async { [unowned self] in
            self.captureSession.startRunning()
        }
    }

    func stopCamera() {
        if !setupComplete {
            return
        }

        if !captureSession.isRunning {
            return
        }

        captureSessionQueue.async { [unowned self] in
            self.captureSession.stopRunning()
        }
    }

    // Helper method for creating capture device
    // It uses a discovery session to retrieve available capture devices (front and back cameras)
    private func captureDevice(with mediaType: String, position: AVCaptureDevice.Position?) -> AVCaptureDevice? {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
        let cameras = session.devices
        let captureDevice = cameras.first
        return captureDevice
    }
}

// Delegate for video output
extension VideoCameraController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        frameProcessor?.sourceFrame = sampleBuffer
    }
}
