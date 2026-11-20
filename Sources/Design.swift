import Foundation
import SwiftUI

/// 设计令牌：与线上 index.html 的 CSS 变量一一对应，保证原生版和网页版看起来是同一个东西。
enum MZ {
    static let bg = Color(hex: 0xF5F7FA)
    static let card = Color.white
    static let line = Color(hex: 0xE6EAF0)
    static let text = Color(hex: 0x1D2430)
    static let muted = Color(hex: 0x7A8699)
    static let brand = Color(hex: 0x2F6BFF)
    static let brandSoft = Color(hex: 0xEAF0FF)
    static let ok = Color(hex: 0x12A150)
    static let okSoft = Color(hex: 0xE6F6EC)
    static let warn = Color(hex: 0xE08600)
    static let warnSoft = Color(hex: 0xFFF3E0)
    static let bad = Color(hex: 0xD93025)
    static let badSoft = Color(hex: 0xFCE8E6)
    static let wait = Color(hex: 0x6B7280)
    static let waitSoft = Color(hex: 0xF1F3F6)
    static let soft = Color(hex: 0xFAFBFD)
    static let soft2 = Color(hex: 0xF2F4F8)
    static let hover = Color(hex: 0xF3F7FF)

    static let radiusCard: CGFloat = 14
    static let padCard: CGFloat = 14
    static let gapCard: CGFloat = 10
    static let pagePad: CGFloat = 12
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1
        )
    }
}

/// 金额 / 时间格式化。规则和网页版 money()、fmtTime()、日期显示保持一致。
enum Fmt {
    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    static func money(_ v: Double?) -> String {
        guard let v = v else { return "¥0.00" }
        let s = moneyFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
        return "¥" + s
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func date(_ isoString: String?) -> Date? {
        guard let s = isoString, !s.isEmpty else { return nil }
        if let d = iso.date(from: s) { return d }
        if let d = isoNoFrac.date(from: s) { return d }
        if let d = local.date(from: s) { return d }
        return nil
    }

    /// 卡片上的日期：MM-dd（跨年时补年份，和网页版一致）
    static func shortDay(_ isoString: String?) -> String {
        guard let d = date(isoString) else { return "" }
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = cal.component(.year, from: d) == cal.component(.year, from: Date()) ? "MM-dd" : "yyyy-MM-dd"
        return df.string(from: d)
    }

    /// 完整时间：yyyy-MM-dd HH:mm
    static func fullTime(_ isoString: String?) -> String {
        guard let d = date(isoString) else { return "" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: d)
    }

    static func todayKey() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}

/// 统一的白色圆角卡片容器
struct MZCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = MZ.padCard, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MZ.card)
            .clipShape(RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous)
                    .stroke(MZ.line, lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x101828).opacity(0.05), radius: 1, x: 0, y: 1)
    }
}
