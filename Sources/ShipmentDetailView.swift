import SwiftUI
import PhotosUI
import UIKit

/// 运单详情：轨迹、结算/寄存、照片、删除。
/// 结算三态口径与网页版一致：settled 只代表「动过结算」，标了寄存且结回的钱少于货值算「部分结算」。
struct ShipmentDetailView: View {
    let row: Shipment

    init(row: Shipment) {
        self.row = row
    }

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var busy = false
    @State private var err = ""
    @State private var confirmDelete = false

    private var live: Shipment {
        state.rows.first(where: { $0.id == row.id }) ?? row
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    headCard
                    settleCard
                    itemsCard
                    PhotoStrip(row: live)
                    traceCard
                    if !err.isEmpty {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(MZ.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    deleteButton
                    Color.clear.frame(height: 8)
                }
                .padding(14)
            }
            .background(MZ.bg)
            .navigationTitle("运单详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                amountText = live.settle_amount.map { trimZero($0) } ?? ""
            }
            .alert("确认删除？", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) {
                    Task {
                        let m = await state.removeRow(live)
                        if m.isEmpty { dismiss() } else { err = m }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("运单 \(live.tracking_no) 将被永久删除，不可恢复。")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 头部

    private var headCard: some View {
        MZCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(live.tracking_no)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundColor(MZ.text)
                    StatusBadge(kind: live.statusKind, locker: live.isLocker)
                    Spacer()
                    Text(Fmt.money(live.displayAmount))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(MZ.text)
                }
                HStack(spacing: 6) {
                    Text(live.carrierLabel)
                    Text("·")
                    Text(Fmt.shortDay(live.created_at))
                    if !(live.phone_tail ?? "").isEmpty {
                        Text("·")
                        Text("尾号 \(live.phone_tail ?? "")")
                    }
                    Spacer()
                    if live.traceCount > 0 {
                        Text("轨迹 \(live.traceCount) 条")
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(MZ.muted)

                if !(live.note ?? "").isEmpty {
                    Text(live.note ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(MZ.muted)
                }
            }
        }
    }

    // MARK: - 结算

    private var settleCard: some View {
        MZCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("结算")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MZ.text)
                    Spacer()
                    Text(settleLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(settleColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(settleColor.opacity(0.1))
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    TextField("结算金额", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15))
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .background(MZ.soft2)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Button {
                        Task {
                            busy = true
                            let m = await state.saveSettle(live, raw: amountText)
                            busy = false
                            if !m.isEmpty { err = m }
                        }
                    } label: {
                        Text("保存")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 40)
                            .background(MZ.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .disabled(busy)
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            let m = await state.toggleSettled(live)
                            if !m.isEmpty { err = m }
                            amountText = (state.rows.first(where: { $0.id == row.id })?.settle_amount)
                                .map { trimZero($0) } ?? ""
                        }
                    } label: {
                        Text((live.settled ?? 0) == 0 ? "标记已结算" : "取消结算")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor((live.settled ?? 0) == 0 ? MZ.ok : MZ.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background((live.settled ?? 0) == 0 ? MZ.okSoft : MZ.soft2)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }

                    Button {
                        Task {
                            let m = await state.toggleDeposit(live)
                            if !m.isEmpty { err = m }
                        }
                    } label: {
                        Text((live.deposit ?? 0) == 0 ? "标记寄存" : "取消寄存")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor((live.deposit ?? 0) == 0 ? MZ.warn : MZ.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background((live.deposit ?? 0) == 0 ? MZ.warnSoft : MZ.soft2)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }

                // 金额口径：未结余额 / 已结 / 利润，和网页版三张卡同一套规则
                HStack(spacing: 10) {
                    miniStat("未结余额", Fmt.money(live.openAmount), live.openAmount > 0 ? MZ.warn : MZ.muted)
                    miniStat("已结", Fmt.money(live.settle_amount ?? 0), MZ.muted)
                    miniStat("利润", Fmt.money(live.profit),
                             live.profit > 0 ? MZ.ok : (live.profit < 0 ? MZ.bad : MZ.muted))
                }
            }
        }
    }

    private var settleLabel: String {
        if live.isPartSettled { return "部分结算" }
        if (live.deposit ?? 0) != 0 && (live.settled ?? 0) == 0 { return "寄存中" }
        return (live.settled ?? 0) == 0 ? "未结算" : "已结清"
    }

    private var settleColor: Color {
        if live.isPartSettled { return MZ.warn }
        if (live.settled ?? 0) == 0 { return (live.deposit ?? 0) != 0 ? MZ.warn : MZ.wait }
        return MZ.ok
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(MZ.muted)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 物品

    private var itemsCard: some View {
        MZCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("物品")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MZ.text)
                if live.items.isEmpty {
                    Text("（没填物品明细）")
                        .font(.system(size: 13))
                        .foregroundColor(MZ.muted)
                } else {
                    ForEach(Array(live.items.enumerated()), id: \.offset) { _, it in
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(MZ.brand.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 6)
                            Text(it)
                                .font(.system(size: 13))
                                .foregroundColor(MZ.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 轨迹

    private var traceCard: some View {
        MZCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("物流轨迹（\(live.traceCount) 条）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MZ.text)
                if live.traces.isEmpty {
                    Text("暂无轨迹。录完单后可在首页点「一键查询轨迹」联网更新。")
                        .font(.system(size: 12))
                        .foregroundColor(MZ.muted)
                } else {
                    ForEach(Array(live.traces.enumerated()), id: \.offset) { i, t in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(i == 0 ? MZ.brand : MZ.line)
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.context ?? "")
                                    .font(.system(size: 13))
                                    .foregroundColor(i == 0 ? MZ.text : MZ.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(Fmt.fullTime(t.time))
                                    .font(.system(size: 11))
                                    .foregroundColor(MZ.muted)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button {
            confirmDelete = true
        } label: {
            Text("删除这一单")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MZ.bad)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(MZ.badSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func trimZero(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 { return String(Int(v.rounded())) }
        return String(format: "%.2f", v)
    }
}

// MARK: - 状态徽章

struct StatusBadge: View {
    let kind: ShipStatus
    let locker: Bool

    var body: some View {
        let k: ShipStatus = locker ? .locker : kind
        Text(k.label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(fg(k))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(bg(k))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func fg(_ k: ShipStatus) -> Color {
        switch k {
        case .transit: return MZ.brand
        case .signed: return MZ.ok
        case .problem: return MZ.bad
        case .locker: return MZ.warn
        case .pending: return MZ.wait
        }
    }

    private func bg(_ k: ShipStatus) -> Color {
        switch k {
        case .transit: return MZ.brandSoft
        case .signed: return MZ.okSoft
        case .problem: return MZ.badSoft
        case .locker: return MZ.warnSoft
        case .pending: return MZ.waitSoft
        }
    }
}

// MARK: - 照片

struct PhotoStrip: View {
    let row: Shipment

    @State private var items: [PhotoItem] = []
    @State private var pick: PhotosPickerItem?
    @State private var uploading = false
    @State private var err = ""
    @State private var loaded = false

    var body: some View {
        MZCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("照片（\(items.count)）")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MZ.text)
                    Spacer()
                    PhotosPicker(selection: $pick, matching: .images) {
                        HStack(spacing: 4) {
                            if uploading {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13))
                            }
                            Text(uploading ? "上传中" : "加照片")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(MZ.brand)
                    }
                }

                if items.isEmpty {
                    Text("还没有照片。拍到货照片可以存档，别人也能在旁边核对。")
                        .font(.system(size: 12))
                        .foregroundColor(MZ.muted)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(items) { p in
                                PhotoThumb(id: p.id)
                            }
                        }
                    }
                }

                if !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(MZ.bad)
                }
            }
        }
        .task {
            if !loaded {
                loaded = true
                await reload()
            }
        }
        .onChange(of: pick) { item in
            guard let item = item else { return }
            Task { await upload(item) }
        }
    }

    private func reload() async {
        if let list = try? await API.shared.photoList(trackingNo: row.tracking_no) {
            items = list
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        err = ""
        defer { uploading = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else {
            err = "读不到这张图片"
            return
        }
        let small = img.mz_resized(maxSide: 1600)
        guard let jpg = small.jpegData(compressionQuality: 0.72) else {
            err = "图片转码失败"
            return
        }
        // 后端单张上限 8MB，留点余量
        if jpg.count > 7 * 1024 * 1024 {
            err = "图片太大，换一张（建议 4MB 以内）"
            return
        }
        do {
            _ = try await API.shared.uploadPhoto(
                base64: jpg.base64EncodedString(),
                fileName: "shot.jpg",
                mime: "image/jpeg",
                rowId: row.id,
                trackingNo: row.tracking_no
            )
            await reload()
        } catch {
            err = error.localizedDescription
        }
    }
}

struct PhotoThumb: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(MZ.soft2)
                    .overlay(ProgressView().scaleEffect(0.7))
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task {
            if image == nil, let d = try? await API.shared.photoData(id: id) {
                image = UIImage(data: d)
            }
        }
    }
}

extension UIImage {
    /// 等比缩到最长边不超过 maxSide，避免 iPhone 原图把 8MB 上限顶穿
    func mz_resized(maxSide: CGFloat) -> UIImage {
        let w = size.width, h = size.height
        let m = max(w, h)
        if m <= maxSide { return self }
        let scale = maxSide / m
        let target = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
