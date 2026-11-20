import Foundation

// MARK: - 轨迹

struct Trace: Decodable, Identifiable {
    var time: String?
    var context: String?

    var id: String { (time ?? "") + "|" + (context ?? "") }

    enum CodingKeys: String, CodingKey {
        case time, context
    }
}

// MARK: - 状态

enum ShipStatus: String {
    case transit, signed, problem, pending, locker

    var label: String {
        switch self {
        case .transit: return "在途"
        case .signed: return "已签收"
        case .problem: return "异常"
        case .pending: return "待更新"
        case .locker: return "快递柜"
        }
    }
}

// MARK: - 运单

struct Shipment: Decodable, Identifiable {
    var id: Int
    var tracking_no: String
    var carrier: String?
    var carrier_name: String?
    var amount: Double?
    var item_detail: String?
    var phone_tail: String?
    var status: String?
    var status_code: String?
    var last_trace: String?
    var tracesRaw: String?
    var tracked_at: String?
    var note: String?
    var prev_no: String?
    var city: String?
    var sub_nos: String?
    var created_at: String
    var settled: Int?
    var settled_at: String?
    var settle_amount: Double?
    var deposit: Int?

    enum CodingKeys: String, CodingKey {
        case id, tracking_no, carrier, carrier_name, amount, item_detail
        case phone_tail, status, status_code, last_trace, traces, tracked_at
        case note, prev_no, city, sub_nos, created_at, settled, settled_at
        case settle_amount, deposit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        tracking_no = (try? c.decodeIfPresent(String.self, forKey: .tracking_no)) ?? ""
        carrier = try? c.decodeIfPresent(String.self, forKey: .carrier)
        carrier_name = try? c.decodeIfPresent(String.self, forKey: .carrier_name)
        amount = try? c.decodeIfPresent(Double.self, forKey: .amount)
        item_detail = try? c.decodeIfPresent(String.self, forKey: .item_detail)
        phone_tail = try? c.decodeIfPresent(String.self, forKey: .phone_tail)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        status_code = try? c.decodeIfPresent(String.self, forKey: .status_code)
        last_trace = try? c.decodeIfPresent(String.self, forKey: .last_trace)
        tracked_at = try? c.decodeIfPresent(String.self, forKey: .tracked_at)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        prev_no = try? c.decodeIfPresent(String.self, forKey: .prev_no)
        city = try? c.decodeIfPresent(String.self, forKey: .city)
        sub_nos = try? c.decodeIfPresent(String.self, forKey: .sub_nos)
        created_at = (try? c.decodeIfPresent(String.self, forKey: .created_at)) ?? ""
        settled = try? c.decodeIfPresent(Int.self, forKey: .settled)
        settled_at = try? c.decodeIfPresent(String.self, forKey: .settled_at)
        settle_amount = try? c.decodeIfPresent(Double.self, forKey: .settle_amount)
        deposit = try? c.decodeIfPresent(Int.self, forKey: .deposit)

        // traces 在库里是 TEXT（JSON 字符串），但个别版本会直接返回数组，两种都接住
        if let s = try? c.decodeIfPresent(String.self, forKey: .traces) {
            tracesRaw = s
        } else if let arr = try? c.decodeIfPresent([Trace].self, forKey: .traces) {
            if let d = try? JSONEncoder().encode(arr) {
                tracesRaw = String(data: d, encoding: .utf8)
            } else {
                tracesRaw = nil
            }
        } else {
            tracesRaw = nil
        }
    }
}

// MARK: - 业务规则（与网页版 statusOf / isLocker / isPartSettled 一一对应）

extension Shipment {
    static let pseudoPrefixes = ["自取", "上门回收", "上门", "自提", "送货上门", "送货", "当面交易", "当面"]

    var isPseudo: Bool {
        let no = tracking_no.trimmingCharacters(in: .whitespacesAndNewlines)
        return Shipment.pseudoPrefixes.contains { no.hasPrefix($0) }
    }

