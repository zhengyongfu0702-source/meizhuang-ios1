import SwiftUI
import UIKit

/// 导出 CSV 并调用系统分享面板。
/// WebView 里 a.download 是死路，原生这边用 UIActivityViewController，
/// 可以直接存到「文件」App，或者发到微信/邮件。
enum Exporter {
    static func csv(_ rows: [Shipment]) -> String {
        var lines: [String] = []
        lines.append("运单号,快递/客人,物品,金额,状态,结算,结算金额,备注,录入时间")
        for r in rows {
            let settle: String
            if r.isPartSettled {
                settle = "部分结算"
            } else if (r.settled ?? 0) != 0 {
                settle = "已结清"
            } else if (r.deposit ?? 0) != 0 {
                settle = "寄存中"
            } else {
                settle = "未结算"
            }
            let cells = [
                r.tracking_no,
                r.carrierLabel,
                r.items.joined(separator: "、"),
                String(format: "%.2f", r.displayAmount),
                r.statusKind.label,
                settle,
                r.settle_amount.map { String(format: "%.2f", $0) } ?? "",
                r.note ?? "",
                Fmt.fullTime(r.created_at)
            ]
            lines.append(cells.map(esc).joined(separator: ","))
        }
        // 加 BOM，Excel 打开中文不乱码
        return "\u{FEFF}" + lines.joined(separator: "\r\n")
    }

    /// 写到临时目录，返回可分享的文件地址
    static func writeTempFile(_ content: String, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        guard let data = content.data(using: .utf8) else {
            throw NSError(domain: "export", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "内容编码失败"])
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func esc(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
