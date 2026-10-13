import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var panel: StatusPanel!
    private var server: SnapshotServer!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel(_:))

        panel = StatusPanel(model: model)

        let model = self.model
        server = SnapshotServer(
            port: AppModel.port,
            token: model.code,
            onSnapshot: { snapshot in Task { @MainActor in model.accept(snapshot) } },
            onStatus: { status in Task { @MainActor in model.serverStatus = status } }
        )
        server.start()

        model.onChange = { [weak self] in self?.updateStatusTitle() }
        model.onCodeChange = { [server] code in server?.setToken(code) }
        updateStatusTitle()

        // Atualiza o "há X min" e apaga os números quando o dado envelhece.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in model.tick() }
        }
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if !panel.isShown { model.now = Date() }
        panel.toggle(from: sender)
    }

    /// Texto da barra de menus: passos e último batimento, com ícones SF Symbols.
    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        let snapshot = model.snapshot
        let color: NSColor = model.isStale ? .secondaryLabelColor : .labelColor
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let title = NSMutableAttributedString()
        func symbol(_ name: String) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return }
            image.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = image
            let attributed = NSMutableAttributedString(attachment: attachment)
            attributed.addAttribute(.baselineOffset, value: -1, range: NSRange(location: 0, length: attributed.length))
            title.append(attributed)
        }
        func text(_ value: String) {
            title.append(NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color]))
        }

        symbol("figure.walk")
        text(" \(snapshot?.steps.map(Format.integer) ?? "--")   ")
        symbol("heart.fill")
        text(" \(snapshot?.heartRate.map { "\($0.bpm)" } ?? "--")")

        button.attributedTitle = title
        button.toolTip = model.receivedAt.map { "FitDock · atualizado \(Format.relative($0, now: model.now))" } ?? "FitDock"
    }
}

let arguments = CommandLine.arguments
if arguments.count == 4, arguments[1] == "--render-icon" {
    // Uso: FitDock --render-icon <arquivo.png> <tamanho>
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let ok = DockIcon.writePNG(to: arguments[2], size: Int(arguments[3]) ?? 1024)
        exit(ok ? 0 : 1)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Só barra de menus: sem ícone no Dock.
    app.setActivationPolicy(.accessory)
    app.run()
}
