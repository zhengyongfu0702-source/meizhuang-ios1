import SwiftUI

/// 回收查价：与网页版同一套数据（/api/prices），同一款商品按商家并排显示。
/// 涨跌配色按国内习惯：涨=红、跌=绿。
struct PriceView: View {
    init() {}

    @Environment(\.dismiss) private var dismiss

    @State private var q = ""
    @State private var rows: [PriceRow] = []
    @State private var movers: [MoverRow] = []
    @State private var loading = false
    @State private var err = ""
    @State private var mode = 0            // 0=查价 1=近 7 天变动
    @State private var histTarget: PriceRow?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                Picker("", selection: $mode) {
                    Text("查价").tag(0)
                    Text("近 7 天变动").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                if mode == 0 {
                    priceList
                } else {
                    moverList
                }
            }
            .background(MZ.bg)
            .navigationTitle("回收查价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $histTarget) { r in
                PriceHistView(row: r)
            }
            .onChange(of: mode) { m in
                if m == 1 && movers.isEmpty {
                    Task { await loadMovers() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(MZ.muted)
            TextField("搜品牌或型号，如：海蓝之谜 精粹水", text: $q)
                .font(.system(size: 14))
                .submitLabel(.search)
                .onChange(of: q) { v in
                    searchTask?.cancel()
                    let query = v.trimmingCharacters(in: .whitespacesAndNewlines)
                    if query.isEmpty {
                        rows = []
                        return
                    }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 280_000_000)
                        if Task.isCancelled { return }
                        await search(query)
                    }
                }
            if !q.isEmpty {
                Button {
                    q = ""
                    rows = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(MZ.muted)
                }
            }
            if loading { ProgressView().scaleEffect(0.7) }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(MZ.card)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(MZ.line, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - 查价列表

    private var priceList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(MZ.bad)
                        .padding(14)
                }
                if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyHint("输入品牌或型号开始查价。报价每 3 小时自动从金山文档同步一次。")
                } else if rows.isEmpty && !loading {
                    emptyHint("没有找到「\(q)」，换个关键词试试（只输品牌或容量更容易命中）。")
                } else {
                    ForEach(groups) { g in
                        groupRow(g)
                        Rectangle().fill(MZ.line).frame(height: 1)
                    }
                }
            }
            .background(MZ.card)
            .clipShape(RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous)
                    .stroke(MZ.line, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    private func groupRow(_ g: PriceGroup) -> some View {
        Button {
            if let first = g.items.first { histTarget = first }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MZ.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(g.items.first?.sourceLabel ?? "")
                        .font(.system(size: 10.5))
                        .foregroundColor(MZ.muted)
                }
                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(g.items) { it in
                        HStack(spacing: 5) {
                            Text(it.shop)
                                .font(.system(size: 10.5))
                                .foregroundColor(MZ.muted)
                            Text(it.priceText)
                                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                .foregroundColor(it.hot != 0 ? MZ.bad : MZ.text)
                            if it.hot != 0 {
                                Text("昨出货")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(MZ.bad)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(MZ.badSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            } else {
                                // 占位，保证多商家时价格右边界对齐
                                Color.clear.frame(width: 34, height: 1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var groups: [PriceGroup] {
        var map: [String: [PriceRow]] = [:]
        var order: [String] = []
        for r in rows {
            if map[r.name] == nil { order.append(r.name) }
            map[r.name, default: []].append(r)
        }
        return order.map { n in
            var list = map[n] ?? []
            list.sort { a, b in
                if a.shop == "吉尼" && b.shop != "吉尼" { return true }
                if b.shop == "吉尼" && a.shop != "吉尼" { return false }
                return a.shop < b.shop
            }
            return PriceGroup(name: n, items: list)
        }
    }

    // MARK: - 变动榜

    private var moverList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if movers.isEmpty {
                    emptyHint(loading ? "正在统计…" : "近 7 天没有价格变动记录。")
                } else {
                    ForEach(movers) { m in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(MZ.text)
                                    .lineLimit(2)
                                Text("\(m.shop) · \(sourceLabel(m.source)) · 变动 \(m.changes) 次")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(MZ.muted)
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(money(m.from)) → \(money(m.to))")
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .foregroundColor(MZ.text)
                                Text(m.diff == 0 ? "持平" : ((m.diff > 0 ? "+" : "") + String(format: "%.1f%%", m.pct)))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(m.diff > 0 ? MZ.bad : (m.diff < 0 ? MZ.ok : MZ.muted))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        Rectangle().fill(MZ.line).frame(height: 1)
                    }
                }
            }
            .background(MZ.card)
            .clipShape(RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous)
                    .stroke(MZ.line, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    private func emptyHint(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12.5))
            .foregroundColor(MZ.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
    }

    private func money(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 { return "¥" + String(Int(v.rounded())) }
        return String(format: "¥%.2f", v)
    }

    private func sourceLabel(_ s: String) -> String {
        switch s {
        case "phone": return "手机"
        case "beauty": return "美妆"
        case "health": return "港药保健"
        default: return s
        }
    }

    // MARK: - 网络

    private func search(_ query: String) async {
        loading = true
        err = ""
        do {
            let list = try await API.shared.searchPrices(query)
            if !Task.isCancelled { rows = list }
        } catch {
            if !Task.isCancelled { err = error.localizedDescription }
        }
        loading = false
    }

    private func loadMovers() async {
        loading = true
        if let r = try? await API.shared.priceMovers(days: 7) {
            movers = r.items
        }
        loading = false
    }
}

private struct PriceGroup: Identifiable {
    var name: String
    var items: [PriceRow]
    var id: String { name }
}

private extension PriceRow {
    var priceText: String {
        guard let p = price else { return "暂无" }
        if abs(p - p.rounded()) < 0.005 { return "¥" + String(Int(p.rounded())) }
        return String(format: "¥%.2f", p)
    }

    var sourceLabel: String {
        switch source {
        case "phone": return "手机"
        case "beauty": return "美妆"
        case "health": return "港药保健"
        default: return source
        }
    }
}

// MARK: - 历史调价

/// 逐次变价一条：只列「和上一次不同」的价格点，不做曲线。
struct PriceHistView: View {
    let row: PriceRow

    @Environment(\.dismiss) private var dismiss
    @State private var points: [PricePoint] = []
    @State private var loading = true
    @State private var err = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    MZCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(MZ.text)
                            HStack(spacing: 6) {
                                Text("\(row.shop) · \(row.sourceLabel)")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(MZ.muted)
                                Spacer()
                                Text(row.priceText)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(MZ.text)
                            }
                        }
                    }

                    MZCard(padding: 0) {
                        VStack(spacing: 0) {
                            if loading {
                                ProgressView().padding(30)
                            } else if points.isEmpty {
                                Text(err.isEmpty ? "暂无历史调价记录" : err)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(MZ.muted)
                                    .padding(30)
                            } else {
                                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                                    HStack(spacing: 10) {
                                        Text(p.d)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(MZ.muted)
                                            .frame(width: 92, alignment: .leading)
                                        Text(priceText(p.p))
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(p.hot != 0 ? MZ.bad : MZ.text)
                                        if p.hot != 0 {
                                            Text("出货")
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .foregroundColor(MZ.bad)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1.5)
                                                .background(MZ.badSoft)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        Spacer()
                                        if let p2 = p.p2 {
                                            Text("代理 " + priceText(p2))
                                                .font(.system(size: 11))
                                                .foregroundColor(MZ.muted)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    if i < points.count - 1 {
                                        Rectangle().fill(MZ.line).frame(height: 1).padding(.leading, 12)
                                    }
                                }
                            }
                        }
                    }

                    Text("「出货」是红字标价，表示这款昨天有出货；没标的是常规报价。")
                        .font(.system(size: 11))
                        .foregroundColor(MZ.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }
                .padding(14)
            }
            .background(MZ.bg)
            .navigationTitle("调价记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { load() }
        }
        .navigationViewStyle(.stack)
    }

    private func priceText(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        if abs(v - v.rounded()) < 0.005 { return "¥" + String(Int(v.rounded())) }
        return String(format: "¥%.2f", v)
    }

    private func load() {
        loading = true
        Task {
            do {
                let r = try await API.shared.priceHistory(name: row.name, shop: row.shop, source: row.source)
                // 逐次变价一条：和上一条价格相同就并掉（网页版 v248 同规则）
                var keep: [PricePoint] = []
                var last: Double? = nil
                for p in r.points {
                    if let lp = last, let cp = p.p, abs(lp - cp) < 0.001 { continue }
                    keep.append(p)
                    if let cp = p.p { last = cp }
                }
                points = Array(keep.reversed())
            } catch {
                err = error.localizedDescription
            }
            loading = false
        }
    }
}
