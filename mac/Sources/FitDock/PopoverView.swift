import Charts
import ServiceManagement
import SwiftUI

/// Conteúdo do painel da barra de menus.
struct PopoverView: View {
    static let width: CGFloat = 320

    let model: AppModel
    /// Avisa o painel quando a altura muda (resumo e preferências têm tamanhos diferentes).
    var onSizeChange: (CGSize) -> Void = { _ in }
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 10) {
            if showingSettings {
                SettingsPage(model: model) { showingSettings = false }
            } else {
                SummaryPage(model: model)
                footer
            }
        }
        .padding(12)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
    }

    private var footer: some View {
        HStack {
            Button("Preferências") { showingSettings = true }
            Spacer()
            Button("Sair") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card()
    }
}

private struct SummaryPage: View {
    let model: AppModel

    var body: some View {
        if let s = model.snapshot {
            VStack(spacing: 10) {
                rings(s)
                details(s)
                if let series = s.heartRateSeries, series.count > 1 {
                    chart(series)
                }
                updatedLine(s)
            }
            .opacity(model.isStale ? 0.6 : 1)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Aguardando o celular", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.headline)
                Text("Abra o FitDock no celular, informe o código \(model.code) e toque em Sincronizar agora.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func rings(_ s: Snapshot) -> some View {
        let steps = s.steps ?? 0
        let goal = max(model.stepGoal, 1)
        return HStack(spacing: 0) {
            Ring(progress: Double(steps) / Double(goal), tint: .green) {
                RingLabel(symbol: "figure.walk", value: s.steps.map(Format.compactSteps) ?? "--", caption: "passos")
            }
            Spacer()
            Ring(progress: s.heartRate == nil ? 0 : 1, tint: .red) {
                RingLabel(symbol: "heart.fill", value: s.heartRate.map { "\($0.bpm)" } ?? "--", caption: "bpm")
            }
            Spacer()
            Ring(progress: (s.activeCaloriesKcal ?? 0) / 500, tint: .orange) {
                RingLabel(symbol: "flame.fill",
                          value: s.activeCaloriesKcal.map { "\(Int($0.rounded()))" } ?? "--",
                          caption: "kcal ativas")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .card()
    }

    private func details(_ s: Snapshot) -> some View {
        VStack(spacing: 8) {
            Row(label: "Meta de passos", value: "\(Format.integer(s.steps ?? 0)) de \(Format.integer(model.stepGoal))")
            Row(label: "Distância", value: s.distanceMeters.map(Format.distance) ?? "sem dado")
            Row(label: "Calorias totais", value: s.totalCaloriesKcal.map(Format.kcal) ?? "sem dado")
            if let hr = s.heartRate {
                Row(label: "Último batimento", value: "\(hr.bpm) bpm às \(Format.time(hr.at))")
            }
            if let stats = s.heartRateToday {
                Row(label: "Faixa hoje", value: "\(stats.min) a \(stats.max) bpm, média \(stats.avg)")
            }
        }
        .padding(14)
        .card()
    }

    private func chart(_ series: [HeartSample]) -> some View {
        Chart(series, id: \.at) { sample in
            LineMark(x: .value("Hora", sample.at), y: .value("bpm", sample.bpm))
                .interpolationMethod(.monotone)
                .foregroundStyle(.red)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .frame(height: 90)
        .padding(14)
        .card()
    }

    private func updatedLine(_ s: Snapshot) -> some View {
        HStack {
            if let receivedAt = model.receivedAt {
                Text("Atualizado \(Format.relative(receivedAt, now: model.now))")
                    .foregroundStyle(model.isStale ? .orange : .secondary)
            }
            Spacer()
            if let device = s.device {
                Text(device).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 6)
    }
}

private struct SettingsPage: View {
    let model: AppModel
    var onBack: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { onBack() } label: { Label("Voltar", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                Spacer()
                Text("Preferências").font(.headline)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 10) {
                Text("Celular").font(.subheadline.bold())
                HStack {
                    Text("Código").foregroundStyle(.secondary)
                    Text(model.code)
                        .font(.system(.body, design: .monospaced).bold())
                        .textSelection(.enabled)
                    Spacer()
                    Button("Gerar novo") { model.regenerateCode() }
                }
                ForEach(LocalNetwork.ipv4Addresses(), id: \.self) { address in
                    HStack {
                        Text("Endereço").foregroundStyle(.secondary)
                        Text("\(address):\(AppModel.port)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                Text(model.serverStatus).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Stepper(value: Binding(get: { model.stepGoal }, set: { model.stepGoal = $0 }),
                        in: 1000...50000, step: 500) {
                    HStack {
                        Text("Meta de passos")
                        Spacer()
                        Text(Format.integer(model.stepGoal)).monospacedDigit()
                    }
                }
                Toggle("Abrir ao iniciar sessão", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(14)
            .card()
        }
    }
}

private struct Ring<Content: View>: View {
    var progress: Double
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: 74, height: 74)
    }
}

private struct RingLabel: View {
    var symbol: String
    var value: String
    var caption: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 58)
    }
}

private struct Row: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 13))
    }
}

private extension View {
    func card() -> some View {
        background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)).allowsHitTesting(false))
    }
}