    var traces: [Trace] {
        guard let s = tracesRaw, let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Trace].self, from: d)) ?? []
    }

    var rawStatus: ShipStatus {
        ShipStatus(rawValue: status ?? "") ?? .pending
    }

    static let lockerKeywords = [
        "丰巢", "快递柜", "智能柜", "自提柜", "储物柜", "驿站", "代收点",
        "快递超市", "菜鸟", "兔喜", "近邻宝", "物业", "便利店", "小卖部", "门卫", "代收"
    ]

    /// 还没签收、但最新轨迹显示已放进快递柜/驿站
    var isLocker: Bool {
        let raw = rawStatus
        if isPseudo || raw == .signed || raw == .problem { return false }
        let head = traces.first?.context ?? ""
        let hay = head + " " + (last_trace ?? "")
        return Shipment.lockerKeywords.contains { hay.contains($0) }
    }

    /// 停滞天数：从最新一条轨迹时间算起，没有轨迹就用录入时间
    var stallDays: Int {
        if isPseudo { return 0 }
        var base = traces.first?.time ?? ""
        if base.isEmpty { base = created_at }
        guard let d = Fmt.date(base) else { return 0 }
        let days = Int(Date().timeIntervalSince(d) / 86400)
        return max(days, 0)
    }

    var statusKind: ShipStatus {
        var st = rawStatus
        if st == .pending && !traces.isEmpty { st = .transit }
        if (st == .transit || st == .pending) && !isLocker && stallDays >= 3 { st = .problem }
        return st
    }

    /// 部分结算：动过结算、标了寄存、但结回来的钱少于货值
    var isPartSettled: Bool {
        guard (settled ?? 0) != 0, (deposit ?? 0) != 0 else { return false }
        guard let sa = settle_amount else { return false }
        return sa < (amount ?? 0) - 0.005
    }

    var isOpenSettled: Bool { (settled ?? 0) == 0 || isPartSettled }

    /// 未结余额：没结过=全额；部分结算=差额
    var openAmount: Double {
        if (settled ?? 0) == 0 { return amount ?? 0 }
        return max((amount ?? 0) - (settle_amount ?? 0), 0)
    }

    /// 已结清的实收（部分结算的单不计利润，避免"结一半"变成假亏损）
    var profit: Double {
        guard isOpenSettled == false else { return 0 }
        return (settle_amount ?? 0) - (amount ?? 0)
    }

    var displayAmount: Double { amount ?? 0 }

    /// 上门单的客人名存在 carrier_name 里
    var guestName: String {
        guard isPseudo else { return "" }
        let n = (carrier_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return "" }
        if Shipment.pseudoPrefixes.contains(where: { n.hasPrefix($0) }) { return "" }
        return n
    }

    var carrierLabel: String {
        if isPseudo { return guestName.isEmpty ? "上门回收" : guestName }
        if let n = carrier_name, !n.isEmpty { return n }
        return Shipment.detectCarrier(tracking_no)
    }

    static func detectCarrier(_ no: String) -> String {
        let s = no.uppercased()
        if s.hasPrefix("SF") { return "顺丰速运" }
        if s.hasPrefix("JD") || s.hasPrefix("JDV") || s.hasPrefix("JDX") { return "京东物流" }
        if s.hasPrefix("DPK") || s.hasPrefix("DP") { return "德邦快递" }
        if s.hasPrefix("YT") { return "圆通速递" }
        if s.hasPrefix("STO") || s.hasPrefix("77") { return "申通快递" }
        if s.hasPrefix("YD") || s.hasPrefix("43") { return "韵达速递" }
        if s.hasPrefix("JT") { return "极兔速递" }
        if s.hasPrefix("ZTO") || s.hasPrefix("68") || s.hasPrefix("73") || s.hasPrefix("75") || s.hasPrefix("78") { return "中通快递" }
        if s.hasPrefix("EM") || s.hasPrefix("1") { return "邮政快递包裹" }
        return "快递"
    }

    /// 物品清单：和网页版 splitItems 同规则（逗号、顿号、斜杠、加号都当分隔）
    var items: [String] {
        guard let raw = item_detail else { return [] }
        var s = raw.replacingOccurrences(of: "\u{3000}", with: " ")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        let seps = CharacterSet(charactersIn: ",，、;；/|+＋")
        return s.components(separatedBy: seps)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var traceCount: Int { traces.count }
}

// MARK: - 用户

struct User: Decodable {
    var username: String?
    var is_admin: Bool?
    var price_perm: Bool?
    var has_api_key: Bool?

    enum CodingKeys: String, CodingKey {
        case username, is_admin, price_perm, has_api_key
    }

