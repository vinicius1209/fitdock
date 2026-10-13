import AppKit
import SwiftUI

/// Painel sem seta que abre logo abaixo do ícone da barra de menus, no estilo do OneMenu.
/// Substitui o NSPopover, que se reposicionava por cima da barra quando o SwiftUI mudava de altura.
@MainActor
final class StatusPanel {
    private let panel: KeyablePanel
    private let hosting: FirstClickHostingView
    private weak var anchor: NSStatusBarButton?
    private var monitors: [Any] = []

    private static let gap: CGFloat = 6
    private static let screenMargin: CGFloat = 8

    init(model: AppModel) {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: PopoverView.width, height: 400),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        // Quase invisível, mas não zero: pixels com alfa 0 deixam o clique atravessar o painel.
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        hosting = FirstClickHostingView(rootView: PopoverView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        hosting.rootView = PopoverView(model: model) { [weak self] size in
            self?.resize(to: size)
        }
    }

    var isShown: Bool { panel.isVisible }

    func toggle(from button: NSStatusBarButton) {
        isShown ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        anchor = button
        resize(to: hosting.fittingSize)
        // Painel "não ativador" vira janela-chave sem ativar o app (o macOS 14+ costuma negar
        // ativação a apps de barra de menus); sem ser chave, o SwiftUI ignora o clique.
        panel.makeKeyAndOrderFront(nil)
        startMonitors()
    }

    func close() {
        panel.orderOut(nil)
        stopMonitors()
    }

    /// Mantém o topo grudado embaixo do ícone; só a altura muda.
    private func resize(to size: CGSize) {
        guard size.height > 0 else { return }
        let width = PopoverView.width
        var origin = NSPoint(x: 0, y: 0)

        if let button = anchor, let buttonWindow = button.window {
            let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = buttonWindow.screen ?? NSScreen.main
            origin.x = buttonFrame.midX - width / 2
            origin.y = buttonFrame.minY - Self.gap - size.height
            if let visible = screen?.visibleFrame {
                origin.x = min(max(origin.x, visible.minX + Self.screenMargin), visible.maxX - width - Self.screenMargin)
            }
        }
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: size.height)), display: true)
    }

    private func startMonitors() {
        stopMonitors()
        // Clique fora (em outro app ou na mesa) fecha o painel.
        // O painel não ativa o app, então os cliques nele também chegam aqui: filtra pela posição.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.containsMouse() else { return }
                self.close()
            }
        }) {
            monitors.append(global)
        }
        // Esc fecha.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.close() }
                return nil
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// O ponteiro está sobre o painel ou sobre o ícone da barra (que já alterna sozinho)?
    private func containsMouse() -> Bool {
        let point = NSEvent.mouseLocation
        if panel.frame.contains(point) { return true }
        if let button = anchor, let window = button.window {
            return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
        }
        return false
    }

    private func stopMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

/// Painel sem borda não vira janela-chave por padrão; sem isso o Stepper e o Toggle não respondem ao teclado.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// O primeiro clique num painel de app inativo vira só "foco" por padrão; aqui ele já aciona o botão.
private final class FirstClickHostingView: NSHostingView<PopoverView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
