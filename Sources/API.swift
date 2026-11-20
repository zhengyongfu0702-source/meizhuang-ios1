import Foundation
import Security

enum APIError: LocalizedError {
    case network
    case unauthorized
    case http(Int, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .network: return "网络连接失败，请检查网络"
        case .unauthorized: return "登录已过期，请重新登录"
        case .http(let code, let msg):
            return msg.isEmpty ? "请求失败（HTTP \(code)）" : msg
        case .decode(let m): return "数据解析失败：\(m)"
        }
    }
}

/// 极简 Keychain 封装：会话 token 和设备密钥都放这里，比 UserDefaults 安全
enum Keychain {
    private static let service = "top.jn736918.meizhuang"

    // TrollStore 用伪签名安装，没有正式的 keychain-access-groups entitlements，
    // SecItemAdd 可能返回 -34018。所以这里双写：Keychain 成功就用它，失败也能从
    // UserDefaults 读回来，避免"装完打不开、一直要求登录"。
    private static func defaultsKey(_ key: String) -> String { "kc_" + key }

    static func set(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey(key))
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data,
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return UserDefaults.standard.string(forKey: defaultsKey(key))
    }

    static func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(key))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 和网页版 api() 同一套语义：主线路优先，网络层失败才切备用，一次会话只降级一次
final class API {
    static let shared = API()

    static let primary = "https://736918.top"
    static let backup = "http://8.134.91.157"

    private let fallbackKey = "ep_fallback"
    private(set) var onFallback: Bool

    private init() {
        onFallback = UserDefaults.standard.bool(forKey: "ep_fallback")
    }

    var base: String { onFallback ? API.backup : API.primary }
    var usingBackup: Bool { onFallback }

    func useBackup() {
        onFallback = true
        UserDefaults.standard.set(true, forKey: fallbackKey)
    }

    func usePrimary() {
        onFallback = false
        UserDefaults.standard.set(false, forKey: fallbackKey)
    }

    private var token: String? { Keychain.get("token") }

    func raw(_ method: String, _ path: String, body: Data? = nil, retried: Bool = false) async throws -> Data {
        guard let url = URL(string: base + path) else { throw APIError.network }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        if let b = body {
            req.httpBody = b
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.network }
            if http.statusCode == 401 { throw APIError.unauthorized }
            if !(200..<300).contains(http.statusCode) {
                var msg = ""
                if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    msg = (obj["message"] as? String) ?? ""
                }
                throw APIError.http(http.statusCode, msg)
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            if !retried && !onFallback {
                useBackup()
                return try await raw(method, path, body: body, retried: true)
            }
            throw APIError.network
        }
    }

    func json<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        var payload: Data?
        if let body = body {
            payload = try JSONSerialization.data(withJSONObject: body)
        }
        let data = try await raw(method, path, body: payload)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(String(describing: error))
        }
    }

    // MARK: - 业务接口

    func login(username: String, password: String) async throws -> LoginResult {
        try await json("POST", "/api/login", body: ["username": username, "password": password])
    }

    func loginByKey(_ k: String) async throws -> LoginResult {
        try await json("POST", "/api/login_by_key", body: ["k": k])
    }

    func me() async throws -> User {
        try await json("GET", "/api/me")
    }

    /// 首屏列表：纯按时间倒序取最近 limit 条（和网页版 load() 同口径）
    func shipmentsData(limit: Int = 100) async throws -> Data {
        let q = "?select=*&order=created_at.desc&limit=\(limit)"
        return try await raw("GET", "/.cloud/database/rest/shipments" + q)
    }

    func shipments(limit: Int = 100) async throws -> [Shipment] {
        let data = try await shipmentsData(limit: limit)
        return try JSONDecoder().decode([Shipment].self, from: data)
    }

    func build() async -> String {
        struct Build: Decodable { let build: String? }
        guard let b: Build = try? await json("GET", "/api/build") else { return "" }
        return b.build ?? ""
    }

    // MARK: - 运单写操作（对应网页版 cloud.database.from('shipments') 那一套）

    func insertShipment(_ payload: [String: Any]) async throws -> Shipment {
        let list: [Shipment] = try await json("POST", "/.cloud/database/rest/shipments", body: payload)
        guard let first = list.first else { throw APIError.decode("保存未生效") }
        return first
    }

    func updateShipment(id: Int, patch: [String: Any]) async throws -> Shipment {
        let list: [Shipment] = try await json("PATCH", "/.cloud/database/rest/shipments?id=eq.\(id)", body: patch)
        guard let first = list.first else { throw APIError.decode("更新未生效") }
        return first
    }

    func deleteShipment(id: Int) async throws {
        _ = try await raw("DELETE", "/.cloud/database/rest/shipments?id=eq.\(id)")
    }

    func mergePseudo(ids: [Int], trackingNo: String, carrierName: String) async throws -> MergeResult {
        try await json("POST", "/api/merge_pseudo", body: [
            "ids": ids,
            "tracking_no": trackingNo,
            "carrier_name": carrierName
        ])
    }

    // MARK: - 回收查价

    func searchPrices(_ q: String) async throws -> [PriceRow] {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let r: PriceListResp = try await json("GET", "/api/prices?q=" + enc)
        return r.items
    }

    func allPrices() async throws -> [PriceRow] {
        let r: PriceListResp = try await json("GET", "/api/prices/all")
        return r.items
    }

    func priceHistory(name: String, shop: String, source: String, days: Int = 365) async throws -> PriceHistResp {
        var path = "/api/prices/history?days=\(days)&name="
        path += name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if !shop.isEmpty { path += "&shop=" + (shop.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") }
        if !source.isEmpty { path += "&source=" + source }
        return try await json("GET", path)
    }

    func priceMovers(days: Int = 7) async throws -> MoverResp {
        try await json("GET", "/api/prices/movers?days=\(days)")
    }

    // MARK: - 照片

    func photoList(trackingNo: String) async throws -> [PhotoItem] {
        var path = "/api/photo/list?limit=200"
        if !trackingNo.isEmpty {
            path += "&tracking_no=" + (trackingNo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        }
        let r: PhotoListResp = try await json("GET", path)
        return r.items
    }

    func uploadPhoto(base64: String, fileName: String, mime: String,
                     rowId: Int?, trackingNo: String) async throws -> PhotoItem {
        var body: [String: Any] = [
            "data": base64,
            "file_name": fileName,
            "mime": mime,
            "shot_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let r = rowId { body["row_id"] = r }
        if !trackingNo.isEmpty { body["tracking_no"] = trackingNo }
        return try await json("POST", "/api/photo/upload", body: body)
    }

    /// 图片接口要带 Bearer，AsyncImage 拿不到，只能自己取 Data
    func photoData(id: String) async throws -> Data {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try await raw("GET", "/api/photo/get?id=" + enc)
    }

    // MARK: - 轨迹查询（走服务器代理阿里云，AppCode 不出服务器）

    func queryExpress(no: String, carrier: String, tail: String) async throws -> ExpressInfo {
        try await json("POST", "/api/express/query", body: [
            "provider": "ali",
            "tracking_no": no,
            "carrier": carrier,
            "phone_tail": tail
        ])
    }
}

struct ExpressInfo: Decodable {
    var traces: [Trace]?
    var status: String?
    var carrier_name: String?
    var last_trace: String?
}
