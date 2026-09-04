import SwiftUI
import UIKit

enum PinbookOnboardingState {
    static let completionKey = "pinbook.onboarding.completed.v1"
}

enum PinbookOnboardingPolicy {
    static func shouldPresent(
        mode: PinbookOnboardingMode,
        hasCompleted: Bool,
        overrideDismissed: Bool
    ) -> Bool {
        guard !overrideDismissed else { return false }
        switch mode {
        case .automatic: return !hasCompleted
        case .show: return true
        case .skip: return false
        }
    }
}

struct PinbookOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PinbookLanguage.preferenceKey, store: PinbookLanguage.preferenceStore) private var languagePreference = PinbookLanguage.system.rawValue
    @State private var showingLanguagePicker = false
    @State private var pageIndex = 0
    @State private var symbolIsFloating = false
    let completion: () -> Void

    private let pages = PinbookOnboardingPage.all

    var body: some View {
        ZStack {
            pages[pageIndex].background
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: pageIndex)

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack {
                        Text("Welcome to Pinbook")
                            .font(.headline)
                        Spacer()
                    }

                    HStack {
                        languageMenu
                        Spacer()
                        Button("Skip") { finish() }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("onboarding-skip")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)

                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPageView(
                            page: page,
                            isFloating: symbolIsFloating && index == pageIndex,
                            reduceMotion: reduceMotion
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .snappy(duration: 0.42), value: pageIndex)

                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == pageIndex ? pages[pageIndex].accent : Color.secondary.opacity(0.28))
                                .frame(width: index == pageIndex ? 28 : 8, height: 8)
                                .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: pageIndex)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Page \(pageIndex + 1) of \(pages.count)"))

                    HStack(spacing: 12) {
                        if pageIndex > 0 {
                            Button("Back", systemImage: "chevron.backward") {
                                move(to: pageIndex - 1)
                            }
                            .buttonStyle(.glass)
                        }

                        Button {
                            if pageIndex == pages.count - 1 {
                                finish()
                            } else {
                                move(to: pageIndex + 1)
                            }
                        } label: {
                            Label(
                                pageIndex == pages.count - 1 ? "Start fresh" : "Continue",
                                systemImage: pageIndex == pages.count - 1 ? "checkmark" : "arrow.forward"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("onboarding-primary-action")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled()
        .onAppear { startFloatingAnimation() }
        .onChange(of: reduceMotion) { _, _ in startFloatingAnimation() }
        .sheet(isPresented: $showingLanguagePicker) {
            LanguageOptionsSheet()
        }
        .modifier(PinbookLanguageEnvironment())
    }

    private var selectedLanguage: PinbookLanguage {
        PinbookLanguage(rawValue: languagePreference) ?? .system
    }

    private var languageMenu: some View {
        Button {
            showingLanguagePicker = true
        } label: {
            Label {
                if selectedLanguage == .system {
                    Text("System Default")
                } else {
                    Text(verbatim: selectedLanguage.nativeName)
                }
            } icon: {
                Image(systemName: "globe")
            }
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("onboarding-language-menu")
    }

    private func move(to index: Int) {
        if reduceMotion {
            pageIndex = index
        } else {
            withAnimation(.snappy(duration: 0.42)) { pageIndex = index }
        }
    }

    private func finish() {
        completion()
        dismiss()
    }

    private func startFloatingAnimation() {
        symbolIsFloating = false
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            symbolIsFloating = true
        }
    }
}

private struct OnboardingPageView: View {
    let page: PinbookOnboardingPage
    let isFloating: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 28)

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 190, height: 190)
                    .overlay {
                        Circle().stroke(page.accent.opacity(0.32), lineWidth: 1)
                    }
                    .shadow(color: page.accent.opacity(0.22), radius: 32, y: 18)

                Image(systemName: page.symbol)
                    .font(.system(size: 70, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(page.accent)
                    .offset(y: reduceMotion ? 0 : (isFloating ? -7 : 7))
                    .scaleEffect(reduceMotion ? 1 : (isFloating ? 1.04 : 0.96))
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("onboarding-title")
                Text(page.detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 540)
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 18)
        }
    }
}

