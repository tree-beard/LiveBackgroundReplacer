import SwiftUI

struct ContentView: View {
    @StateObject private var model: WorkspaceModel
    @State private var isChoosingBackground = false

    init(preview: Bool = false) {
        _model = StateObject(wrappedValue: WorkspaceModel(preview: preview))
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Color.black
                if let renderer = model.renderer {
                    CameraViewRepresentable(renderer: renderer)
                }
                if model.state != .running {
                    Text(model.state.message)
                        .multilineTextAlignment(.center)
                        .padding()
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
            .frame(minWidth: 480, minHeight: 270)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                CameraButton(isRunning: model.requestedRunning) {
                    if model.requestedRunning { model.stop() } else { model.start() }
                }
                .disabled(model.renderer == nil)
                .padding(16)
            }

            BackgroundEffectsStrip(selection: $model.effect,
                                   backgrounds: model.backgrounds,
                                   isLoading: model.isLoadingBackground) {
                isChoosingBackground = true
            }
            HStack {
                Spacer()
                Toggle("Mirror", isOn: $model.mirrored)
            }
            if model.effect == .blur {
                HStack {
                    Text("Blur")
                    Slider(value: $model.blurRadius, in: 0...40)
                    Text(model.blurRadius, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit().frame(width: 30)
                }
            }
            if let warning = model.warning ?? model.metrics?.warning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            SnapshotButton(action: model.captureSnapshot)
            .disabled(model.state != .running || !model.requestedRunning || model.isExportingSnapshot)
			HStack {
				VStack(alignment: .leading) {
					Text(model.state.message).font(.caption)
					if let metrics = model.metrics {
						Text(String(format: "Processing: %.1f FPS · Vision: %.1f ms · Dropped: %d",
									metrics.processedFPS, metrics.visionMilliseconds, metrics.droppedFrames))
							.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
					}
				}
				Spacer()
			}
        }
        .padding()
        .fileImporter(isPresented: $isChoosingBackground,
                      allowedContentTypes: [.png, .jpeg, .heic, .tiff],
                      onCompletion: model.importBackground)
        .fileExporter(isPresented: $model.isExportingSnapshot,
                      document: model.snapshotDocument,
                      contentType: .png,
                      defaultFilename: model.snapshotFilename,
                      onCompletion: model.finishSnapshotExport)
        .alert(model.backgroundImportError != nil ? "Unable to Load Background" : "Unable to Save Snapshot", isPresented: Binding(
            get: { model.snapshotError != nil || model.backgroundImportError != nil },
            set: {
                if !$0 {
                    model.snapshotError = nil
                    model.backgroundImportError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                model.snapshotError = nil
                model.backgroundImportError = nil
            }
        } message: {
            Text(model.backgroundImportError ?? model.snapshotError ?? "")
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

#Preview {
    ContentView(preview: true)
}
