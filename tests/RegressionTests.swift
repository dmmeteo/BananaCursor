import AppKit
import Sparkle

enum RegressionFailure: Error { case failed(String) }

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw RegressionFailure.failed(message) }
}

@MainActor
final class RecordingUpdateEngine: UpdateEngine {
    var canCheckForUpdates = true
    var informationChecks = 0
    var installationChecks = 0
    func checkForUpdateInformation() { informationChecks += 1 }
    func checkForUpdates() { installationChecks += 1 }
}

@main
struct RegressionTests {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BananaCursor-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: "BananaCursor-tests-\(UUID().uuidString)")!
        defer { defaults.removeObject(forKey: "automaticUpdateChecks") }

        let original = CursorLibrary(name: "Original", author: "RegressionTest")
        original.identifier = "com.test.\(UUID().uuidString)"
        let oldIdentifier = original.identifier
        let oldURL = directory.appendingPathComponent("\(oldIdentifier).cape")
        original.fileURL = oldURL
        try original.save()
        let oldBytes = try Data(contentsOf: oldURL)
        let appState = AppState(libraryURL: directory)
        let cape = appState.capes.first!
        appState.editCape(cape)
        cape.name = "Renamed"
        appState.markAsChanged()
        let replacement = directory.appendingPathComponent("local.RegressionTest.Renamed.cape")
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try Data("block atomic replacement".utf8).write(to: replacement.appendingPathComponent("blocker"))

        try expect(!appState.saveCape(cape), "A blocked destination must fail to save")
        try expect(try Data(contentsOf: oldURL) == oldBytes, "Failed rename deleted or changed the original cape")
        try expect(cape.identifier == oldIdentifier && cape.fileURL == oldURL, "Failed rename changed identity or URL")
        try expect(appState.isEditing && appState.hasUnsavedChanges && cape.name == "Renamed", "Failed save lost the dirty editor draft")
        try expect(!appState.resolveUnsavedChanges(.cancel), "Cancel approved leaving the editor")
        try expect(!appState.resolveUnsavedChanges(.save), "Failed Save approved Quit/window close")

        let engine = RecordingUpdateEngine()
        let updater = AppUpdater(engine: engine, defaults: defaults) { appState.resolveUnsavedChanges(.save) }
        updater.checkForUpdates()
        updater.foundUpdate(version: "0.2.0", build: "3")
        updater.finishCheck(error: nil)
        updater.installAndRestart()
        try expect(engine.installationChecks == 0 && updater.canInstall, "Failed Save entered the Sparkle install path")
        try expect(try Data(contentsOf: oldURL) == oldBytes, "Install approval changed the original cape after Save failed")

        try FileManager.default.removeItem(at: replacement)
        updater.installAndRestart()
        try expect(engine.installationChecks == 1, "Approved installation did not enter Sparkle exactly once")
        try expect(!appState.isEditing && !appState.hasUnsavedChanges, "Successful Save did not close the editor")
        try expect(FileManager.default.fileExists(atPath: replacement.path) && !FileManager.default.fileExists(atPath: oldURL.path), "Successful rename did not replace the old path")
        try expect(!updater.canTerminate, "The app can quit before the installer is ready")
        var installReply: SPUUserUpdateChoice?
        updater.showReady(toInstallAndRelaunch: { installReply = $0 })
        try expect(installReply == .install && !updater.canTerminate, "Ready-to-install callback granted premature termination")
        updater.showInstallingUpdate(withApplicationTerminated: true, retryTerminatingApplication: {})
        try expect(updater.canTerminate && updater.state == .installing(.exitReady), "Real installing callback did not authorize termination")
        updater.finishCheck(error: nil)
        try expect(updater.state == .installing(.exitReady), "Finished cycle erased the installer handoff")

        let quietEngine = RecordingUpdateEngine()
        let quiet = AppUpdater(engine: quietEngine, defaults: defaults, confirmLeavingEditor: { false })
        quiet.checkQuietly()
        quiet.automaticChecks = false
        quiet.automaticChecks = true
        quiet.foundUpdate(version: "0.2.0", build: "3")
        quiet.finishCheck(error: nil)
        try expect(quiet.state == .idle && quietEngine.installationChecks == 0, "Late quiet result survived switching checks off")
        quiet.automaticChecks = false
        quiet.checkForUpdates()
        quiet.foundUpdate(version: "0.2.0", build: "3")
        quiet.finishCheck(error: nil)
        try expect(quiet.canInstall && quietEngine.informationChecks == 2, "Manual check did not work with automatic checks off")
        quiet.installAndRestart()
        try expect(quietEngine.installationChecks == 0, "Cancel entered the installer")
        var unexpectedReadyReply: SPUUserUpdateChoice?
        quiet.showReady(toInstallAndRelaunch: { unexpectedReadyReply = $0 })
        try expect(unexpectedReadyReply == .skip, "Unapproved installer was not cancelled")
        let failure = NSError(domain: "RegressionTest", code: 7, userInfo: [NSLocalizedDescriptionKey: "Rejected signature"])
        quiet.showUpdaterError(failure, acknowledgement: {})
        quiet.finishCheck(error: failure)
        try expect(!quiet.isInstalling && quiet.canTerminate && quiet.canCheck, "Failure left editing or future checks blocked")
        print("PASS: failed and successful atomic rename, editor Cancel/Save, install approval, real handoff, quiet/manual checks, error recovery")
    }
}
