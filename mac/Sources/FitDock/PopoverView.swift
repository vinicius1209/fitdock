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
                SettingsPage(model: model) {
                    withAnimation(.snappy(duration: 0.25)) { showingSettings = false }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                SummaryPage(model: model)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                footer.reveal(4, trigger: model.panelOpenCount)
            }
        }
        .padding(12)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .onChange(of: model.panelOpenCount) { showingSettings = false }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showingSettings = true }
            } label: {
                Label("Preferências", systemImage: "gearshape")
            }
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Label("Sair", systemImage: "power")
            }
        }
        .buttonStyle(HoverButtonStyle())
        .font(.system(size: 13, weight: .medium))
        .padding(6)
        .card()
    }
}

// MARK: - Resumo

private struct SummaryPage: View {
    let model: AppModel

    var body: some View {
        let trigger = model.panelOpenCount
        if let s = model.snapshot {
            VStack(spacing: 10) {
                rings(s, trigger: trigger).reveal(0, trigger: trigger)
                details(s).reveal(1, trigger: trigger)
                if let series = s.heartRateSeries, series.count > 1 {
                    HeartChart(series: series, trigger: trigger).reveal(2, trigger: trigger)
                }
                StatusLine(model: model).reveal(3, trigger: trigger)
            }
            .opacity(model.isStale ? 0.65 : 1)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Aguardando o celular", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.headline)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("Abra o FitDock no celular, informe o código \(model.code) e toque em Sincronizar agora.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .reveal(0, trigger: trigger)
        }
    }

    private func rings(_ s: Snapshot, trigger: Int) -> some View {
        let steps = s.steps ?? 0
        let goal = max(model.stepGoal, 1)
        let stepProgress = Double(steps) / Double(goal)
        let active = s.activeCaloriesKcal ?? 0
        return HStack(spacing: 0) {
            AnimatedRing(progress: stepProgress, colors: [.green, .mint], trigger: trigger) {
                RingLabel(symbol: stepProgress >= 1 ? "checkmark.circle.fill" : "figure.walk",
                          value: s.steps.map(Format.compactSteps) ?? "--",
                          caption: "passos")
            }
            .help("\(Format.integer(steps)) de \(Format.integer(model.stepGoal)) passos (\(Int((stepProgress * 100).rounded()))% da meta)")
            Spacer()
            HeartPulse(sample: s.heartRate, now: model.now)
            Spacer()
            AnimatedRing(progress: active / AppModel.activeCaloriesReference, colors: [.orange, .yellow], trigger: trigger) {
                RingLabel(symbol: "flame.fill",
                          value: s.activeCaloriesKcal.map { "\(Int($0.rounded()))" } ?? "--",
                          caption: "kcal ativas")
            }
            .help("Calorias gastas em atividade hoje. O anel enche em \(Int(AppModel.activeCaloriesReference)) kcal.")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .card()
    }

    private func details(_ s: Snapshot) -> some View {
        let steps = s.steps ?? 0
        let remaining = max(model.stepGoal - steps, 0)
        return VStack(spacing: 2) {
            Row(symbol: "target", tint: .green, label: "Meta",
                value: remaining == 0 ? "batida" : "faltam \(Format.integer(remaining))")
            Row(symbol: "map", tint: .blue, label: "Distância",
                value: s.distanceMeters.map(Format.distance) ?? "sem dado")
            Row(symbol: "bolt.heart", tint: .pink, label: "Calorias totais",
                value: s.totalCaloriesKcal.map(Format.kcal) ?? "sem dado")
            if let hr = s.heartRate {
                Row(symbol: "heart.text.square", tint: .red, label: "Último batimento",
                    value: "\(hr.bpm) bpm às \(Format.time(hr.at))")
            }
            if let stats = s.heartRateToday {
                Row(symbol: "waveform.path.ecg", tint: .red, label: "Faixa hoje",
                    value: "\(stats.min) a \(stats.max) bpm, média \(stats.avg)")
            }
        }
        .padding(8)
        .card()
    }
}

/// "Atualizado há X" + botão que pede um envio ao celular.
private struct StatusLine: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    message(now: now)
                        .contentTransition(.numericText())
                    if let device = model.snapshot?.device {
                        Text(device).foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                Spacer()
                RefreshButton(waiting: model.refreshRequestedAt != nil) { model.requestRefresh() }
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func message(now: Date) -> some View {
        if let requestedAt = model.refreshRequestedAt {
            // Previsão pelo intervalo combinado; se já passou, conta a partir do pedido.
            let expected = max(model.expectedNextSync ?? requestedAt, requestedAt)
            let remaining = Int(expected.timeIntervalSince(now).rounded())
            let waited = now.timeIntervalSince(requestedAt)
            if remaining > 0 {
                Text("Pedido enviado, o celular confere em \(Format.duration(remaining))")
                    .foregroundStyle(.secondary)
            } else if waited < TimeInterval(AppModel.relaxedSyncSeconds + 120) {
                Text("Esperando o celular…").foregroundStyle(.secondary)
            } else {
                Text("O celular ainda não respondeu. Pode estar fora da Wi-Fi ou poupando bateria.")
                    .foregroundStyle(.orange)
            }
        } else if let receivedAt = model.receivedAt {
            Text("Atualizado \(Format.relative(receivedAt, now: now))")
                .foregroundStyle(model.isStale ? .orange : .secondary)
        }
    }
}

private struct RefreshButton: View {
    var waiting: Bool
    var action: () -> Void
    @State private var spin = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(HoverButtonStyle(shape: .circle))
        .help("Pedir ao celular um envio agora")
        .disabled(waiting)
        .onChange(of: waiting, initial: true) { _, isWaiting in
            if isWaiting {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
            } else {
                withAnimation(.spring(response: 0.4)) { spin = false }
            }
        }
    }
}

