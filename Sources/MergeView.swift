import SwiftUI

/// 合并上门单：分几次上门收的货，最后并成一票快递寄出。
/// 校验规则与后端 _handle_merge_pseudo 完全一致——前端先挡一遍，避免提交后才报错。
struct MergeView: View {
    init() {}

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var picked = Set<Int>()
    @State private var no = ""
    @State private var busy = false
    @State private var err = ""

    private var pseudoRows: [Shipment] {
        state.rows.filter { $0.isPseudo }
    }

    private var pickedRows: [Shipment] {
        pseudoRows.filter { picked.contains($0.id) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if pseudoRows.isEmpty {
                    VStack(spacing: 8) {
                        Text("没有可合并的上门单")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MZ.text)
                        Text("上门单是一句话里写「上门 客人名 物品 金额」录进来的，\n录过之后才会出现在这里。")
                            .font(.system(size: 12))
                            .foregroundColor(MZ.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(pseudoRows) { r in
                                mergeRow(r)
                            }
                            if !err.isEmpty {
                                Text(err)
                                    .font(.system(size: 13))
                                    .foregroundColor(MZ.bad)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 2)
                            }
                        }
                        .padding(14)
                    }
                }

                bottomBar
            }
            .background(MZ.bg)
            .navigationTitle("合并上门单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(picked.count == pseudoRows.count ? "取消全选" : "全选") {
                        if picked.count == pseudoRows.count {
                            picked.removeAll()
                        } else {
                            picked = Set(pseudoRows.map { $0.id })
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func mergeRow(_ r: Shipment) -> some View {
        Button {
            if picked.contains(r.id) { picked.remove(r.id) } else { picked.insert(r.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: picked.contains(r.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(picked.contains(r.id) ? MZ.brand : MZ.line)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(r.guestName.isEmpty ? QuickParser.pseudoLabel : r.guestName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MZ.text)
                        if (r.settled ?? 0) != 0 {
                            Text("已结算")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(MZ.ok)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(MZ.okSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(r.items.isEmpty ? "（无物品明细）" : r.items.joined(separator: "、"))
                        .font(.system(size: 11.5))
                        .foregroundColor(MZ.muted)
                        .lineLimit(1)
                    Text("\(Fmt.shortDay(r.created_at)) · \(r.tracking_no)")
                        .font(.system(size: 10.5))
                        .foregroundColor(MZ.muted)
                }

                Spacer(minLength: 6)

                Text(Fmt.money(r.displayAmount))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(MZ.text)
            }
            .padding(12)
            .background(MZ.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(picked.contains(r.id) ? MZ.brand.opacity(0.6) : MZ.line,
                            lineWidth: picked.contains(r.id) ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("合并后的快递单号", text: $no)
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(MZ.card)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(MZ.line, lineWidth: 1)
                    )

                Button {
                    Task { await submit() }
                } label: {
                    Text(busy ? "合并中" : "合并")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 76, height: 42)
                        .background(picked.count >= 2 ? MZ.brand : MZ.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .disabled(busy || picked.count < 2)
            }

            HStack(spacing: 4) {
                Text("已选 \(picked.count) 张")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(MZ.text)
                Text("合计 \(Fmt.money(pickedRows.reduce(0) { $0 + $1.displayAmount }))")
                    .font(.system(size: 11.5))
                    .foregroundColor(MZ.muted)
                Spacer()
                Text("原单会被删除，单号写进新单的「原单号」")
                    .font(.system(size: 10.5))
                    .foregroundColor(MZ.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(MZ.card)
        .overlay(alignment: .top) {
            Rectangle().fill(MZ.line).frame(height: 1)
        }
    }

    // MARK: - 提交

    private func submit() async {
        if let m = validate() {
            err = m
            return
        }
        err = ""
        busy = true
        let code = no.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let car = QuickParser.carrier(code).name
        do {
            let res = try await API.shared.mergePseudo(
                ids: pickedRows.map { $0.id },
                trackingNo: code,
                carrierName: car == "未识别" ? "" : car
            )
            await state.load()
            state.flash("已合并成 \(code)（\(res.merged ?? pickedRows.count) 张单）")
            busy = false
            dismiss()
        } catch {
            busy = false
            err = error.localizedDescription
        }
    }

    private func validate() -> String? {
        if pickedRows.count < 2 { return "至少要选两张单才能合并" }
        let settled = pickedRows.filter { ($0.settled ?? 0) != 0 }
        if settled.count > 0 && settled.count < pickedRows.count {
            return "已结算和未结算的单不能混在一起合并"
        }
        if settled.count == pickedRows.count {
            for r in pickedRows {
                let got = r.settle_amount ?? (r.amount ?? 0)
                if got - (r.amount ?? 0) <= 0 {
                    return "「\(r.tracking_no)」已结算但没有利润，不能参与合并"
                }
            }
        }
        let code = no.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty { return "请填写合并后的快递单号" }
        if QuickParser.isPseudo(code) { return "物流单号不能填成「上门回收」这类标签" }
        if state.rows.contains(where: { !$0.isPseudo && QuickParser.normNo($0.tracking_no) == QuickParser.normNo(code) }) {
            return "单号 \(code) 已经被别的运单占用了"
        }
        return nil
    }
}
