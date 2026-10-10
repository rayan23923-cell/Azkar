import SwiftUI
import QuranText

/// The short animation shown once when the app starts: the ornaments supplied by the app's
/// owner (light and dark variants in Assets.xcassets) gather in the middle, then fade to the
/// app. The launch screen before it is the plain page colour (`LaunchBackground`), which is
/// this view's first frame. With Reduce Motion it only fades.
struct LaunchSplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var turned = false
    @State private var leaving = false

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width * 0.52, geometry.size.height * 0.3, 260)
            let corner = min(geometry.size.width * 0.26, 130)
            ZStack {
                Color("LaunchBackground")
                    .ignoresSafeArea()

                RadialGradient(colors: [Color(red: 0.95, green: 0.80, blue: 0.40).opacity(0.55), .clear],
                               center: .center, startRadius: 0, endRadius: side * 0.95)
                    .frame(width: side * 2, height: side * 2)
                    .scaleEffect(shown ? 1 : 0.6)
                    .opacity(shown ? 1 : 0)

                Image("SplashRing")
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 1.42, height: side * 1.42)
                    .rotationEffect(.degrees(turned ? 0 : -50))
                    .scaleEffect(shown ? 1 : 1.15)
                    .opacity(shown ? 1 : 0)

                Image("SplashMedallion")
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .scaleEffect(shown ? 1 : 0.7)
                    .opacity(shown ? 1 : 0)

                Text("أذكار")
                    .font(.custom(QuranFont.postScriptName, size: side * 0.13))
                    .foregroundStyle(Color(red: 0.72, green: 0.56, blue: 0.24))
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : side * 0.04)

                cornerImage("SplashCornerTL", size: corner, alignment: .topLeading)
                cornerImage("SplashCornerTR", size: corner, alignment: .topTrailing)
                cornerImage("SplashCornerBL", size: corner, alignment: .bottomLeading)
                cornerImage("SplashCornerBR", size: corner, alignment: .bottomTrailing)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // The corners are drawn as they are, left and right as in the artwork.
        .environment(\.layoutDirection, .leftToRight)
        .opacity(leaving ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("أذكار")
        .task { await run() }
    }

    private func cornerImage(_ name: String, size: CGFloat, alignment: Alignment) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(shown ? 1 : 0)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func run() async {
        if reduceMotion {
            turned = true
            withAnimation(.easeOut(duration: 0.35)) { shown = true }
            try? await Task.sleep(nanoseconds: 900_000_000)
        } else {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { shown = true }
            withAnimation(.easeOut(duration: 1.6)) { turned = true }
            try? await Task.sleep(nanoseconds: 1_900_000_000)
        }
        withAnimation(.easeIn(duration: 0.35)) { leaving = true }
        try? await Task.sleep(nanoseconds: 350_000_000)
        onFinish()
    }
}
