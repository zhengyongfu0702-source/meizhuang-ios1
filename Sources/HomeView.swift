import SwiftUI

struct HomeView: View {
    init() {}

    @EnvironmentObject var state: AppState

    @State private var folding = true
    @State private var sheet: HomeSheet?
    @State private var scanSeed = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(MZ.line).frame(height: 1)

            ScrollView {
                VStack(spacing: 10) {
                    quickBar
                    oneLineCard
                    foldBar

                    if state.filtered.isEmpty {
                        emptyCard
                    } else {
                        LazyVStack(spacing: MZ.gapCard) {
                            ForEach(state.filtered) { r in
                                ShipmentCardView(row: r)
                                    .onTapGesture { sheet = .detail(r) }
                            }
                        }
                    }

                    Color.clear.frame(height: 76)
                }
                .padding(.horizontal, MZ.pagePad)
                .padding(.top, 10)
            }
            .refreshable { await state.load() }
        }
        .background(MZ.bg)
        .overlay(alignment: .bottom) { bottomBar }
        .sheet(item: $sheet) { s in
            sheetView(s)
        }
    }

    // MARK: - 弹窗分发

    @ViewBuilder
    private func sheetView(_ s: HomeSheet) -> some View {
        switch s {
        case .compose:
            ComposeView(initialText: scanSeed)
                .environmentObject(state)
        case .scan:
            ScanView { code in
                scanSeed = code
                sheet = nil
                // 等扫码页关干净再开录入页，否则两个 sheet 会互相顶掉
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sheet = .compose
                }
            }
        case .price:
            PriceView()
        case .merge:
            MergeView()
                .environmentObject(state)
        case .detail(let r):
            ShipmentDetailView(row: r)
                .environmentObject(state)
        case .share(let url):
            ShareSheet(items: [url])
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("全品类回收统计")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(MZ.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Button {
                    Task { await state.traceAll() }
                } label: {
                    Text(state.tracing ? state.traceProgress : "一键查询轨迹")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MZ.text)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(MZ.soft2)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .disabled(state.tracing)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { folding.toggle() }
                } label: {
                    Text(folding ? "▼ 全部展开" : "▲ 收起")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MZ.text)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(MZ.soft2)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                Spacer(minLength: 4)

                Menu {
                    Button {
                        sheet = .price
                    } label: {
                        Label("回收查价", systemImage: "tag")
                    }
                    Button {
                        sheet = .merge
                    } label: {
                        Label("合并上门单", systemImage: "arrow.triangle.merge")
                    }
                    Button {
                        exportCSV()
                    } label: {
                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        state.logout()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 19))
                        .foregroundColor(MZ.text)
                }
            }

            HStack(spacing: 2) {
                Text("7天未结算 \(state.due7Count) 单")
                Text("·").padding(.horizontal, 3)
                Text("今日共 \(state.todayCount) 单/快递\(state.todayExpressCount)单/上门\(state.todaySelfCount)单")
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundColor(MZ.muted)
        }
        .padding(.horizontal, MZ.pagePad)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(MZ.card)
    }

    // MARK: - 扫码 + 搜索

    private var quickBar: some View {
        HStack(spacing: 8) {
            Button {
                scanSeed = ""
                sheet = .scan
            } label: {
                Text("扫码录入")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(MZ.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(MZ.muted)
                TextField("搜索单号 / 物品 / 快递 / 金额 / 备注", text: $state.keyword)
                    .font(.system(size: 14))
                    .submitLabel(.search)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(MZ.card)
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(MZ.line, lineWidth: 1)
            )
        }
    }

    // MARK: - 一句话录入入口

    private var oneLineCard: some View {
        Button {
            scanSeed = ""
            sheet = .compose
        } label: {
            MZCard(padding: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15))
                        .foregroundColor(MZ.brand)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("点这里，一句话录入")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(MZ.text)
                        Text("单号 物品 金额  |  上门 客人名 物品 金额")
                            .font(.system(size: 11))
                            .foregroundColor(MZ.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MZ.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 在途 / 异常 折叠条

    private var foldBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { folding.toggle() }
        } label: {
            HStack(spacing: 4) {
                Spacer()
                Text("在途 \(state.transitCount) 单")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MZ.text)
                Text("·")
                    .font(.system(size: 13))
                    .foregroundColor(MZ.muted)
                Text("异常 \(state.problemCount) 单")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(state.problemCount > 0 ? MZ.bad : MZ.text)
                Image(systemName: folding ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MZ.muted)
                    .padding(.leading, 2)
                Spacer()
            }
            .padding(.vertical, 11)
            .background(MZ.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MZ.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 空态 / 底部

    private var emptyCard: some View {
        VStack(spacing: 6) {
            if state.loading {
                ProgressView()
            }
            Text(state.hint.isEmpty ? (state.rows.isEmpty ? "还没有记录" : "没有匹配的记录") : state.hint)
                .font(.system(size: 13))
                .foregroundColor(MZ.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(MZ.card)
        .clipShape(RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous))
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                scanSeed = ""
                sheet = .compose
            } label: {
                Text("记录")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(MZ.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .background(
            MZ.bg.opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - 导出

    private func exportCSV() {
        let rows = state.filtered.isEmpty ? state.rows : state.filtered
        if rows.isEmpty {
            state.flash("没有可导出的记录")
            return
        }
        let csv = Exporter.csv(rows)
        let name = "运单导出_\(Fmt.todayKey()).csv"
        do {
            let url = try Exporter.writeTempFile(csv, name: name)
            sheet = .share(url)
        } catch {
            state.flash("导出失败：\(error.localizedDescription)")
        }
    }
}

enum HomeSheet: Identifiable {
    case compose
    case scan
    case price
    case merge
    case detail(Shipment)
    case share(URL)

    var id: String {
        switch self {
        case .compose: return "compose"
        case .scan: return "scan"
        case .price: return "price"
        case .merge: return "merge"
        case .detail(let r): return "detail-\(r.id)"
        case .share(let u): return "share-\(u.lastPathComponent)"
        }
    }
}
