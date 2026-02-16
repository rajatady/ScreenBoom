import SwiftUI

struct ControlsPanel: View {
    @Bindable var project: Project

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                backgroundSection
                layoutSection
                shadowSection
                outputSection
                exportSection
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Background

    var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background")
                .font(.headline)

            HStack {
                ColorPicker("Color 1", selection: $project.gradientColor1)
                    .onChange(of: project.gradientColor1) { _, _ in project.updateVisuals() }
            }
            HStack {
                ColorPicker("Color 2", selection: $project.gradientColor2)
                    .onChange(of: project.gradientColor2) { _, _ in project.updateVisuals() }
            }

            HStack {
                Button("Dark") {
                    project.gradientColor1 = Color(red: 0.08, green: 0.08, blue: 0.12)
                    project.gradientColor2 = Color(red: 0.18, green: 0.12, blue: 0.28)
                    project.updateVisuals()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Light") {
                    project.gradientColor1 = Color(red: 0.92, green: 0.92, blue: 0.96)
                    project.gradientColor2 = Color(red: 0.85, green: 0.88, blue: 0.95)
                    project.updateVisuals()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Blue") {
                    project.gradientColor1 = Color(red: 0.05, green: 0.1, blue: 0.3)
                    project.gradientColor2 = Color(red: 0.1, green: 0.2, blue: 0.5)
                    project.updateVisuals()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Layout

    var layoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Padding: \(Int(project.padding))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $project.padding, in: 0...200, step: 5)
                    .onChange(of: project.padding) { _, _ in project.updateVisuals() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Corner Radius: \(Int(project.cornerRadius))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $project.cornerRadius, in: 0...60, step: 1)
                    .onChange(of: project.cornerRadius) { _, _ in project.updateVisuals() }
            }
        }
    }

    // MARK: - Shadow

    var shadowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shadow")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Radius: \(Int(project.shadowRadius))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $project.shadowRadius, in: 0...80, step: 1)
                    .onChange(of: project.shadowRadius) { _, _ in project.updateVisuals() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Opacity: \(Int(project.shadowOpacity * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $project.shadowOpacity, in: 0...1, step: 0.05)
                    .onChange(of: project.shadowOpacity) { _, _ in project.updateVisuals() }
            }
        }
    }

    // MARK: - Output

    var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)

            Picker("Resolution", selection: Binding(
                get: { "\(Int(project.outputWidth))x\(Int(project.outputHeight))" },
                set: { val in
                    let parts = val.split(separator: "x")
                    if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) {
                        project.outputWidth = w
                        project.outputHeight = h
                        project.updateVisuals()
                    }
                }
            )) {
                Text("1920x1080").tag("1920x1080")
                Text("2560x1440").tag("2560x1440")
                Text("3840x2160").tag("3840x2160")
                Text("1280x720").tag("1280x720")
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Export

    var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export")
                .font(.headline)

            if project.isExporting {
                ProgressView(value: project.exportProgress) {
                    Text("Exporting... \(Int(project.exportProgress * 100))%")
                        .font(.caption)
                }
            } else {
                Button("Export MP4") {
                    project.startExport()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(project.segments.filter(\.isEnabled).isEmpty)
            }
        }
    }
}
