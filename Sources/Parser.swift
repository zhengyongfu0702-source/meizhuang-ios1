import Foundation

/// 一句话录入解析器：逐条移植网页版 parseLine / parseChangeNo / normPseudoNo 的规则。
/// 改动这里之前，先确认 index.html 里对应函数是不是也改了，否则两端录入结果会不一致。
struct ParsedEntry {
    var no: String = ""
    var amount: Double = 0
    var item: String = ""
    var guest: String = ""
    var subs: [String] = []
}

struct ChangeIntent {
    var oldNo: String
    var newNo: String
    var error: String?
}

enum QuickParser {
    static let pseudoLabel = "上门回收"

    /// 上门类抬头：命中任何一个都当成「上门回收」单，单号本身不是真实物流号
    static let pseudoPrefixes = ["自取", "上门回收", "上门", "自提", "送货上门", "送货", "当面交易", "当面"]

    static let changePattern = "变更|改单|换单|改运单|换运单|改号|转单|新单号|改成|换成|替换成"

    private static let carrierPattern =
        "中通|圆通|申通|顺丰|韵达|极兔|京东|邮政|EMS|ems|德邦|百世|宅急送|天天|优速|快递|速递|物流"

    // MARK: - 基础判断

    static func isPseudo(_ no: String) -> Bool {
        let s = no.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return false }
        return pseudoPrefixes.contains { s.hasPrefix($0) }
    }

    /// 单号规范化：去空格和连字符、转大写。重复判断、查重都走它
    static func normNo(_ s: String) -> String {
        s.replacingOccurrences(of: "[\\s\\-]", with: "", options: .regularExpression).uppercased()
    }

    /// 全角字符转半角（微信里复制出来的单号常带全角）
    static func halfWidth(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            if u.value >= 0xFF01 && u.value <= 0xFF5E {
                if let c = Unicode.Scalar(u.value - 0xFEE0) { out.unicodeScalars.append(c) }
            } else if u.value == 0x3000 {
                out.append(" ")
            } else {
                out.unicodeScalars.append(u)
            }
        }
        return out
    }

    // MARK: - 正则小工具

    private static func firstMatch(_ s: String, _ pattern: String, group: Int = 0) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard m.numberOfRanges > group else { return nil }
        let r = m.range(at: group)
        if r.location == NSNotFound || r.length == 0 { return nil }
        return ns.substring(with: r)
    }

    private static func allMatches(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        let ms = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        return ms.map { ns.substring(with: $0.range) }
    }

    // MARK: - 单号提取

    /// 从任意文本里抠出所有像单号的串（去重、规范化），用于「变更单号」判定
    static func noTokens(_ text: String) -> [String] {
        let s = halfWidth(text)
        let raw = allMatches(s, "[A-Za-z]{1,4}\\s?-?\\s?\\d{8,20}") + allMatches(s, "\\d{10,25}")
        var out: [String] = []
        var seen = Set<String>()
        for v in raw {
            let n = normNo(v)
            if n.isEmpty || seen.contains(n) { continue }
            seen.insert(n)
            out.append(n)
        }
        return out
    }

    /// 子母件写法：`主单号|子单1,子单2`
    static func splitSubLine(_ text: String) -> (main: String, subs: [String]) {
        let s = halfWidth(text)
        let parts = s.components(separatedBy: CharacterSet(charactersIn: "|｜"))
        if parts.count < 2 { return (text, []) }
        let main = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        var subs: [String] = []
        for p in parts.dropFirst() {
            for x in p.components(separatedBy: CharacterSet(charactersIn: ",，、;；/ ")) {
                let t = x.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { subs.append(t) }
            }
        }
        return (main.isEmpty ? text : main, subs)
    }

    // MARK: - 一句话解析

    static func parse(_ text: String) -> ParsedEntry? {
        let sp = splitSubLine(text)
        let mainText = sp.main

        // 上门单靠「第二段」取客人名，所以分段要在去掉标点之前做
        var segs = mainText.components(separatedBy: CharacterSet(charactersIn: ",，、；;|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if segs.count < 2 {
            segs = mainText.components(separatedBy: CharacterSet.whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        var s = halfWidth(mainText)
        s = s.replacingOccurrences(of: "[，,、；;|]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }

        // 单号：字母+数字 / 纯数字 10~25 位 / 上门类抬头
        var rawNo = firstMatch(s, "[A-Za-z]{1,4}\\s?-?\\s?\\d{8,20}")
        if rawNo == nil { rawNo = firstMatch(s, "\\b\\d{10,25}\\b") }
        if rawNo == nil { rawNo = firstMatch(s, "自取|上门回收|上门|自提|送货上门|送货|当面交易|当面") }
        let no = rawNo.map { $0.replacingOccurrences(of: "[\\s-]", with: "", options: .regularExpression) } ?? ""

        // 金额：先认带「元/块/￥」的，避免把规格里的数字当价格
        var amount: Double = 0
        var amtTxt = ""
        if let frag = firstMatch(s, "(?:[¥￥]\\s*)?\\d{1,7}(?:\\.\\d{1,2})?\\s*(?:元|块|RMB|rmb)") {
            amtTxt = frag
            if let n = firstMatch(frag, "\\d{1,7}(?:\\.\\d{1,2})?") { amount = Double(n) ?? 0 }
        } else if let frag = firstMatch(s, "[¥￥]\\s*\\d{1,7}(?:\\.\\d{1,2})?") {
            amtTxt = frag
            if let n = firstMatch(frag, "\\d{1,7}(?:\\.\\d{1,2})?") { amount = Double(n) ?? 0 }
        } else {
            // 没有货币标记：取最后一个「独立数字」当金额，且不能等于单号
            for tok in s.components(separatedBy: " ") {
                let t = tok.trimmingCharacters(in: CharacterSet(charactersIn: "()（）[]"))
                guard !t.isEmpty else { continue }
                let isNum = firstMatch(t, "^\\d{1,7}(?:\\.\\d{1,2})?$") != nil
                if isNum && t != no {
                    amount = Double(t) ?? 0
                    amtTxt = tok
                }
            }
        }

        // 物品：抹掉单号、金额、字段名和快递公司名，剩下的就是物品描述
        var item = s
        if let rn = rawNo { item = item.replacingOccurrences(of: rn, with: " ") }
        if !amtTxt.isEmpty { item = item.replacingOccurrences(of: amtTxt, with: " ") }
        item = item.replacingOccurrences(of: "(?:金额|价格|合计|单价|运单号|快递单号|单号)\\s*[:：]?",
                                         with: " ", options: .regularExpression)
        item = item.replacingOccurrences(of: "[¥￥]", with: " ", options: .regularExpression)
        item = item.replacingOccurrences(of: "(?:\(carrierPattern))", with: " ", options: .regularExpression)
        item = item.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        item = item.trimmingCharacters(in: CharacterSet(charactersIn: " -:：,，.。"))

        // 上门单：第二段是客人名
        var guest = ""
        if isPseudo(no), segs.count >= 2 {
            let cand = segs[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if isGuestName(cand) { guest = cand }
        }
        if !guest.isEmpty {
            if item.hasPrefix(guest) {
                item = String(item.dropFirst(guest.count)).trimmingCharacters(in: .whitespaces)
            } else {
                item = item.replacingOccurrences(of: guest, with: " ")
                item = item.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            }
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: " -:：,，.。"))
        }

        return ParsedEntry(no: no, amount: amount, item: item, guest: guest, subs: sp.subs)
    }

    /// 客人名合法性：不能太长、不能带数字/量词、不能本身是上门抬头
    private static func isGuestName(_ s: String) -> Bool {
        if s.isEmpty || s.count > 20 { return false }
        if isPseudo(s) { return false }
        if s.range(of: "\\d|ml|ML|kg|KG|瓶|盒|件|支|套|只|个|包|罐|袋|片|条|双|箱",
                   options: .regularExpression) != nil { return false }
        return true
    }

    // MARK: - 快递公司识别

    struct CarrierInfo {
        var name: String
        var kd: String
    }

    /// 与网页版 CARRIERS 表一致；kd 是后端查询轨迹时用的代码，不能省
    static func carrier(_ no: String) -> CarrierInfo {
        let n = no.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return CarrierInfo(name: "未识别", kd: "") }
        let table: [(String, String, String)] = [
            ("顺丰速运", "shunfeng", "^SF[0-9A-Z]{10,20}$"),
            ("中通快递", "zhongtong", "^(ZTO)?(68|73|75|78)[0-9]{10,12}$"),
            ("圆通速递", "yuantong", "^(YT|D)[0-9]{10,15}$"),
            ("申通快递", "shentong", "^(STO)?(33|55|66|77|88)[0-9]{10,12}$"),
            ("极兔速递", "jtexpress", "^JT[0-9]{10,15}$"),
            ("韵达速递", "yunda", "^(31|43|46|19)[0-9]{11,13}$"),
            ("京东物流", "jd", "^JD[A-Z0-9]{10,20}$"),
            ("EMS", "ems", "^[A-Z]{2}[0-9]{9}[A-Z]{2}$"),
            ("德邦快递", "debangkuaidi", "^DPK[0-9]{9,15}$"),
            ("百世快递", "huitongkuaidi", "^[ABD][0-9]{12}$"),
            ("宅急送", "zhaijisong", "^ZJS[0-9]{10,}$"),
            ("邮政快递", "youzhengguonei", "^[0-9]{13}$")
        ]
        for (name, kd, pat) in table {
            if n.range(of: pat, options: [.regularExpression, .caseInsensitive]) != nil {
                return CarrierInfo(name: name, kd: kd)
            }
        }
        return CarrierInfo(name: "未识别", kd: "")
    }

    // MARK: - 变更单号

    /// 命中「变更」句式才返回；不像变更单就返回 nil，交回普通录入
    static func parseChange(_ text: String, existing: Set<String>) -> ChangeIntent? {
        guard text.range(of: changePattern, options: .regularExpression) != nil else { return nil }
        let nos = noTokens(text)
        if nos.count < 2 {
            return ChangeIntent(oldNo: nos.first ?? "", newNo: "",
                                error: "变更要写两个单号，例如：运单号：旧号，变更，运单号：新号")
        }
        let a = existing.contains(normNo(nos[0]))
        let b = existing.contains(normNo(nos[1]))
        if a && !b { return ChangeIntent(oldNo: nos[0], newNo: nos[1], error: nil) }
        if !a && b { return ChangeIntent(oldNo: nos[1], newNo: nos[0], error: nil) }
        if a && b {
            return ChangeIntent(oldNo: nos[0], newNo: nos[1],
                                error: "两个单号都已经录入过了，请核对后再变更")
        }
        return ChangeIntent(oldNo: nos[0], newNo: nos[1], error: nil)
    }
}
