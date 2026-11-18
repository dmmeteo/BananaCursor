import AppKit
import Observation
import Sparkle

@MainActor
protocol UpdateEngine: AnyObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdateInformation()
    func checkForUpdates()
}

extension SPUUpdater: UpdateEngine {}

enum UpdateState: Equatable {
    case unavailable(String)
    case idle
    case checking
    case available(version: String, build: String)
    case installing(InstallationStage)
    case failed(String)

    enum InstallationStage: Equatable {
        case checking, downloading, extracting, awaitingInstaller, exitReady
    }
}

@Observable @MainActor
final class AppUpdater: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    static let publicKey = "8SLS/2Gi3wYdSD1AAVGwfCATxnmkbrKCR8v2n/5xZS8="

    private(set) var state: UpdateState = .unavailable("Updates have not started.")
    var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: "automaticUpdateChecks")
            if !automaticChecks, case .quiet = intent {
                suppressQuietResult = true
                state = .idle
            }
        }
    }

    private enum CheckIntent { case quiet, manual, install }
    private var intent: CheckIntent?
    private var candidate: (version: String, build: String)?
    private var updater: (any UpdateEngine)?
    private var timer: Timer?
    private var suppressQuietResult = false
    private let defaults: UserDefaults
    private let confirmLeavingEditor: () -> Bool

    init(engine: (any UpdateEngine)? = nil, defaults: UserDefaults = .standard,
         confirmLeavingEditor: @escaping () -> Bool = { AppState.shared.confirmLeavingEditor() }) {
        self.defaults = defaults
        self.confirmLeavingEditor = confirmLeavingEditor
        self.updater = engine
        automaticChecks = defaults.object(forKey: "automaticUpdateChecks") as? Bool ?? true
        super.init()
        if engine != nil { state = .idle }
    }

    var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }

    var canTerminate: Bool { !isInstalling || state == .installing(.exitReady) }
    var canCheck: Bool { intent == nil && updater?.canCheckForUpdates == true && !isInstalling }
    var canInstall: Bool {
        if case .available = state { return canCheck }
        return false
    }

    var status: String {
        switch state {
        case .unavailable(let reason), .failed(let reason): return reason
        case .idle: return "No newer version is available."
        case .checking: return "Checking for updates…"
        case .available(let version, _): return "BananaCursor \(version) is available."
        case .installing(let stage):
            switch stage {
            case .checking: return "Preparing update…"
            case .downloading: return "Downloading update…"
            case .extracting: return "Verifying update…"
            case .awaitingInstaller, .exitReady: return "Installing and restarting…"
            }
        }
    }

    func start() {
        guard updater == nil else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              info["SUPublicEDKey"] as? String == Self.publicKey,
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              (info["SUSignedFeedFailureExpirationInterval"] as? NSNumber)?.doubleValue == 0 else {
            state = .unavailable("Update configuration is invalid. Download a fresh copy from Releases.")
            return
        }
        let controller = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        controller.automaticallyChecksForUpdates = false
        controller.automaticallyDownloadsUpdates = false
        controller.sendsSystemProfile = false
        do {
            try controller.start()
            updater = controller
            state = .idle
            timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkQuietly() }
            }
            DispatchQueue.main.async { [weak self] in self?.checkQuietly() }
        } catch { state = .unavailable(error.localizedDescription) }
    }

    func checkForUpdates() { check(intent: .manual) }
    func checkQuietly() {
        guard automaticChecks else { return }
        check(intent: .quiet)
    }

    private func check(intent: CheckIntent) {
        guard canCheck, let updater else { return }
        self.intent = intent
        suppressQuietResult = false
        candidate = nil
        state = .checking
        updater.checkForUpdateInformation()
    }

    func installAndRestart() {
        guard canInstall, let updater,
              confirmLeavingEditor() else { return }
        intent = .install
        candidate = nil
        state = .installing(.checking)
        updater.checkForUpdates()
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        state == .installing(.awaitingInstaller) || state == .installing(.exitReady)
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard !item.isInformationOnlyUpdate,
              item.signingValidationStatus == .succeeded,
              item.displayVersionString.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              let url = item.fileURL, url.scheme == "https", url.pathExtension.lowercased() == "zip",
              let build = UInt64(item.versionString), let installed = UInt64(currentBuild), build > installed,
              SUStandardVersionComparator.default.compareVersion(item.displayVersionString, toVersion: currentVersion) == .orderedDescending,
              let minimumOS = item.minimumSystemVersion, !minimumOS.isEmpty,
              item.minimumOperatingSystemVersionIsOK else {
            throw NSError(domain: "BananaCursor.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "No compatible newer update is available."])
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundUpdate(version: item.displayVersionString, build: item.versionString)
    }

    func foundUpdate(version: String, build: String) {
        candidate = (version, build)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        finishCheck(error: error)
    }

    func finishCheck(error: Error?) {
        let finishedIntent = intent
        intent = nil
        if state == .installing(.exitReady) { return }
        if isInstalling {
            state = .failed(error?.localizedDescription ?? "The update stopped. Try again.")
        } else if case .quiet = finishedIntent, suppressQuietResult {
            state = .idle
        } else if let error, (error as NSError).code != SUError.noUpdateError.rawValue {
            state = .failed(error.localizedDescription)
        } else if let candidate {
            state = .available(version: candidate.version, build: candidate.build)
        } else { state = .idle }
        candidate = nil
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state updateState: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard case .install = intent, isInstalling else { reply(.skip); return }
        state = .installing(updateState.stage == .installing ? .awaitingInstaller : .downloading)
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        if isInstalling { state = .failed("The update is no longer available. Check again.") }
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state = .failed(error.localizedDescription)
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { state = .installing(.downloading) }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { state = .installing(.extracting) }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard case .install = intent, isInstalling else { reply(.skip); return }
        state = .installing(.awaitingInstaller)
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        guard state == .installing(.awaitingInstaller) else { return }
        state = .installing(.exitReady)
        if !applicationTerminated {
            // Sparkle's earlier quit request may have been rejected while preparing.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
    func showUpdateInFocus() {}
}
