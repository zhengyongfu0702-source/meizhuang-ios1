import SwiftUI

@main
struct MeizhuangApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.light)
                .task {
                    if state.user == nil && !state.showingLogin {
                        await state.bootstrap()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            MZ.bg.ignoresSafeArea()
            if state.booting {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在启动…")
                        .font(.system(size: 12))
                        .foregroundColor(MZ.muted)
                }
            } else if state.showingLogin {
                LoginView()
                    .transition(.opacity)
            } else {
                HomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.showingLogin)
        .animation(.easeInOut(duration: 0.18), value: state.booting)
        .overlay(alignment: .top) {
            if !state.toast.isEmpty {
                Text(state.toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(hex: 0x1D2430).opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
    }
}
