//
//  NWCQRScannerSheet.swift
//  Nostur
//
//  Created for QR-based NWC setup on 21/06/2026.
//

import SwiftUI
import AVFoundation
import UIKit

#if canImport(VisionKit) && !targetEnvironment(macCatalyst)
import VisionKit
#endif

struct NWCQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var cameraAccess: CameraAccessState = .checking
    @State private var isTorchOn = false
    
    let onScan: (String) -> Void
    
    var body: some View {
        ZStack {
            switch cameraAccess {
            case .checking:
                ProgressView(String(localized: "Starting camera…", comment: "Loading message shown while preparing the QR scanner camera"))
            case .denied:
                permissionDeniedView
            case .allowed:
                scannerContent
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(String(localized: "Scan QR", comment: "Navigation title for the Nostr Wallet Connect QR scanner"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                if scannerMode == .legacy, LegacyQRCodeScannerViewController.hasTorch {
                    Button(
                        isTorchOn
                        ? String(localized: "Torch Off", comment: "Button to turn off the torch while scanning a QR code")
                        : String(localized: "Torch On", comment: "Button to turn on the torch while scanning a QR code"),
                        systemImage: isTorchOn ? "flashlight.off.fill" : "flashlight.on.fill"
                    ) {
                        isTorchOn.toggle()
                    }
                }
            }
        }
        .task {
            await ensureCameraAccess()
        }
    }
    
    @ViewBuilder
    private var scannerContent: some View {
        switch scannerMode {
        case .dataScanner:
            dataScannerContent
        case .legacy:
            LegacyQRCodeScannerView(isTorchOn: $isTorchOn) { scannedValue in
                handleScan(scannedValue)
            }
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom) {
                instructionBanner
            }
        case .unavailable:
            unavailableView
        }
    }
    
#if canImport(VisionKit) && !targetEnvironment(macCatalyst)
    private var dataScannerContent: AnyView {
        if #available(iOS 16.0, *) {
            return AnyView(
                DataScannerQRCodeView { scannedValue in
                    handleScan(scannedValue)
                }
                .ignoresSafeArea()
                .safeAreaInset(edge: .bottom) {
                    instructionBanner
                }
            )
        } else {
            return AnyView(unavailableView)
        }
    }
#else
    private var dataScannerContent: AnyView {
        return AnyView(unavailableView)
    }
#endif
    
    private var instructionBanner: some View {
        Text(String(localized: "Point your camera at your wallet's NWC QR code", comment: "Instruction shown while scanning a Nostr Wallet Connect QR code"))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 24)
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
            
            Text(String(localized: "Camera access is needed to scan an NWC QR code", comment: "Explanation shown when camera permission is denied for the NWC QR scanner"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            
            Button(String(localized: "Open Settings", comment: "Button to open system settings after camera permission was denied")) {
                guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(settingsUrl)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
    
    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(.white)
            
            Text(String(localized: "QR scanning is not available on this device", comment: "Message shown when QR scanning is not available on the current device"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .padding(24)
    }
    
    private func handleScan(_ scannedValue: String) {
        dismiss()
        onScan(scannedValue)
    }
    
    private var scannerMode: ScannerMode {
#if targetEnvironment(macCatalyst)
        .unavailable
#else
        guard AVCaptureDevice.default(for: .video) != nil else {
            return .unavailable
        }
        #if canImport(VisionKit)
        if #available(iOS 16.0, *),
           DataScannerViewController.isSupported,
           DataScannerViewController.isAvailable {
            return .dataScanner
        }
        #endif
        return .legacy
#endif
    }
    
    private func ensureCameraAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAccess = .allowed
        case .notDetermined:
            let accessGranted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAccess = accessGranted ? .allowed : .denied
        default:
            cameraAccess = .denied
        }
    }
}

private extension NWCQRScannerSheet {
    enum CameraAccessState {
        case checking
        case allowed
        case denied
    }
    
    enum ScannerMode {
        case dataScanner
        case legacy
        case unavailable
    }
}

#if canImport(VisionKit) && !targetEnvironment(macCatalyst)
@available(iOS 16.0, *)
private struct DataScannerQRCodeView: UIViewControllerRepresentable {
    let onFound: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound)
    }
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }
    
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onFound: (String) -> Void
        private var didScan = false
        
        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didScan else { return }
            
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { continue }
                didScan = true
                onFound(payload)
                return
            }
        }
    }
}
#endif

private struct LegacyQRCodeScannerView: UIViewControllerRepresentable {
    @Binding var isTorchOn: Bool
    let onFound: (String) -> Void
    
    func makeUIViewController(context: Context) -> LegacyQRCodeScannerViewController {
        let controller = LegacyQRCodeScannerViewController()
        controller.onFound = onFound
        return controller
    }
    
    func updateUIViewController(_ uiViewController: LegacyQRCodeScannerViewController, context: Context) {
        uiViewController.setTorch(enabled: isTorchOn)
    }
    
    static func dismantleUIViewController(_ uiViewController: LegacyQRCodeScannerViewController, coordinator: ()) {
        uiViewController.stopScanning()
    }
}

private final class LegacyQRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    static var hasTorch: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }
    
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "nostur.nwc.qr.scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didConfigureSession = false
    private var didScan = false
    
    var onFound: ((String) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScanning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    func startScanning() {
        sessionQueue.async {
            guard self.didConfigureSession, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }
    
    func stopScanning() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
    
    func setTorch(enabled: Bool) {
        sessionQueue.async {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = enabled ? .on : .off
                device.unlockForConfiguration()
            } catch {
                L.og.error("Could not toggle NWC QR scanner torch: \(error.localizedDescription)")
            }
        }
    }
    
    private func configureSession() {
        sessionQueue.async {
            guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                
                self.session.beginConfiguration()
                
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                }
                
                let metadataOutput = AVCaptureMetadataOutput()
                if self.session.canAddOutput(metadataOutput) {
                    self.session.addOutput(metadataOutput)
                    metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                    metadataOutput.metadataObjectTypes = [.qr]
                }
                
                self.session.commitConfiguration()
                
                DispatchQueue.main.async {
                    let previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                    previewLayer.videoGravity = .resizeAspectFill
                    previewLayer.frame = self.view.bounds
                    self.view.layer.insertSublayer(previewLayer, at: 0)
                    self.previewLayer = previewLayer
                }
                
                self.didConfigureSession = true
            } catch {
                L.og.error("Could not configure NWC QR scanner: \(error.localizedDescription)")
            }
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan else { return }
        
        for object in metadataObjects {
            guard let qrObject = object as? AVMetadataMachineReadableCodeObject,
                  qrObject.type == .qr,
                  let payload = qrObject.stringValue else { continue }
            didScan = true
            stopScanning()
            onFound?(payload)
            return
        }
    }
}