    // 后端布尔字段可能返回 true/false，也可能是 0/1 整数，两种都要接住，
    // 否则整个 User 解码失败会把登录直接断掉。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try? c.decodeIfPresent(String.self, forKey: .username)
        is_admin = User.flexBool(c, .is_admin)
        price_perm = User.flexBool(c, .price_perm)
        has_api_key = User.flexBool(c, .has_api_key)
    }

    private static func flexBool(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
        if let b = try? c.decode(Bool.self, forKey: key) { return b }
        if let i = try? c.decode(Int.self, forKey: key) { return i != 0 }
        return nil
    }
}

struct LoginResult: Decodable {
    var token: String
    var user: User?
    var key: String?
}

// MARK: - 回收查价

/// 解码兜底：后端 REAL 列偶尔会返回字符串或 null，直接 decode 会让整批数据解析失败
private func flexDouble<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Double? {
    if let v = try? c.decode(Double.self, forKey: k) { return v }
    if let v = try? c.decode(Int.self, forKey: k) { return Double(v) }
    if let s = try? c.decode(String.self, forKey: k) { return Double(s) }
    return nil
}

private func flexInt<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Int? {
    if let v = try? c.decode(Int.self, forKey: k) { return v }
    if let v = try? c.decode(Bool.self, forKey: k) { return v ? 1 : 0 }
    if let s = try? c.decode(String.self, forKey: k) { return Int(s) }
    return nil
}

struct PriceRow: Decodable, Identifiable {
    var shop: String
    var source: String
    var name: String
    var price: Double?
    var price2: Double?
    var hot: Int
    var updated_at: String?

    var id: String { shop + "|" + source + "|" + name }

    enum CodingKeys: String, CodingKey {
        case shop, source, name, price, price2, hot, updated_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shop = (try? c.decode(String.self, forKey: .shop)) ?? "吉尼"
        source = (try? c.decode(String.self, forKey: .source)) ?? "beauty"
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        price = flexDouble(c, .price)
        price2 = flexDouble(c, .price2)
        hot = flexInt(c, .hot) ?? 0
        updated_at = try? c.decode(String.self, forKey: .updated_at)
    }
}

struct PriceListResp: Decodable {
    var items: [PriceRow]
}

/// 历史价格的一个点：d=日期 p=主价 p2=代理价 hot=昨天出过货
struct PricePoint: Decodable, Identifiable {
    var d: String
    var p: Double?
    var p2: Double?
    var hot: Int

    var id: String { d + "|" + String(format: "%.2f", p ?? -1) }

    enum CodingKeys: String, CodingKey { case d, p, p2, hot }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        d = (try? c.decode(String.self, forKey: .d)) ?? ""
        p = flexDouble(c, .p)
        p2 = flexDouble(c, .p2)
        hot = flexInt(c, .hot) ?? 0
    }
}

struct PriceHistResp: Decodable {
    var name: String?
    var shop: String?
    var source: String?
    var points: [PricePoint]
}

struct MoverRow: Decodable, Identifiable {
    var shop: String
    var source: String
    var name: String
    var from: Double
    var to: Double
    var diff: Double
    var pct: Double
    var changes: Int

    var id: String { shop + "|" + source + "|" + name }

    enum CodingKeys: String, CodingKey {
        case shop, source, name, changes
        case fromValue = "from"
        case to, diff, pct
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shop = (try? c.decode(String.self, forKey: .shop)) ?? "吉尼"
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.from = flexDouble(c, .fromValue) ?? 0
        to = flexDouble(c, .to) ?? 0
        diff = flexDouble(c, .diff) ?? 0
        pct = flexDouble(c, .pct) ?? 0
        changes = flexInt(c, .changes) ?? 0
    }
}

struct MoverResp: Decodable {
    var days: Int?
    var items: [MoverRow]
    var changed: Int?
    var up: Int?
    var down: Int?
}

// MARK: - 照片

struct PhotoItem: Decodable, Identifiable {
    var id: String
    var row_id: Int?
    var tracking_no: String?
    var url: String?
    var mime: String?
    var size: Int?
    var created_at: String?

    enum CodingKeys: String, CodingKey {
        case id, row_id, tracking_no, url, mime, size, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        row_id = flexInt(c, .row_id)
        tracking_no = try? c.decode(String.self, forKey: .tracking_no)
        url = try? c.decode(String.self, forKey: .url)
        mime = try? c.decode(String.self, forKey: .mime)
        size = flexInt(c, .size)
        created_at = try? c.decode(String.self, forKey: .created_at)
    }
}

struct PhotoListResp: Decodable {
    var items: [PhotoItem]
}

struct MergeResult: Decodable {
    var merged: Int?
    var tracking_no: String?
}
