//
//  SharedViews.swift
//  Span — shared UI building blocks for the dark "Health Intelligence" theme.
//
//  Nav bar, section label, educational footer, segmented control, toggle,
//  primary/ghost buttons, tab bar styling, skeletons, and the load-failure view.
//

import SwiftUI

// MARK: - Nav bar (.nb / .nbk / .nbt / .nba)

/// The comp's top nav bar: optional back chevron (purple), bold title, optional
/// trailing accessory. Blurred surface with a bottom hairline.
struct SpanNavBar<Trailing: View>: View {
    let title: String
    var backTitle: String? = nil
    var onBack: (() -> Void)? = nil
    var titleAlignment: HorizontalAlignment = .leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 9) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        if let backTitle { Text(backTitle).font(.system(size: 13, weight: .medium)) }
                    }
                    .foregroundStyle(SpanColor.accent)
                }
                .buttonStyle(.plain)
            }

            Text(title)
                .font(SpanFont.title3)
                .kerning(-0.35)
                .foregroundStyle(SpanColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: titleAlignment == .leading ? .leading : (titleAlignment == .trailing ? .trailing : .center))

            trailing()
        }
        .padding(.horizontal, SpanSpacing.screenH)
        .frame(height: 44)
        .background(SpanColor.surface.opacity(0.88))
        .background(.ultraThinMaterial)
        .spanBottomHairline()
    }
}

extension SpanNavBar where Trailing == EmptyView {
    init(title: String, backTitle: String? = nil, onBack: (() -> Void)? = nil,
         titleAlignment: HorizontalAlignment = .leading) {
        self.init(title: title, backTitle: backTitle, onBack: onBack,
                  titleAlignment: titleAlignment) { EmptyView() }
    }
}

// MARK: - Section label (.lbl)

/// Uppercase, tracked, tertiary section label.
struct SpanSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).spanSectionHeaderStyle()
    }
}

/// Section header row with an optional trailing accessory.
struct SectionHeader: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title).spanSectionHeaderStyle()
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - Educational footer (.edu)

struct DisclaimerFooter: View {
    var text: String = "Educational only · discuss any result with your clinician."

    var body: some View {
        Text(text)
            .spanDisclaimerStyle()
            .padding(.top, SpanSpacing.gutter)
            .padding(.bottom, SpanSpacing.xs)
            .padding(.horizontal, SpanSpacing.screenH)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Rectangle().fill(SpanColor.border).frame(height: SpanSpacing.hairline)
            }
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Buttons

/// Light filled primary button (.btnP / .btnA) — near-white fill, near-black label.
struct SpanPrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .kerning(-0.15)
            .foregroundStyle(enabled ? SpanColor.onPrimary : SpanColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: SpanSpacing.touchTarget)
            .background(
                (enabled ? SpanColor.textPrimary : SpanColor.surfaceRaised),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Ghost / secondary button (.btnG) — transparent, hairline border, muted text.
struct SpanGhostButtonStyle: ButtonStyle {
    var tint: Color = SpanColor.textSecondary
    var border: Color = SpanColor.borderStrong
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(border, lineWidth: SpanSpacing.hairline)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func spanPrimaryButton(enabled: Bool = true) -> some View {
        buttonStyle(SpanPrimaryButtonStyle(enabled: enabled)).disabled(!enabled)
    }
    func spanGhostButton(tint: Color = SpanColor.textSecondary,
                         border: Color = SpanColor.borderStrong) -> some View {
        buttonStyle(SpanGhostButtonStyle(tint: tint, border: border))
    }
}

// MARK: - Segmented control (.seg)

/// A dark segmented control. `selection` binds to the index of `options`.
struct SpanSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, label in
                let active = idx == selection
                Text(label)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? SpanColor.textPrimary : SpanColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(active ? SpanColor.surfaceRaised : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = idx }
            }
        }
        .padding(2)
        .background(SpanColor.surfaceCard, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(SpanColor.border, lineWidth: SpanSpacing.hairline)
        )
    }
}

// MARK: - Toggle (.tog)

/// A dark pill toggle that matches the comp (green when on, b2 track when off).
struct SpanToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .tint(SpanColor.statusGreen)
    }
}

// MARK: - Tab bar styling helpers

/// Apply the comp's dark tab-bar appearance (blurred surface, purple selected,
/// tertiary unselected) globally. Call once from the app root.
enum SpanTabBarStyle {
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(SpanColor.surface).withAlphaComponent(0.92)
        appearance.shadowColor = UIColor(SpanColor.border)

        let item = appearance.stackedLayoutAppearance
        let unselected = UIColor(SpanColor.textTertiary)
        let selected = UIColor(SpanColor.accent)
        item.normal.iconColor = unselected
        item.normal.titleTextAttributes = [.foregroundColor: unselected,
                                            .font: UIFont.systemFont(ofSize: 9)]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected,
                                              .font: UIFont.systemFont(ofSize: 9)]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = selected
    }
}

/// Apply the comp's dark nav-bar appearance (used if a screen uses a system
/// NavigationStack bar rather than `SpanNavBar`).
enum SpanNavBarStyle {
    static func apply() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(SpanColor.surface).withAlphaComponent(0.88)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(SpanColor.textPrimary)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(SpanColor.textPrimary)]
        appearance.shadowColor = UIColor(SpanColor.border)
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(SpanColor.accent)
    }
}

// MARK: - Loading skeleton

struct SkeletonBlock: View {
    var height: CGFloat = 80
    var body: some View {
        RoundedRectangle(cornerRadius: SpanRadius.card, style: .continuous)
            .fill(SpanColor.surfaceRaised)
            .frame(height: height)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

// MARK: - Inline error with retry

struct LoadFailureView: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: SpanSpacing.gutter) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(SpanColor.textTertiary)
            Text(message)
                .font(SpanFont.callout)
                .foregroundStyle(SpanColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .spanPrimaryButton()
                .frame(maxWidth: 160)
        }
        .frame(maxWidth: .infinity)
        .padding(SpanSpacing.xl)
    }
}

#Preview("Controls") {
    StatefulPreview()
        .padding(20)
        .background(SpanColor.background)
}

private struct StatefulPreview: View {
    @State private var seg = 2
    @State private var on = true
    var body: some View {
        VStack(spacing: 20) {
            SpanNavBar(title: "Biological age", backTitle: nil, onBack: {})
            SpanSectionLabel("Wellbeing")
            SpanSegmentedControl(options: ["28d", "1y", "All"], selection: $seg)
            HStack { Text("On treatment").foregroundStyle(SpanColor.textPrimary); Spacer(); SpanToggle(isOn: $on) }
            Button("I understand — continue") {}.spanPrimaryButton()
            Button("Skip for now") {}.spanGhostButton()
            DisclaimerFooter()
        }
    }
}
