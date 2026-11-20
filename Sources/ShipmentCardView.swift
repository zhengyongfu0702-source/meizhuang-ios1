import SwiftUI

struct ShipmentCardView: View {
    let row: Shipment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.tracking_no)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(MZ.text)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(Fmt.shortDay(row.created_at))
                        .font(.system(size: 12))
                        .foregroundColor(MZ.muted)
                }

                Spacer(minLength: 6)
                badge
            }

            if !row.items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(row.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 5) {
                            Text("·")
                                .font(.system(size: 13))
                                .foregroundColor(MZ.muted)
                            Text(item)
                                .font(.system(size: 13))
                                .foregroundColor(MZ.text)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.top, 10)
            }

            HStack(spacing: 10) {
                Text(row.carrierLabel)
                    .font(.system(size: 12))
                    .foregroundColor(MZ.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MZ.soft2)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(Fmt.money(row.displayAmount))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(MZ.text)

                Spacer(minLength: 0)
            }
            .padding(.top, 10)

            if row.traceCount > 0 {
                VStack(alignment: .leading, spacing: 1) {
                    Text("查看轨迹")
                    Text("（\(row.traceCount) 条）")
                }
                .font(.system(size: 13))
                .foregroundColor(MZ.brand)
                .padding(.top, 8)
            }

            DashedLine()
                .stroke(MZ.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
                .padding(.top, 12)

            HStack(spacing: 3) {
                Spacer()
                Text("点按卡片展开操作")
                    .font(.system(size: 11))
                    .foregroundColor(MZ.muted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(MZ.muted)
            }
            .padding(.top, 8)
        }
        .padding(MZ.padCard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MZ.card)
        .clipShape(RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MZ.radiusCard, style: .continuous)
                .stroke(MZ.line, lineWidth: 1)
        )
        .shadow(color: Color(hex: 0x101828).opacity(0.05), radius: 1, x: 0, y: 1)
    }

    private var badge: some View {
        let kind = row.statusKind
        let fg: Color
        let bg: Color
        switch kind {
        case .transit:
            fg = MZ.brand
            bg = MZ.brandSoft
        case .signed:
            fg = MZ.ok
            bg = MZ.okSoft
        case .problem:
            fg = MZ.bad
            bg = MZ.badSoft
        case .pending:
            fg = MZ.wait
            bg = MZ.waitSoft
        case .locker:
            fg = MZ.warn
            bg = MZ.warnSoft
        }
        return Text(kind.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
