import SwiftUI
import AVFoundation
import Vision
import PhotosUI
import AudioToolbox
import UIKit

/// 扫码页：原生相机取景 + 相册条码识别。
/// 网页版靠 BarcodeDetector/getUserMedia，在 WKWebView 里大概率被拒；原生没有这个问题。
struct ScanView: View {
    var onCode: (String) -> Void

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
    }

    @Environment(\.dismiss) private var dismiss
    @State private var denied = false
    @State private var tip = ""
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if denied {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.7))
                        Text("没有相机权限")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text("到「设置 → 回收统计 → 相机」里打开，\n或者直接用下面的「从相册识别」和手动输入。")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    CameraPreview(onCode: { code in
                        AudioServicesPlaySystemSound(1057)
                        onCode(code)
                        dismiss()
                    })
                    .ignoresSafeArea()

                    // 取景框
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 290, height: 150)
                }

                VStack {
                    Spacer()
                    Text(tip.isEmpty ? "把快递单条码对准框内，识别到自动返回" : tip)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("扫码录入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("从相册识别")
                    }
                }
            }
            .onAppear {
                AVCaptureDevice.requestAccess(for: .video) { ok in
                    DispatchQueue.main.async { denied = !ok }
                }
            }
            .onChange(of: photoItem) { item in
                guard let item = item else { return }
                tip = "正在识别…"
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data),
                       let code = await BarcodeReader.read(img) {
                        onCode(code)
                        dismiss()
                    } else {
                        tip = "这张图里没找到条码，换一张或直接手输单号"
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 相机预览

struct CameraPreview: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}
}

final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setup()
    }

    private func setup() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            // 快递面单主要是 code128，顺带支持常见的一维码与二维码
            output.metadataObjectTypes = [
                .code128, .code39, .code93, .ean13, .ean8,
                .qr, .pdf417, .itf14, .upce, .dataMatrix
            ]
        }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !handled else { return }
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let s = obj.stringValue,
              !s.isEmpty else { return }
        handled = true
        if session.isRunning { session.stopRunning() }
        onCode?(s)
    }
}

// MARK: - 相册条码识别

enum BarcodeReader {
    /// 用 Vision 在图片里找条码；找不到返回 nil
    static func read(_ image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let req = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([req])
            let obs = req.results as? [VNBarcodeObservation]
            return obs?.compactMap { $0.payloadStringValue }.first
        }.value
    }
}
