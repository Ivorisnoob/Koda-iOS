import KodaCore
import SwiftUI

/// The listener's preferences, each saved the moment it changes.
@MainActor
@Observable
final class AppSettings {
    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: Self { self }
        var title: String {
            switch self {
            case .system: "Automatic"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum LyricsSize: String, CaseIterable, Identifiable {
        case small, standard, large

        var id: Self { self }
        var title: String {
            switch self {
            case .small: "Small"
            case .standard: "Default"
            case .large: "Large"
            }
        }
        /// Point size of a sung line; backing vocals are drawn at 70% of it.
        var fontSize: CGFloat {
            switch self {
            case .small: 25
            case .standard: 30
            case .large: 35
            }
        }
    }

    private let defaults = UserDefaults.standard

    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: Keys.theme) } }
    /// The cover's colours drift behind Now Playing; off, they hold still.
    var animatesPlayerBackground: Bool { didSet { defaults.set(animatesPlayerBackground, forKey: Keys.animatedBackground) } }
    /// Every lyrics service, best first; the order decides which answer wins.
    var lyricsSourceOrder: [LyricsSource] { didSet { defaults.set(lyricsSourceOrder.map(\.rawValue), forKey: Keys.lyricsOrder) } }
    var disabledLyricsSources: Set<LyricsSource> { didSet { defaults.set(disabledLyricsSources.map(\.rawValue), forKey: Keys.lyricsDisabled) } }
    /// Words rise as they start and held notes swell.
    var lyricsMotion: Bool { didSet { defaults.set(lyricsMotion, forKey: Keys.lyricsMotion) } }
    var lyricsSize: LyricsSize { didSet { defaults.set(lyricsSize.rawValue, forKey: Keys.lyricsSize) } }
    var showsBackingVocals: Bool { didSet { defaults.set(showsBackingVocals, forKey: Keys.backingVocals) } }
    /// The second singer of a duet on the right; off, every line sits on the left.
    var duetSides: Bool { didSet { defaults.set(duetSides, forKey: Keys.duetSides) } }
    /// Off, nothing played is added to history, Quick picks or stats.
    var savesListeningHistory: Bool { didSet { defaults.set(savesListeningHistory, forKey: Keys.listeningHistory) } }
    var savesSearchHistory: Bool { didSet { defaults.set(savesSearchHistory, forKey: Keys.searchHistory) } }

    private enum Keys {
        static let theme = "koda.theme"
        static let animatedBackground = "koda.player.animatedBackground"
        static let lyricsOrder = "koda.lyrics.order"
        static let lyricsDisabled = "koda.lyrics.disabled"
        static let lyricsMotion = "koda.lyrics.motion"
        static let lyricsSize = "koda.lyrics.size"
        static let backingVocals = "koda.lyrics.backingVocals"
        static let duetSides = "koda.lyrics.duetSides"
        static let listeningHistory = "koda.history.listening"
        static let searchHistory = "koda.history.search"
    }

    init() {
        let d = UserDefaults.standard
        theme = d.string(forKey: Keys.theme).flatMap(Theme.init(rawValue:)) ?? .system
        animatesPlayerBackground = d.object(forKey: Keys.animatedBackground) as? Bool ?? true
        // Services added in a later version join at the end of a saved order.
        let saved = (d.stringArray(forKey: Keys.lyricsOrder) ?? []).compactMap(LyricsSource.init(rawValue:))
        lyricsSourceOrder = saved + LyricsSource.allCases.filter { !saved.contains($0) }
        disabledLyricsSources = Set((d.stringArray(forKey: Keys.lyricsDisabled) ?? []).compactMap(LyricsSource.init(rawValue:)))
        lyricsMotion = d.object(forKey: Keys.lyricsMotion) as? Bool ?? true
        lyricsSize = d.string(forKey: Keys.lyricsSize).flatMap(LyricsSize.init(rawValue:)) ?? .standard
        showsBackingVocals = d.object(forKey: Keys.backingVocals) as? Bool ?? true
        duetSides = d.object(forKey: Keys.duetSides) as? Bool ?? true
        savesListeningHistory = d.object(forKey: Keys.listeningHistory) as? Bool ?? true
        savesSearchHistory = d.object(forKey: Keys.searchHistory) as? Bool ?? true
    }

    /// The services to ask, best first.
    var lyricsSources: [LyricsSource] { lyricsSourceOrder.filter { !disabledLyricsSources.contains($0) } }

    func isEnabled(_ source: LyricsSource) -> Bool { !disabledLyricsSources.contains(source) }

    /// The last enabled service cannot be turned off; lyrics need somewhere to come from.
    func setEnabled(_ source: LyricsSource, _ on: Bool) {
        if on {
            disabledLyricsSources.remove(source)
        } else if lyricsSources.count > 1 {
            disabledLyricsSources.insert(source)
        }
    }
}
