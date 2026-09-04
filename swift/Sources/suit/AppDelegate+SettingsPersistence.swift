import Cocoa

// The UserDefaults double-entry ledger: loadSettings restores every persisted
// setting at launch, saveSettings writes them all back after any change. The
// two lists MUST mirror each other — a key added to one but not the other
// silently fails to persist or restore. Adding a setting means touching three
// places: the AppDelegate property, its `…Changed` handler (+Appearance or
// +Settings), and both halves here.
extension AppDelegate {
    func loadSettings() {
        let defaults = UserDefaults.standard
        // "hackFontMigrated" is a one-shot marker, not a setting, which is why
        // it has no partner in saveSettings: the first launch after Hack
        // started shipping moves everyone who was still on the old
        // system-monospaced default onto Hack, then latches so a deliberate
        // switch back survives. BundledFonts.resolvedFontName owns the rule.
        let migrated = defaults.bool(forKey: DefaultsKey.hackFontMigrated)
        let fontName = BundledFonts.resolvedFontName(
            persisted: defaults.string(forKey: DefaultsKey.fontName), migrated: migrated)
        let size = defaults.double(forKey: DefaultsKey.fontSize)
        currentFont = NSFont(name: fontName, size: size > 0 ? CGFloat(size) : currentFont.pointSize) ?? currentFont
        if !migrated {
            defaults.set(true, forKey: DefaultsKey.hackFontMigrated)
            // Write the migrated name through immediately rather than waiting
            // for the next settings change, so UserDefaults never disagrees
            // with what the app is actually drawing.
            defaults.set(currentFont.fontName, forKey: DefaultsKey.fontName)
        }
        if defaults.object(forKey: DefaultsKey.textColorR) != nil {
            currentTextColor = NSColor(
                calibratedRed: CGFloat(defaults.double(forKey: DefaultsKey.textColorR)),
                green: CGFloat(defaults.double(forKey: DefaultsKey.textColorG)),
                blue: CGFloat(defaults.double(forKey: DefaultsKey.textColorB)),
                alpha: CGFloat(defaults.double(forKey: DefaultsKey.textColorA))
            )
        }
        if defaults.object(forKey: DefaultsKey.wordWrapEnabled) != nil {
            wordWrapEnabled = defaults.bool(forKey: DefaultsKey.wordWrapEnabled)
        }
        if defaults.object(forKey: DefaultsKey.defaultBgR) != nil {
            defaultTerminalBackground = NSColor(
                calibratedRed: CGFloat(defaults.double(forKey: DefaultsKey.defaultBgR)),
                green: CGFloat(defaults.double(forKey: DefaultsKey.defaultBgG)),
                blue: CGFloat(defaults.double(forKey: DefaultsKey.defaultBgB)),
                alpha: 1
            )
        }
        if let raw = defaults.string(forKey: DefaultsKey.cursorStyle), let style = CursorStyle.from(string: raw) {
            cursorStyle = style
        }
        // Re-validate at load: the shell may have been uninstalled since.
        if let shell = defaults.string(forKey: DefaultsKey.shellPath),
           FileManager.default.isExecutableFile(atPath: shell) {
            shellPath = shell
        }
        if defaults.object(forKey: DefaultsKey.bellFlashEnabled) != nil {
            bellFlashEnabled = defaults.bool(forKey: DefaultsKey.bellFlashEnabled)
        }
        if defaults.object(forKey: DefaultsKey.bellDockBounceEnabled) != nil {
            bellDockBounceEnabled = defaults.bool(forKey: DefaultsKey.bellDockBounceEnabled)
        }
        if defaults.object(forKey: DefaultsKey.taskDoneSoundEnabled) != nil {
            taskDoneSoundEnabled = defaults.bool(forKey: DefaultsKey.taskDoneSoundEnabled)
        }
        if defaults.object(forKey: DefaultsKey.needsInputSoundEnabled) != nil {
            needsInputSoundEnabled = defaults.bool(forKey: DefaultsKey.needsInputSoundEnabled)
        }
        if let name = defaults.string(forKey: DefaultsKey.taskDoneSoundName) {
            taskDoneSoundName = name
        }
        if let name = defaults.string(forKey: DefaultsKey.needsInputSoundName) {
            needsInputSoundName = name
        }
        if defaults.object(forKey: DefaultsKey.goalPrependProvenanceEnabled) != nil {
            goalPrependProvenanceEnabled = defaults.bool(forKey: DefaultsKey.goalPrependProvenanceEnabled)
        }
        if let args = defaults.string(forKey: DefaultsKey.claudeSessionArgs) {
            claudeSessionArgs = args
        }
        if defaults.object(forKey: DefaultsKey.taskIsolateByDefault) != nil {
            taskIsolateByDefault = defaults.bool(forKey: DefaultsKey.taskIsolateByDefault)
        }
        // Cost budget guardrails.
        if defaults.object(forKey: DefaultsKey.budgetSessionCap) != nil {
            budgetSessionCap = defaults.double(forKey: DefaultsKey.budgetSessionCap)
        }
        if defaults.object(forKey: DefaultsKey.budgetTaskCap) != nil {
            budgetTaskCap = defaults.double(forKey: DefaultsKey.budgetTaskCap)
        }
        budgetAutoInterrupt = defaults.bool(forKey: DefaultsKey.budgetAutoInterrupt)
        if let raw = defaults.dictionary(forKey: DefaultsKey.budgetPerSession) {
            budgetPerSession = raw.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(currentFont.fontName, forKey: DefaultsKey.fontName)
        defaults.set(Double(currentFont.pointSize), forKey: DefaultsKey.fontSize)
        let color = currentTextColor.usingColorSpace(.deviceRGB) ?? currentTextColor
        defaults.set(Double(color.redComponent), forKey: DefaultsKey.textColorR)
        defaults.set(Double(color.greenComponent), forKey: DefaultsKey.textColorG)
        defaults.set(Double(color.blueComponent), forKey: DefaultsKey.textColorB)
        defaults.set(Double(color.alphaComponent), forKey: DefaultsKey.textColorA)
        defaults.set(wordWrapEnabled, forKey: DefaultsKey.wordWrapEnabled)
        let background = defaultTerminalBackground.usingColorSpace(.deviceRGB) ?? defaultTerminalBackground
        defaults.set(Double(background.redComponent), forKey: DefaultsKey.defaultBgR)
        defaults.set(Double(background.greenComponent), forKey: DefaultsKey.defaultBgG)
        defaults.set(Double(background.blueComponent), forKey: DefaultsKey.defaultBgB)
        defaults.set(cursorStyle.persistedName, forKey: DefaultsKey.cursorStyle)
        defaults.set(shellPath, forKey: DefaultsKey.shellPath)
        defaults.set(bellFlashEnabled, forKey: DefaultsKey.bellFlashEnabled)
        defaults.set(bellDockBounceEnabled, forKey: DefaultsKey.bellDockBounceEnabled)
        defaults.set(taskDoneSoundEnabled, forKey: DefaultsKey.taskDoneSoundEnabled)
        defaults.set(needsInputSoundEnabled, forKey: DefaultsKey.needsInputSoundEnabled)
        defaults.set(taskDoneSoundName, forKey: DefaultsKey.taskDoneSoundName)
        defaults.set(needsInputSoundName, forKey: DefaultsKey.needsInputSoundName)
        defaults.set(goalPrependProvenanceEnabled, forKey: DefaultsKey.goalPrependProvenanceEnabled)
        defaults.set(claudeSessionArgs, forKey: DefaultsKey.claudeSessionArgs)
        defaults.set(taskIsolateByDefault, forKey: DefaultsKey.taskIsolateByDefault)
        defaults.set(budgetSessionCap, forKey: DefaultsKey.budgetSessionCap)
        defaults.set(budgetTaskCap, forKey: DefaultsKey.budgetTaskCap)
        defaults.set(budgetAutoInterrupt, forKey: DefaultsKey.budgetAutoInterrupt)
        defaults.set(budgetPerSession, forKey: DefaultsKey.budgetPerSession)
    }
}

// The inverse of SwiftTerm's CursorStyle.from(string:), for UserDefaults.
extension CursorStyle {
    var persistedName: String {
        switch self {
        case .blinkBlock: return "blinkBlock"
        case .steadyBlock: return "steadyBlock"
        case .blinkUnderline: return "blinkUnderline"
        case .steadyUnderline: return "steadyUnderline"
        case .blinkBar: return "blinkBar"
        case .steadyBar: return "steadyBar"
        }
    }
}
