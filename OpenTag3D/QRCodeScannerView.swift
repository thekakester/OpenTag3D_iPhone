import AVFoundation
import SwiftUI

private enum QRCodeScannerError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case cameraInputUnavailable
    case metadataOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to scan QR codes."
        case .cameraUnavailable:
            return "This device does not have an available camera."
        case .cameraInputUnavailable:
            return "The camera could not be prepared for QR scanning."
        case .metadataOutputUnavailable:
            return "The QR-code scanner could not be prepared."
        }
    }
}

/// Full-screen QR scanner used by the Import Tag menu.
struct QRCodeScannerView: View {
    let onCode: (String) -> Void
    let onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            QRCodeCameraPreview { code in
                onCode(code)
            } onFailure: { error in
                errorMessage = error.localizedDescription
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                }

                Spacer()

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 180, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)

                Spacer()

                Text("Point the camera at an OpenTag3D QR code")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            .padding()

            if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("Close", action: onCancel)
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .foregroundStyle(.white)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
    }
}

private struct QRCodeCameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onFailure: (Error) -> Void

    func makeUIViewController(context: Context) -> QRCodeCameraViewController {
        QRCodeCameraViewController(onCode: onCode, onFailure: onFailure)
    }

    func updateUIViewController(
        _ uiViewController: QRCodeCameraViewController,
        context: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: QRCodeCameraViewController,
        coordinator: Void
    ) {
        uiViewController.stopScanning()
    }
}

private final class QRCodeCameraViewController: UIViewController,
    AVCaptureMetadataOutputObjectsDelegate {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "OpenTag3D.QRCodeScanner")
    private let onCode: (String) -> Void
    private let onFailure: (Error) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didReportCode = false

    init(
        onCode: @escaping (String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.onCode = onCode
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func stopScanning() {
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] isGranted in
                guard let self else { return }
                if isGranted {
                    self.configureCaptureSession()
                } else {
                    self.reportFailure(QRCodeScannerError.cameraPermissionDenied)
                }
            }
        case .denied, .restricted:
            reportFailure(QRCodeScannerError.cameraPermissionDenied)
        @unknown default:
            reportFailure(QRCodeScannerError.cameraPermissionDenied)
        }
    }

    private func configureCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.captureSession.beginConfiguration()
            do {
                guard let camera = self.preferredBackCamera() else {
                    throw QRCodeScannerError.cameraUnavailable
                }
                try self.configureFocus(for: camera)

                let cameraInput = try AVCaptureDeviceInput(device: camera)
                guard self.captureSession.canAddInput(cameraInput) else {
                    throw QRCodeScannerError.cameraInputUnavailable
                }

                let metadataOutput = AVCaptureMetadataOutput()
                guard self.captureSession.canAddOutput(metadataOutput) else {
                    throw QRCodeScannerError.metadataOutputUnavailable
                }

                self.captureSession.addInput(cameraInput)
                self.captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                metadataOutput.metadataObjectTypes = [.qr]
                self.captureSession.commitConfiguration()
                self.captureSession.startRunning()
            } catch {
                self.captureSession.commitConfiguration()
                self.reportFailure(error)
            }
        }
    }

    /// Prefers a virtual camera that can switch to the ultra-wide constituent
    /// when the main wide camera reaches its minimum focusing distance.
    private func preferredBackCamera() -> AVCaptureDevice? {
        let preferredDeviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera
        ]

        for deviceType in preferredDeviceTypes {
            if let camera = AVCaptureDevice.default(
                deviceType,
                for: .video,
                position: .back
            ) {
                return camera
            }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func configureFocus(for camera: AVCaptureDevice) throws {
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }

        if camera.isVirtualDevice {
            camera.setPrimaryConstituentDeviceSwitchingBehavior(
                .auto,
                restrictedSwitchingBehaviorConditions: []
            )
        }

        if camera.isFocusPointOfInterestSupported {
            camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isAutoFocusRangeRestrictionSupported {
            camera.autoFocusRangeRestriction = .near
        }
        camera.isSubjectAreaChangeMonitoringEnabled = true
    }

    private func reportFailure(_ error: Error) {
        DispatchQueue.main.async { [onFailure] in
            onFailure(error)
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard didReportCode == false,
              let qrCode = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = qrCode.stringValue else {
            return
        }

        didReportCode = true
        stopScanning()
        onCode(value)
    }
}
