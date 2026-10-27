import SwiftUI

struct SnapshotButton: View {
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 55, height: 55)
                .background(Color.red, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .help("Save the current processed frame as a PNG image")
        .accessibilityLabel("Take Snapshot")
    }
}

struct CameraButton: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRunning ? "video.fill" : "video.slash.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color.gray, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help(isRunning ? "Stop camera" : "Start camera")
        .accessibilityLabel(isRunning ? "Stop camera" : "Start camera")
    }
}

struct BackgroundEffectsStrip: View {
    @Binding var selection: WorkspaceModel.Effect
    let backgrounds: [BackgroundOption]
    let isLoading: Bool
    let onImport: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    EffectTile(title: "Original", isSelected: selection == .original) {
                        selection = .original
                    } content: {
                        Color(white: 0.16)
                            .overlay {
                                Image(systemName: "nosign")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                    }
                    .id(WorkspaceModel.Effect.original)

                    EffectTile(title: "Blur", isSelected: selection == .blur) {
                        selection = .blur
                    } content: {
                        LinearGradient(colors: [.cyan, .indigo, .purple],
                                       startPoint: .bottomLeading, endPoint: .topTrailing)
                            .overlay {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .blur(radius: 1)
                            }
                    }
                    .id(WorkspaceModel.Effect.blur)

                    ForEach(backgrounds) { background in
                        let effect = WorkspaceModel.Effect.background(background.id)
                        EffectTile(title: background.name, isSelected: selection == effect) {
                            selection = effect
                        } content: {
                            Image(nsImage: background.thumbnail)
                                .resizable()
                                .scaledToFill()
                        }
                        .id(effect)
                    }

                    EffectTile(title: isLoading ? "Loading Background…" : "Add Background",
                               isSelected: false, action: onImport) {
                        Color(white: 0.16)
                            .overlay {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 32, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .frame(height: 124)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .onChange(of: selection) { _, value in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
        .accessibilityLabel("Background effects")
    }
}

private struct EffectTile<Content: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isSelected ? Color.orange : Color.gray.opacity(0.65),
                                      lineWidth: isSelected ? 2 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.orange, in: Circle())
                            .offset(x: 8, y: -8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
