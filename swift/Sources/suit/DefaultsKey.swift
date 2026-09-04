import Foundation

// Every UserDefaults key the app used to type by hand, spelled once, so a key
// is a symbol and a typo is a compile error rather than a setting that silently
// never persists or never restores. The settings-window values are loaded and
// saved together by AppDelegate+SettingsPersistence, whose two halves must both
// name every key in the first group; the window and sidebar keys are read where
// the view is built and written where the user changes them.
//
// A few keys stay beside their owner because a standalone harness compiles
// that file without this one: FirstRunGuide.shownDefaultsKey,
// ActivityRecorder.lastDigestDayKey, StateRestoration.defaultsKey, and the two
// view-local ones (GitView.commitMessageHeightKey, OpsLogView.kindFilterKey).
enum DefaultsKey {
    // MARK: Settings window (AppDelegate+SettingsPersistence)

    static let fontName = "fontName"
    static let fontSize = "fontSize"
    // A one-shot migration marker, not a setting — see loadSettings.
    static let hackFontMigrated = "hackFontMigrated"
    static let textColorR = "textColorR"
    static let textColorG = "textColorG"
    static let textColorB = "textColorB"
    static let textColorA = "textColorA"
    static let wordWrapEnabled = "wordWrapEnabled"
    static let defaultBgR = "defaultBgR"
    static let defaultBgG = "defaultBgG"
    static let defaultBgB = "defaultBgB"
    static let cursorStyle = "cursorStyle"
    static let shellPath = "shellPath"
    static let bellFlashEnabled = "bellFlashEnabled"
    static let bellDockBounceEnabled = "bellDockBounceEnabled"
    static let taskDoneSoundEnabled = "taskDoneSoundEnabled"
    static let needsInputSoundEnabled = "needsInputSoundEnabled"
    static let taskDoneSoundName = "taskDoneSoundName"
    static let needsInputSoundName = "needsInputSoundName"
    static let goalPrependProvenanceEnabled = "goalPrependProvenanceEnabled"
    static let claudeSessionArgs = "claudeSessionArgs"
    static let taskIsolateByDefault = "taskIsolateByDefault"
    static let budgetSessionCap = "budgetSessionCap"
    static let budgetTaskCap = "budgetTaskCap"
    static let budgetAutoInterrupt = "budgetAutoInterrupt"
    static let budgetPerSession = "budgetPerSession"

    // MARK: Windows (AppDelegate)

    // Where a new window's first shell starts.
    static let lastWorkingDirectory = "lastWorkingDirectory"

    // MARK: Sidebar (TerminalWindowController, SidebarView)

    static let sidebarVisible = "sidebarVisible"
    static let sidebarWidth = "sidebarWidth"
    static let sidebarTab = "sidebarTab"
    // The pinned project root, one key across windows.
    static let sidebarPinnedRoot = "sidebarPinnedRoot"

    // MARK: Search tab (SearchView)

    static let searchResultsFlat = "searchResultsFlat"
    static let searchReplaceExpanded = "searchReplaceExpanded"
    static let searchDetailsExpanded = "searchDetailsExpanded"
}