private struct PinbookOnboardingPage: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let accent: Color
    let background: LinearGradient

    @MainActor static let all: [PinbookOnboardingPage] = [
        PinbookOnboardingPage(
            id: "capture",
            title: "Remember every expense",
            detail: "Keep periodic expenses organized by book, person, date, and currency—without mixing balances.",
            symbol: "wallet.bifold.fill",
            accent: onboardingColor(
                light: UIColor(red: 0.10, green: 0.42, blue: 0.32, alpha: 1),
                dark: UIColor(red: 0.46, green: 0.88, blue: 0.73, alpha: 1)
            ),
            background: LinearGradient(
                colors: [
                    onboardingColor(
                        light: UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1),
                        dark: UIColor(red: 0.06, green: 0.11, blue: 0.09, alpha: 1)
                    ),
                    onboardingColor(
                        light: UIColor(red: 0.83, green: 0.94, blue: 0.88, alpha: 1),
                        dark: UIColor(red: 0.09, green: 0.18, blue: 0.15, alpha: 1)
                    ),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        ),
        PinbookOnboardingPage(
            id: "currencies",
            title: "Choose your currencies",
            detail: "Select only the currencies you use. Pinbook keeps every balance separate and never guesses an exchange rate.",
            symbol: "coloncurrencysign.circle.fill",
            accent: onboardingColor(
                light: UIColor(red: 0.07, green: 0.36, blue: 0.68, alpha: 1),
                dark: UIColor(red: 0.47, green: 0.75, blue: 1.00, alpha: 1)
            ),
            background: LinearGradient(
                colors: [
                    onboardingColor(
                        light: UIColor(red: 0.91, green: 0.96, blue: 1.00, alpha: 1),
                        dark: UIColor(red: 0.05, green: 0.09, blue: 0.17, alpha: 1)
                    ),
                    onboardingColor(
                        light: UIColor(red: 0.82, green: 0.88, blue: 0.98, alpha: 1),
                        dark: UIColor(red: 0.10, green: 0.15, blue: 0.27, alpha: 1)
                    ),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        ),
        PinbookOnboardingPage(
            id: "settle",
            title: "See what remains",
            detail: "Record partial payments, keep currencies separate, and move completed expenses to Noted when you are done.",
            symbol: "chart.bar.xaxis.ascending",
            accent: onboardingColor(
                light: UIColor(red: 0.07, green: 0.36, blue: 0.68, alpha: 1),
                dark: UIColor(red: 0.47, green: 0.75, blue: 1.00, alpha: 1)
            ),
            background: LinearGradient(
                colors: [
                    onboardingColor(
                        light: UIColor(red: 0.91, green: 0.96, blue: 1.00, alpha: 1),
                        dark: UIColor(red: 0.05, green: 0.09, blue: 0.17, alpha: 1)
                    ),
                    onboardingColor(
                        light: UIColor(red: 0.82, green: 0.88, blue: 0.98, alpha: 1),
                        dark: UIColor(red: 0.10, green: 0.15, blue: 0.27, alpha: 1)
                    ),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        ),
        PinbookOnboardingPage(
            id: "private",
            title: "Private by default",
            detail: "Your records stay on this device. Export a backup through Files only when you choose a destination.",
            symbol: "lock.shield.fill",
            accent: onboardingColor(
                light: UIColor(red: 0.45, green: 0.21, blue: 0.65, alpha: 1),
                dark: UIColor(red: 0.78, green: 0.64, blue: 1.00, alpha: 1)
            ),
            background: LinearGradient(
                colors: [
                    onboardingColor(
                        light: UIColor(red: 0.97, green: 0.92, blue: 0.98, alpha: 1),
                        dark: UIColor(red: 0.12, green: 0.07, blue: 0.17, alpha: 1)
                    ),
                    onboardingColor(
                        light: UIColor(red: 0.88, green: 0.91, blue: 1.00, alpha: 1),
                        dark: UIColor(red: 0.10, green: 0.12, blue: 0.23, alpha: 1)
                    ),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        ),
    ]
}

private func onboardingColor(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}
