import Combine
import Foundation

@MainActor final class SettingsStore: ObservableObject {
    @Published private(set) var configuration: RugConfiguration
    @Published var finderStatus = "Finder is not connected. Manual mounds are available."
    @Published var runtimeStatus = "Ready"
    @Published var persistenceError: String?
    var onChange: ((RugConfiguration, RugConfiguration) -> Void)?
    private let defaults: UserDefaults
    private let key = "DesktopRug.configuration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do {
                var config = try JSONDecoder().decode(RugConfiguration.self, from: data)
                config.sanitize()
                configuration = config
            } catch {
                configuration = RugConfiguration()
                persistenceError = "Saved settings could not be read: \(error.localizedDescription)"
            }
        } else { configuration = RugConfiguration() }
    }

    func update(_ change: (inout RugConfiguration) -> Void) {
        let previous = configuration
        var next = previous
        change(&next); next.sanitize()
        guard next != previous else { return }
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: key)
            persistenceError = nil
        } catch { persistenceError = "Settings could not be saved: \(error.localizedDescription)" }
        configuration = next
        onChange?(previous, next)
    }
}
