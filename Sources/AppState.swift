import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var user: User?
    @Published var rows: [Shipment] = []
    @Published var booting = true
    @Published var loading = false
    @Published var hint: String = ""
    @Published var banner: String = ""
    @Published var keyword: String = ""
    @Published var showingLogin = false

    private let cacheKey = "cache_rows"
    private let lastUserKey = "last_user"

    var isLoggedIn: Bool { user != nil }

    var filtered: [Shipment] {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !k.isEmpty else { return rows }
        return rows.filter { r in
            r.tracking_no.lowercased().contains(k)
            || (r.item_detail ?? "").lowercased().contains(k)
            || (r.carrierLabel).lowercased().contains(k)
            || (r.last_trace ?? "").lowercased().contains(k)
            || (r.note ?? "").lowercased().contains(k)
        }
    }

    // MARK: - 统计（和网页版三张卡/顶栏同口径）

    var transitCount: Int { rows.filter { $0.statusKind == .transit }.count }
    var problemCount: Int { rows.filter { $0.statusKind == .problem }.count }
    var todayCount: Int { rows.filter { $0.created_at.hasPrefix(Fmt.todayKey()) }.count }
    var todaySelfCount: Int { rows.filter { $0.created_at.hasPrefix(Fmt.todayKey()) && $0.isPseudo }.count }
    var todayExpressCount: Int { todayCount - todaySelfCount }

    /// 7 天未结算：已签收满 7 天还没结算 + 标了寄存的单
    var due7Count: Int {
        rows.filter { r in
            if (r.deposit ?? 0) != 0 { return true }
            guard (r.settled ?? 0) == 0 else { return false }
            guard r.statusKind == .signed else { return false }
            guard let d = Fmt.date(r.settled_at ?? r.tracked_at ?? r.created_at) else { return false }
            return Date().timeIntervalSince(d) >= 7 * 86400
        }.count
    }

    var totalAmount: Double { rows.reduce(0) { $0 + $1.displayAmount } }

    // MARK: - 启动

    private var booted = false

    func bootstrap() async {
        if booted { return }
        booted = true

        loadCache()

        let key = Keychain.get("login_key") ?? ""
        let lastUser = UserDefaults.standard.string(forKey: lastUserKey) ?? ""
        let hasToken = Keychain.get("token") != nil

        // 没有任何凭据：直接进登录页，不要先闪一下空白首页
        if key.isEmpty && !hasToken {
            booting = false
            showingLogin = true
            return
        }

        // 有凭据：先把本机缓存铺出来，再后台验证
        booting = false

        if !key.isEmpty, !lastUser.isEmpty {
            do {
                let r = try await API.shared.loginByKey(key)
                Keychain.set(r.token, for: "token")
                user = r.user
                showingLogin = false
                await load()
                return
            } catch {
                // 密钥失效就退回登录页；网络问题也退回，但缓存里的数据还能看
            }
        }

        if Keychain.get("token") != nil {
            do {
                let u = try await API.shared.me()
                user = u
                showingLogin = false
                await load()
                return
            } catch {
                Keychain.remove("token")
            }
        }

        showingLogin = true
    }

    func login(username: String, password: String, remember: Bool) async throws {
        let r = try await API.shared.login(username: username, password: password)
        Keychain.set(r.token, for: "token")
        user = r.user
        UserDefaults.standard.set(username, forKey: lastUserKey)
        if remember {
            // 登录后再换一把长期设备密钥，下次打开免密
            await makeDeviceKey()
        }
        showingLogin = false
        await load()
    }

    private func makeDeviceKey() async {
        struct KeyResp: Decodable { let key: String?; let username: String? }
        guard let r: KeyResp = try? await API.shared.json("POST", "/api/login_key", body: ["label": "native"]) else { return }
        if let k = r.key, !k.isEmpty {
            Keychain.set(k, for: "login_key")
        }
    }

    func logout() {
        Keychain.remove("token")
        Keychain.remove("login_key")
        UserDefaults.standard.removeObject(forKey: lastUserKey)
        user = nil
        rows = []
        showingLogin = true
    }

    // MARK: - 提示

    @Published var toast: String = ""

    /// 轻提示：3 秒自动消失（网页版 toast 同款行为）
    func flash(_ s: String) {
        if s.isEmpty { return }
        toast = s
        let cur = s
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toast == cur { toast = "" }
        }
    }

    // MARK: - 一句话录入 / 变更单号

    /// 返回空串表示成功（成功后的提示已经由 flash 处理），否则是要给用户看的错误
    func submitQuick(_ text: String) async -> String {
        let existing = Set(rows.map { QuickParser.normNo($0.tracking_no) })

        // 「变更单号」优先：一次改掉原记录，而不是新增一单
        if let chg = QuickParser.parseChange(text, existing: existing) {
            if let err = chg.error { return err }
            return await changeNo(chg.oldNo, chg.newNo)
        }

        guard let p = QuickParser.parse(text), !p.no.isEmpty else {
            return "没识别出运单号，请检查单号是否完整"
        }

        var no = p.no
        if QuickParser.isPseudo(no) { no = nextPseudoNo() }

        if let dup = rows.first(where: { QuickParser.normNo($0.tracking_no) == QuickParser.normNo(no) }) {
            return "运单 \(dup.tracking_no) 已经录入过了（\(Fmt.money(dup.amount))）"
        }

        let pseudo = QuickParser.isPseudo(no)
        let c = QuickParser.carrier(no)
        var payload: [String: Any] = [
            "tracking_no": no,
            "amount": p.amount,
            "carrier_name": pseudo ? (p.guest.isEmpty ? QuickParser.pseudoLabel : p.guest) : c.name
        ]
        if !pseudo && !c.kd.isEmpty { payload["carrier"] = c.kd }
        if !p.item.isEmpty { payload["item_detail"] = p.item }
        if !p.subs.isEmpty { payload["sub_nos"] = p.subs.joined(separator: ",") }

        do {
            _ = try await API.shared.insertShipment(payload)
            await load()
            if pseudo {
                flash("已记录 上门回收\(p.guest.isEmpty ? "" : " · " + p.guest) \(Fmt.money(p.amount))")
            } else {
                flash("已记录 \(c.name) \(no) \(Fmt.money(p.amount))")
            }
            return ""
        } catch {
            let m = error.localizedDescription
            if m.contains("已存在") || m.contains("23505") { return "该运单号已存在，不能重复录入" }
            return m
        }
    }

    /// 上门单重号处理：已有「上门回收」就依次加 2、3…，否则被单号唯一约束挡住
    private func nextPseudoNo() -> String {
        let set = Set(rows.map { QuickParser.normNo($0.tracking_no) })
        var cand = QuickParser.pseudoLabel
        var i = 1
        while set.contains(QuickParser.normNo(cand)) {
            i += 1
            cand = QuickParser.pseudoLabel + String(i)
        }
        return cand
    }

    private func changeNo(_ oldNo: String, _ newNo: String) async -> String {
        guard let old = rows.first(where: { QuickParser.normNo($0.tracking_no) == QuickParser.normNo(oldNo) }) else {
            return "没找到运单 \(oldNo)，请先录入或核对单号"
        }
        if QuickParser.normNo(oldNo) == QuickParser.normNo(newNo) { return "新旧单号一样，不用变更" }
        if rows.contains(where: { $0.id != old.id && QuickParser.normNo($0.tracking_no) == QuickParser.normNo(newNo) }) {
            return "新单号 \(newNo) 已经被占用了"
        }

        // 旧单号累积进「原单号」，多次换单也不丢历史
        var prev = (old.prev_no ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",，、;； "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !prev.contains(where: { QuickParser.normNo($0) == QuickParser.normNo(old.tracking_no) }) {
            prev.append(old.tracking_no)
        }

        let c = QuickParser.carrier(newNo)
        var patch: [String: Any] = [
            "tracking_no": newNo,
            "status": "pending",
            "status_code": "",
            "last_trace": "",
            "traces": [String](),       // 换了单号，旧轨迹全部作废
            "tracked_at": NSNull(),
            "prev_no": prev.joined(separator: ","),
            "carrier_name": c.name
        ]
        if !c.kd.isEmpty { patch["carrier"] = c.kd }

        do {
            _ = try await API.shared.updateShipment(id: old.id, patch: patch)
            await load()
            flash("已变更：\(oldNo) → \(newNo)")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - 结算 / 寄存 / 删除

    func saveSettle(_ row: Shipment, raw: String) async -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var v: Double? = nil
        if !t.isEmpty {
            guard let d = Double(t), d >= 0 else { return "结算金额需为不小于 0 的数字" }
            v = d
        }

        var patch: [String: Any] = [:]
        patch["settle_amount"] = v.map { $0 as Any } ?? NSNull()

        // 填了结算金额就说明钱已经结了 → 自动标记已结算
        if v != nil && (row.settled ?? 0) == 0 {
            patch["settled"] = 1
            patch["settled_at"] = ISO8601DateFormatter().string(from: Date())
        }
        // 填了结算金额就当货已到手：柜/驿站件转已签收（异常件、上门单不动）
        if v != nil && !row.isPseudo {
            let st = row.statusKind
            if st != .signed && st != .problem {
                patch["status"] = "signed"
                patch["status_code"] = "MANUAL"
            }
        }

        do {
            _ = try await API.shared.updateShipment(id: row.id, patch: patch)
            await load()
            if let updated = rows.first(where: { $0.id == row.id }), updated.isPartSettled {
                flash("只结了一部分：已结 \(Fmt.money(updated.settle_amount))，还差 \(Fmt.money(updated.openAmount)) 没结")
            } else if let d = v {
                flash("结算金额已保存 \(Fmt.money(d))")
            } else {
                flash("已清空结算金额（按运单金额计）")
            }
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    func toggleSettled(_ row: Shipment) async -> String {
        let next = (row.settled ?? 0) == 0
        var patch: [String: Any] = ["settled": next ? 1 : 0]
        patch["settled_at"] = next ? ISO8601DateFormatter().string(from: Date()) : NSNull()
        if !next { patch["settle_amount"] = NSNull() }
        if next && row.settle_amount == nil { patch["settle_amount"] = row.amount ?? 0 }

        do {
            _ = try await API.shared.updateShipment(id: row.id, patch: patch)
            await load()
            flash(next ? "已标记为已结算" : "已取消结算标记")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    func toggleDeposit(_ row: Shipment) async -> String {
        let next = (row.deposit ?? 0) == 0
        do {
            _ = try await API.shared.updateShipment(id: row.id, patch: ["deposit": next ? 1 : 0])
            await load()
            flash(next ? "已标记寄存（仍未结清）" : "已取消寄存标记")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    func removeRow(_ row: Shipment) async -> String {
        do {
            try await API.shared.deleteShipment(id: row.id)
            rows.removeAll { $0.id == row.id }
            await load()
            flash("已删除")
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - 批量查轨迹

    @Published var tracing = false
    @Published var traceProgress = ""

    /// 一键查询：只查「没签收、不是上门单」的那些，串行提交（免费接口有 QPS 限制）。
    /// 查询结果由本机 PATCH 回运单，和网页版 refreshOne 的做法一致。
    func traceAll() async {
        if tracing { return }
        let todo = rows.filter { !$0.isPseudo && $0.statusKind != .signed }
        if todo.isEmpty {
            flash("没有需要查询的单（都已签收或是上门单）")
            return
        }
        tracing = true
        var ok = 0
        var fail = 0
        for (i, r) in todo.enumerated() {
            if Task.isCancelled { break }
            traceProgress = "查询轨迹 \(i + 1)/\(todo.count)"
            do {
                let info = try await API.shared.queryExpress(
                    no: r.tracking_no,
                    carrier: r.carrier ?? "",
                    tail: r.phone_tail ?? ""
                )
                var patch: [String: Any] = ["tracked_at": ISO8601DateFormatter().string(from: Date())]
                if let s = info.status, !s.isEmpty { patch["status"] = s }
                if let lt = info.last_trace { patch["last_trace"] = lt }
                if let cn = info.carrier_name, !cn.isEmpty { patch["carrier_name"] = cn }
                if let tr = info.traces {
                    patch["traces"] = tr.map { ["time": $0.time ?? "", "context": $0.context ?? ""] }
                }
                _ = try await API.shared.updateShipment(id: r.id, patch: patch)
                ok += 1
            } catch {
                fail += 1
            }
            // 免费通道匿名限速，串行留间隔
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
        await load()
        tracing = false
        traceProgress = ""
        if fail == 0 {
            flash("轨迹已更新 \(ok) 单")
        } else {
            flash("更新 \(ok) 单，\(fail) 单失败（多为缺手机尾号或额度用尽）")
        }
    }

    // MARK: - 数据

    func load() async {
        guard user != nil else { return }
        loading = true
        hint = rows.isEmpty ? "正在加载记录…" : "本地缓存 · 正在更新…"
        do {
            let data = try await API.shared.shipmentsData(limit: 100)
            let list = try JSONDecoder().decode([Shipment].self, from: data)
            rows = list
            UserDefaults.standard.set(data, forKey: cacheKey)
            hint = ""
            banner = API.shared.usingBackup ? "正在使用备用线路（IP 直连）" : ""
        } catch {
            hint = rows.isEmpty ? "加载失败：\(error.localizedDescription)" : ""
        }
        loading = false
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let list = try? JSONDecoder().decode([Shipment].self, from: data) else { return }
        rows = list
    }
}