// MARK: - Batimento

/// Coração que bate no ritmo do último bpm medido, com ondas saindo a cada batida.
/// Fica parado quando a medição tem mais de 90 min (o Health Connect costuma atrasar 30 a 60 min),
/// para não fingir que é ao vivo.
private struct HeartPulse: View {
    var sample: HeartSample?
    var now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFresh: Bool {
        guard let sample else { return false }
        return now.timeIntervalSince(sample.at) < 90 * 60
    }

    var body: some View {
        let animate = isFresh && !reduceMotion
        TimelineView(.animation(paused: !animate)) { context in
            let bpm = Double(sample?.bpm ?? 60)
            let phase = animate
                ? (context.date.timeIntervalSinceReferenceDate * bpm / 60).truncatingRemainder(dividingBy: 1)
                : 0.5
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.red.opacity(isFresh ? 0.16 : 0.06), .clear],
                                         center: .center, startRadius: 0, endRadius: 37))
                if animate {
                    Circle()
                        .stroke(Color.red.opacity(0.45 * (1 - phase)), lineWidth: 2)
                        .scaleEffect(0.5 + 0.5 * phase)
                }
                VStack(spacing: 1) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isFresh ? Color.red : Color.secondary)
                        .scaleEffect(1 + 0.28 * Self.lubDub(phase))
                    Text(sample.map { "\($0.bpm)" } ?? "--")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("bpm")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 74, height: 74)
        }
        .help(sample.map { "Medido às \(Format.time($0.at)) (\(Format.relative($0.at, now: now)))" } ?? "Sem batimentos nas últimas 24 horas")
    }

    /// Duas batidas por ciclo ("tum-tum"), como um batimento de verdade.
    static func lubDub(_ x: Double) -> Double {
        exp(-pow((x - 0.06) / 0.035, 2)) + 0.6 * exp(-pow((x - 0.24) / 0.04, 2))
    }
}

private struct HeartChart: View {
    var series: [HeartSample]
    var trigger: Int
    @State private var reveal: CGFloat = 0

