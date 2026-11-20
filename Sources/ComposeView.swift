import SwiftUI
import PhotosUI

/// 一句话录入：和网页版同一个输入习惯（单号 + 物品 + 金额），支持变更单号、上门单、子母件。
struct ComposeView: View {
    /// 扫码带进来的单号：打开时预填，用户接着补物品和金额
    var initialText: String = ""

    init(initialText: String = "") {
        self.initialText = initialText
    }

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var busy = false
    @State private var err = ""
    @State private var scanning = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inputCard
                    actionRow
                    if !err.isEmpty {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(MZ.bad)
                            .padding(.horizontal, 2)
                    }
                    tips
                }
                .padding(14)
            }
            .background(MZ.bg)
            .navigationTitle("录入运单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if busy { ProgressView() } else { Text("录入").bold() }
                    }
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await submit() }
                } label: {
                    Text(busy ? "提交中…" : "录入这一单")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(text.isEmpty ? MZ.muted : MZ.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .background(MZ.bg)
            }
            .sheet(isPresented: $scanning) {
                ScanView { code in
                    appendCode(code)
                }
            }
            .onChange(of: photoItem) { item in
                guard let item = item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data),
                       let code = await BarcodeReader.read(img) {
                        appendCode(code)
                    } else {
                        err = "这张图里没找到条码，换个角度重拍或直接手输单号"
                    }
                }
            }
            .onAppear {
                if text.isEmpty && !initialText.isEmpty { text = initialText + " " }
                focused = true
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 输入

    private var inputCard: some View {
        MZCard(padding: 12) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("例：DPK202842630378 慵懒周末淡香水100mlX1瓶 300元")
                        .font(.system(size: 14))
                        .foregroundColor(MZ.muted.opacity(0.8))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .frame(minHeight: 96)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                scanning = true
            } label: {
                Label("扫码识别", systemImage: "barcode.viewfinder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MZ.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(MZ.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MZ.line, lineWidth: 1)
                    )
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("相册识别", systemImage: "photo.on.rectangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MZ.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(MZ.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MZ.line, lineWidth: 1)
                    )
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("写法示例")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MZ.muted)
            tipLine("快递单", "DPK8888888888888 慵懒周末淡香水100mlX1瓶 300元")
            tipLine("上门单", "上门 厦航国旅 植村秀粉底液X1 315")
            tipLine("换单号", "运单号：JDVE19491088993，变更，运单号：JDVC38993825710")
            tipLine("子母件", "主单号|子单1 子单2")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func tipLine(_ label: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MZ.brand)
                .frame(width: 42, alignment: .leading)
            Text(body)
                .font(.system(size: 11))
                .foregroundColor(MZ.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    private func appendCode(_ code: String) {
        err = ""
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = t + " "
        } else if !text.contains(t) {
            text = t + " " + text
        }
        focused = true
    }

    private func submit() async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return }
        busy = true
        err = ""
        let msg = await state.submitQuick(raw)
        busy = false
        if msg.isEmpty {
            text = ""
            dismiss()
        } else {
            err = msg
        }
    }
}
