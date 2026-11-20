import SwiftUI

struct LoginView: View {
    init() {}

    @EnvironmentObject var state: AppState

    @State private var username = ""
    @State private var password = ""
    @State private var remember = true
    @State private var busy = false
    @State private var errorText = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 6) {
                Text("全品类回收统计")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(MZ.text)
                Text("登录后在这台设备上免密使用")
                    .font(.system(size: 13))
                    .foregroundColor(MZ.muted)
            }
            .padding(.bottom, 26)

            VStack(spacing: 12) {
                field(title: "账号", text: $username, secure: false)
                field(title: "密码", text: $password, secure: true)

                Toggle(isOn: $remember) {
                    Text("记住这台设备（下次打开免密）")
                        .font(.system(size: 13))
                        .foregroundColor(MZ.muted)
                }
                .toggleStyle(SwitchToggleStyle(tint: MZ.brand))

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundColor(MZ.bad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "登录中…" : "登录")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(MZ.brand)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(busy || username.isEmpty || password.isEmpty)
                .opacity(username.isEmpty || password.isEmpty ? 0.55 : 1)
            }
            .padding(16)
            .background(MZ.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MZ.line, lineWidth: 1)
            )
            .padding(.horizontal, MZ.pagePad)

            Spacer()

            Text("线路：\(API.shared.usingBackup ? "备用（IP 直连）" : "主线路 https://736918.top")")
                .font(.system(size: 11))
                .foregroundColor(MZ.muted)
                .padding(.bottom, 10)
        }
        .background(MZ.bg.ignoresSafeArea())
        .onAppear {
            if username.isEmpty, let u = UserDefaults.standard.string(forKey: "last_user") {
                username = u
            }
        }
    }

    @ViewBuilder
    private func field(title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(MZ.muted)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(MZ.soft2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        errorText = ""
        Task {
            do {
                try await state.login(username: username, password: password, remember: remember)
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
}
