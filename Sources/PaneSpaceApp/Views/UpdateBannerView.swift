import SwiftUI

/// The window-wide reminder that a newer PaneSpace is available.
///
/// It spans the whole window rather than living in a pane: an update is a property of the
/// application, and a banner that belonged to one pane would be hidden by the layout the user
/// happens to have chosen. It is also the *only* notice a scheduled check produces — Sparkle's own
/// window is not built for scheduled updates (gentle reminders hand that job to this view), so
/// anything this banner does not show, the user is not told about.
///
/// A scheduled check that failed shows nothing. That failure is not something the user can act
/// on, and a banner that reported it would turn a background hiccup into a question with no
/// answer available.
struct UpdateBannerView: View {
    @ObservedObject var updates: UpdateModel

    var body: some View {
        if let update = updates.availableUpdate {
            bannerBar(UpdateBannerPresentation.banner(for: update), for: update)
        }
    }

    private func bannerBar(_ banner: UpdateBannerPresentation, for update: AvailableUpdate) -> some View {
        HStack(spacing: 10) {
            // Only the text is combined into one element. The buttons stay separate so VoiceOver
            // still reaches each action on its own.
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text(banner.headline)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if let badge = banner.channelBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(banner.accessibilityLabel)

            Spacer(minLength: 12)

            Button(L10n.text("Skip This Version")) {
                updates.skip(version: update.displayVersion)
            }
            .help(L10n.text("Skip This Version"))

            Button(L10n.text("Dismiss")) {
                updates.dismiss()
            }
            .help(L10n.text("Dismiss"))

            Button(banner.primaryActionTitle) {
                updates.installAvailableUpdate()
            }
            .buttonStyle(.borderedProminent)
            .help(banner.primaryActionTitle)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}
