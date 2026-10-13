import Foundation
import Observation

struct HeartSample: Codable, Hashable {
    var at: Date
    var bpm: Int
}

struct HeartStats: Codable, Hashable {
    var min: Int
    var max: Int
    var avg: Int
}

/// O que o celular envia a cada sincronização. Campos opcionais ficam nulos quando
/// o Health Connect não tem o dado ou a permissão não foi dada.
struct Snapshot: Codable {
    var version: Int
    var device: String?
    var generatedAt: Date
    var steps: Int?
    var activeCaloriesKcal: Double?
    var totalCaloriesKcal: Double?
    var distanceMeters: Double?
    var heartRate: HeartSample?
    var heartRateToday: HeartStats?
    var heartRateSeries: [HeartSample]?
}

private struct StoredState: Codable {
    var snapshot: Snapshot?
    var receivedAt: Date?
}

private struct StoredConfig: Codable {
    var code: String
    var stepGoal: Int?
}

enum JSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

@MainActor
@Observable
final class AppModel {
    static let port: UInt16 = 47800
    /// Depois disso sem envio, os números ficam apagados para não fingir que o dado é atual.
    static let staleAfter: TimeInterval = 2 * 60 * 60
    /// Meta padrão do Samsung Health.
    static let defaultStepGoal = 6000

    var snapshot: Snapshot?
    var receivedAt: Date?
    var code: String
    var stepGoal: Int {
        didSet { saveConfig() }
    }
    var serverStatus = "Iniciando…"
    var now = Date()

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onCodeChange: ((String) -> Void)?
    @ObservationIgnored private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("FitDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
           let config = try? JSON.decoder.decode(StoredConfig.self, from: data) {
            code = config.code
            stepGoal = config.stepGoal ?? AppModel.defaultStepGoal
        } else {
            code = AppModel.makeCode()
            stepGoal = AppModel.defaultStepGoal
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("state.json")),
           let state = try? JSON.decoder.decode(StoredState.self, from: data) {
            snapshot = state.snapshot
            receivedAt = state.receivedAt
        }
        saveConfig()
    }

    var isStale: Bool {
        guard let receivedAt else { return true }
        return now.timeIntervalSince(receivedAt) > AppModel.staleAfter
    }

    func accept(_ s: Snapshot) {
        snapshot = s
        receivedAt = Date()
        now = Date()
        save(StoredState(snapshot: snapshot, receivedAt: receivedAt), to: "state.json")
        onChange?()
    }

    func regenerateCode() {
        code = AppModel.makeCode()
        saveConfig()
        onCodeChange?(code)
    }

    func tick() {
        now = Date()
        onChange?()
    }

    private func saveConfig() {
        save(StoredConfig(code: code, stepGoal: stepGoal), to: "config.json")
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSON.encoder.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    private static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
