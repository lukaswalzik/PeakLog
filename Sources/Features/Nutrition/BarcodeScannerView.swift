import AVFoundation
import SwiftUI
import UIKit

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss

    let onScanned: (String) -> Void

    @State private var isTorchOn: Bool = false
    @State private var cameraError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                if let error = cameraError {
                    EmptyStateView(
                        systemImage: "camera.fill",
                        title: "Kamera nicht verfügbar",
                        message: error
                    )
                } else {
                    BarcodeScannerRepresentable(
                        isTorchOn: $isTorchOn,
                        onScanned: { code in
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onScanned(code)
                            dismiss()
                        },
                        onError: { msg in
                            cameraError = msg
                        }
                    )
                    .ignoresSafeArea()

                    // Scan frame overlay
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 270, height: 165)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Text("Barcode in den Rahmen halten")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(.top, 16)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isTorchOn.toggle()
                    } label: {
                        Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    @Binding var isTorchOn: Bool
    let onScanned: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScanned = onScanned
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.setTorch(enabled: isTorchOn)
    }

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScanned: ((String) -> Void)?
        var onError: ((String) -> Void)?

        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var hasEmittedCode = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setTorch(enabled: false)
            if session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.stopRunning()
                }
            }
        }

        func setTorch(enabled: Bool) {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = enabled ? .on : .off
                device.unlockForConfiguration()
            } catch {}
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video) else {
                onError?("Keine Kamera auf diesem Gerät gefunden.")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }

                let output = AVCaptureMetadataOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                    output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]
                }

                let layer = AVCaptureVideoPreviewLayer(session: session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = view.bounds
                view.layer.addSublayer(layer)
                previewLayer = layer

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                }
            } catch {
                onError?("Kamera konnte nicht gestartet werden: \(error.localizedDescription)")
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasEmittedCode,
                  let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = readable.stringValue,
                  !code.isEmpty else {
                return
            }

            hasEmittedCode = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
            onScanned?(code)
        }
    }
}