    var body: some View {
        let last = series.last!
        Chart {
            ForEach(series, id: \.at) { sample in
                AreaMark(x: .value("Hora", sample.at),
                         yStart: .value("base", (series.map(\.bpm).min() ?? 0) - 5),
                         yEnd: .value("bpm", sample.bpm))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [.red.opacity(0.28), .red.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Hora", sample.at), y: .value("bpm", sample.bpm))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            PointMark(x: .value("Hora", last.at), y: .value("bpm", last.bpm))
                .foregroundStyle(.red)
                .symbolSize(30)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        // Folga nas pontas para o rótulo da última hora não ser cortado.
        .chartXScale(range: .plotDimension(padding: 14))
        .frame(height: 90)
        // A linha "se desenha" da esquerda para a direita a cada abertura.
        .mask(alignment: .leading) {
            GeometryReader { geo in
                Rectangle().frame(width: geo.size.width * reveal)
            }
        }
        .padding(14)
        .card()
        .onChange(of: trigger, initial: true) {
            reveal = 0
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { reveal = 1 }
        }
    }
}

// MARK: - Preferências

private struct SettingsPage: View {
    let model: AppModel
    var onBack: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { onBack() } label: { Label("Voltar", systemImage: "chevron.left") }
                    .buttonStyle(HoverButtonStyle())
                Spacer()
                Text("Preferências").font(.headline)
                Spacer()
                Color.clear.frame(width: 70, height: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Celular").font(.subheadline.bold())
                HStack {
                    Text("Código").foregroundStyle(.secondary)
                    Text(model.code)
                        .font(.system(.body, design: .monospaced).bold())
                        .textSelection(.enabled)
                        .contentTransition(.numericText())
                    Spacer()
                    Button("Gerar novo") { withAnimation { model.regenerateCode() } }
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
                Stepper(value: Binding(get: { model.stepGoal }, set: { value in withAnimation { model.stepGoal = value } }),
                        in: 1000...50000, step: 500) {
                    HStack {
                        Text("Meta de passos")
                        Spacer()
                        Text(Format.integer(model.stepGoal))
                            .monospacedDigit()
                            .contentTransition(.numericText())
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

// MARK: - Peças

/// Anel que enche com mola a cada abertura do painel e quando o valor muda.
private struct AnimatedRing<Content: View>: View {
    var progress: Double
    var colors: [Color]
    var trigger: Int
    @ViewBuilder var content: Content
    @State private var shown: Double = 0

    var body: some View {
        let clamped = min(max(shown, 0), 1)
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 7)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(AngularGradient(colors: colors, center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(clamped, 0.01))),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: colors[0].opacity(progress >= 1 ? 0.6 : 0), radius: 6)
            content
        }
        .frame(width: 74, height: 74)
        .onChange(of: trigger, initial: true) {
            shown = 0
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.12)) { shown = progress }
        }
        .onChange(of: progress) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { shown = progress }
        }
    }
}

private struct RingLabel: View {
    var symbol: String
    var value: String
    var caption: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
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
    var symbol: String
    var tint: Color
    var label: String
    var value: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .scaleEffect(hovering ? 1.15 : 1)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
    }
}

/// Botão discreto com fundo que aparece no hover, no estilo dos menus do macOS.
private struct HoverButtonStyle: ButtonStyle {
    enum Shape { case capsule, circle }
    var shape: Shape = .capsule

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, shape: shape)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let shape: Shape
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, shape == .capsule ? 10 : 0)
                .padding(.vertical, shape == .capsule ? 6 : 0)
                .background {
                    let fill = Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering && isEnabled ? 0.08 : 0))
                    if shape == .circle { Circle().fill(fill) } else { Capsule().fill(fill) }
                }
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.6)
                .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// Entrada em cascata: cada cartão aparece um pouco depois do anterior.
private struct Reveal: ViewModifier {
    let index: Int
    let trigger: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
            .onChange(of: trigger, initial: true) {
                if reduceMotion { shown = true; return }
                var hide = Transaction()
                hide.disablesAnimations = true
                withTransaction(hide) { shown = false }
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.05 * Double(index))) {
                        shown = true
                    }
                }
            }
    }
}

private extension View {
    func reveal(_ index: Int, trigger: Int) -> some View {
        modifier(Reveal(index: index, trigger: trigger))
    }

    func card() -> some View {
        background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // A borda é só enfeite: sem allowsHitTesting(false) ela engole os cliques dos botões.
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.5))
                .allowsHitTesting(false))
    }
}
