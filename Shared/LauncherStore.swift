import Foundation
import WidgetKit

/// Where this instance reads and writes launcher data.
enum StorageSource: Equatable {
    /// Injected suite (unit tests).
    case injected
    /// The shared App Group suite — production app and widgets. Unavailable
    /// on a free personal team (F-1); kept first in the chain so paying for
    /// membership re-enables it with no code change.
    case appGroup
    /// Shared keychain item reached through the keychain-access-groups
    /// entitlement (F-2) — the free-team substitute for an App Group. The
    /// app and the widget read/write the SAME item, so both see one dataset.
    case keychain
    /// No shared channel resolved; fell back to `.standard`. Data stays
    /// local to this process and the other target cannot see it. Surfaced
    /// via `storageSource` and a console log so the degraded state is never
    /// silent (K-13 / G1-5).
    case standardFallback
}

/// Read/write seam for the shared keychain, in the same injection style as
/// `resolveStorage`'s parameters: production supplies `SecKeychainStore`;
/// tests substitute in-memory or always-failing channels.
protocol LauncherKeychainStore: AnyObject {
    /// True when the keychain actually ANSWERS queries for this item (the
    /// item itself may be absent). Resolution probes this once so an
    /// un-entitled keychain degrades loudly instead of failing silently on
    /// every later read/write (K-13 / G1-5).
    func isAvailable() -> Bool
    /// Stored blob, or nil when the item is absent. Read errors are logged
    /// and reported as nil so the seeding flow proceeds; a genuinely broken
    /// channel then surfaces on the next write and degrades loudly.
    func data() -> Data?
    /// Replaces the stored blob. Returns false on failure — callers must log
    /// and degrade, never drop the write silently.
    @discardableResult
    func store(_ blob: Data) -> Bool
    /// Removes the item. An absent item counts as removed.
    @discardableResult
    func delete() -> Bool
}

/// Production channel: one data-protection keychain generic-password item
/// holding the launcher blob. When `accessGroup` is set, the item lives in
/// the SHARED keychain group and is visible to every target signed with the
/// same group entitlement (app + widget extension).
final class SecKeychainStore: LauncherKeychainStore {
    let service: String
    let account: String
    /// nil uses the process default access group (unit tests on the
    /// simulator); production passes the shared group constant.
    let accessGroup: String?

    init(service: String, account: String, accessGroup: String?) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    /// Cheap existence probe: errSecSuccess and errSecItemNotFound both prove
    /// the keychain (and the access group, when set) is usable; anything
    /// else — errSecMissingEntitlement on a build without the entitlement,
    /// a locked keychain, … — marks the channel unavailable.
    func isAvailable() -> Bool {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(itemQuery as CFDictionary, &result)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func data() -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            NSLog("PlainPhone: keychain read failed (OSStatus %d) — treating as empty; the next save recreates the item.", status)
            return nil
        }
    }

    @discardableResult
    func store(_ blob: Data) -> Bool {
        let update: [String: Any] = [kSecValueData as String: blob]
        let status = SecItemUpdate(itemQuery as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            break // first write for this item — add below
        default:
            NSLog("PlainPhone: keychain update failed (OSStatus %d).", status)
            return false
        }
        // Return-only keys (kSecReturnData/kSecMatchLimit) are CopyMatching
        // territory: inside an Update query the macOS-backed simulator
        // keychain rejects them with errSecParam (-50) — keep them out.
        var add = itemQuery
        add[kSecValueData as String] = blob
        // Home-screen and lock-screen widgets must be able to read the item
        // after the first unlock, including right after a reboot.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("PlainPhone: keychain add failed (OSStatus %d).", addStatus)
        }
        return addStatus == errSecSuccess
    }

    @discardableResult
    func delete() -> Bool {
        let status = SecItemDelete(itemQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    /// Query identifying the item in the data-protection keychain. Safe for
    /// Update/Delete and for the availability probe.
    private var itemQuery: [String: Any] {
        var query = baseQuery
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    /// CopyMatching-only: adds the return-data keys.
    private var readQuery: [String: Any] {
        var query = itemQuery
        // Existence probes are useless here — the call must RETURN the blob.
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}

/// Single source of truth for launcher data, shared by the app and the widget
/// through whichever shared channel resolves (App Group suite, or a shared
/// keychain item). All writes are clamped to `Limits` (including during
/// decoding) and trigger WidgetKit timeline reloads.
/// Resolved storage target: which channel to use and in what mode.
/// Exposed as a seam so unit tests can exercise EVERY branch deterministically
/// without depending on simulator entitlements or real container presence.
struct StorageResolution {
    /// Backs the `.appGroup`/`.standardFallback`/`.injected` sources; also
    /// the degradation target when a keychain write fails.
    let defaults: UserDefaults
    /// Non-nil exactly when `source == .keychain`; reads and writes then go
    /// here, never to `defaults`.
    let keychain: (any LauncherKeychainStore)?
    let source: StorageSource
}

/// Versioned envelope for the shared keychain payload. LauncherData is left
/// untouched (model fields are owned elsewhere); the CHANNEL owns this
/// wrapper. Bump `currentVersion` whenever payload semantics change:
/// readers that meet a different version treat the item as EMPTY and reseed
/// instead of attempting a hard decode (S-2, owner rule).
struct KeychainBlobEnvelope: Codable {
    static let currentVersion = 1
    var version: Int
    /// Raw LauncherData JSON. Capacity `Limits` keep the whole envelope well
    /// under 2 KB — history/log data has no place in the shared item.
    var payload: Data
}

/// What the shared keychain item held, after envelope handling.
enum KeychainReadOutcome {
    /// Current-version envelope with a decodable payload.
    case payload(LauncherData)
    /// No item, or a different payload version — the seeding flow proceeds.
    case empty
    /// Bytes exist but are unreadable (not an envelope, or payload fails to
    /// decode) — K-11: preserve the original bytes, flag explicit recovery.
    case corrupt(Data)
}

final class LauncherStore: ObservableObject {
    static let appGroupID = "group.com.plainphone.shared"
    static let storageKey = "plainphone.layouts.v1"
    /// Shared keychain item identity (S-2/F-2): one generic-password item,
    /// same service + account on both sides.
    static let keychainService = "com.example.plainphone.shared"
    static let keychainAccount = "layouts.v1"
    /// n=1 product: the signing team is fixed (72LR92LFT5), so the shared
    /// access group is a build-stable constant matching the
    /// `keychain-access-groups` entry `$(AppIdentifierPrefix)com.example.plainphone.shared`
    /// in both .entitlements files. A multi-team build would derive this from
    /// the resolved AppIdentifierPrefix instead.
    static let keychainAccessGroup = "72LR92LFT5.com.example.plainphone.shared"

    @Published private(set) var data: LauncherData
    /// True when stored bytes failed to decode. The original bytes are kept
    /// untouched until the user makes an edit, so data is never silently lost.
    @Published private(set) var hadLoadError = false
    private(set) var storageSource = StorageSource.appGroup

    private let defaults: UserDefaults
    /// Non-nil in `.keychain` mode; then it is the only read/write channel.
    private let keychainChannel: (any LauncherKeychainStore)?

    /// - Parameters:
    ///   - defaults: injectable for unit tests; marks the store `.injected`.
    ///   - groupContainerAvailable: overrides real container detection so
    ///     tests can force the resolution branches deterministically.
    ///   - keychain: injectable keychain channel (same seam style as
    ///     `resolveStorage`); production builds the real shared-item store.
    ///   - keychainAvailable: forces the keychain branch off so tests can
    ///     reach the `.standardFallback` resolution deterministically.
    ///   - fallbackDefaults: local defaults backing the non-shared branches;
    ///     injectable so keychain-mode tests never touch real `.standard`.
    /// - Note: init only READS. It never writes or reloads timelines, so a
    ///   widget reading an empty store has no side effects. The app process
    ///   calls `seedIfNeeded()` once to materialize the default layouts.
    init(defaults: UserDefaults? = nil,
         groupContainerAvailable: Bool? = nil,
         keychain: (any LauncherKeychainStore)? = nil,
         keychainAvailable: Bool = true,
         fallbackDefaults: UserDefaults? = nil) {
        let stored: Data?
        var keychainLoaded: LauncherData? = nil
        var keychainCorruptRaw: Data? = nil
        if let defaults {
            self.defaults = defaults
            keychainChannel = nil
            storageSource = .injected
            stored = defaults.data(forKey: Self.storageKey)
        } else {
            let resolved = Self.resolveStorage(
                groupContainerAvailable: groupContainerAvailable ?? Self.appGroupContainerAvailable,
                keychainAvailable: keychainAvailable,
                fallbackDefaults: fallbackDefaults ?? .standard,
                keychain: keychain)
            self.defaults = resolved.defaults
            keychainChannel = resolved.keychain
            storageSource = resolved.source
            if resolved.source == .standardFallback {
                NSLog("PlainPhone: no shared channel available (App Group %@, shared keychain) — falling back to standard defaults. Data stays local to this process; widgets cannot read it and will show the built-in seed list.", Self.appGroupID)
            }
            // Load straight from the resolution locals: `self` must not run
            // instance methods until every stored property is initialized.
            if let channel = resolved.keychain {
                switch Self.decodeKeychainBlob(channel.data()) {
                case .payload(let decoded):
                    keychainLoaded = decoded
                    stored = nil
                case .empty:
                    stored = nil
                case .corrupt(let raw):
                    // K-11: item exists but is unreadable — preserve the raw
                    // bytes and flag the corruption state.
                    keychainCorruptRaw = raw
                    stored = nil
                }
            } else {
                stored = resolved.defaults.data(forKey: Self.storageKey)
            }
        }

        // Precedence: decoded keychain payload (current version) > corrupt
        // keychain item (K-11: defaults in memory + recovery flag, original
        // bytes untouched) > raw defaults blob (defensive decode; unknown
        // keys are ignored, never corruption — K-14) > empty seed state.
        if let keychainLoaded {
            self.data = keychainLoaded
            self.hadLoadError = false
        } else if keychainCorruptRaw != nil {
            self.data = LauncherData(layouts: DefaultLayouts.all)
            self.hadLoadError = true
        } else if let raw = stored {
            if let decoded = try? JSONDecoder().decode(LauncherData.self, from: raw) {
                self.data = decoded
                self.hadLoadError = false
            } else {
                self.data = LauncherData(layouts: DefaultLayouts.all)
                self.hadLoadError = true
            }
        } else {
            self.data = LauncherData(layouts: DefaultLayouts.all)
            self.hadLoadError = false
        }
    }

    /// Resolution order (S-2): App Group suite first (future-proof — a paid
    /// team re-enables it with no code change), then the shared keychain
    /// item (the free-team channel, F-2) — probed once so an un-entitled
    /// keychain degrades to local instead of failing silently — then local
    /// `.standard` with the degraded source reported. `keychain` is the
    /// test seam; production builds the real SecItem-backed store with the
    /// shared access group.
    static func resolveStorage(groupContainerAvailable: Bool,
                               keychainAvailable: Bool = true,
                               appGroupID: String = LauncherStore.appGroupID,
                               fallbackDefaults: UserDefaults = .standard,
                               keychain: (any LauncherKeychainStore)? = nil) -> StorageResolution {
        if groupContainerAvailable, let suite = UserDefaults(suiteName: appGroupID) {
            return StorageResolution(defaults: suite, keychain: nil, source: .appGroup)
        }
        if keychainAvailable {
            let channel = keychain ?? SecKeychainStore(service: keychainService,
                                                       account: keychainAccount,
                                                       accessGroup: keychainAccessGroup)
            // Probe before committing: an un-entitled keychain (e.g. a
            // simulator build, where `$(AppIdentifierPrefix)` cannot
            // resolve) must fall through to the local fallback with the
            // degraded banner, not fail on every later write.
            guard channel.isAvailable() else {
                return StorageResolution(defaults: fallbackDefaults, keychain: nil,
                                         source: .standardFallback)
            }
            return StorageResolution(defaults: fallbackDefaults, keychain: channel, source: .keychain)
        }
        return StorageResolution(defaults: fallbackDefaults, keychain: nil, source: .standardFallback)
    }

    /// Test-only hook: erases stored launcher data through the SAME channel
    /// the store would resolve in this process, so UI-test resets work in
    /// every storage mode (App Group, shared keychain, local).
    static func wipeStoredData(groupContainerAvailable: Bool? = nil,
                               appGroupID: String = LauncherStore.appGroupID,
                               defaults: UserDefaults? = nil,
                               keychain: (any LauncherKeychainStore)? = nil,
                               keychainAvailable: Bool = true) {
        if let defaults {
            defaults.removeObject(forKey: storageKey)
            return
        }
        let resolved = resolveStorage(
            groupContainerAvailable: groupContainerAvailable ?? appGroupContainerAvailable,
            keychainAvailable: keychainAvailable,
            appGroupID: appGroupID,
            keychain: keychain)
        if let channel = resolved.keychain {
            channel.delete()
        } else {
            resolved.defaults.removeObject(forKey: storageKey)
        }
    }

    /// Test-only hook: plants unreadable bytes so the corruption-warning UX
    /// can be verified end-to-end through the real app.
    static func plantCorruptData(defaults: UserDefaults? = nil,
                                 keychain: (any LauncherKeychainStore)? = nil) {
        let corrupt = Data("corrupted-by-test".utf8)
        if let defaults {
            defaults.set(corrupt, forKey: storageKey)
        } else if let keychain {
            keychain.store(corrupt)
        } else {
            let resolved = resolveStorage(groupContainerAvailable: appGroupContainerAvailable)
            if let channel = resolved.keychain {
                channel.store(corrupt)
            } else {
                resolved.defaults.set(corrupt, forKey: storageKey)
            }
        }
    }

    /// Writes the default layouts once if nothing USABLE is stored yet —
    /// absent item, or a foreign payload version. Corrupt bytes do NOT
    /// reseed (K-11 recovery is explicit). App-process only (see
    /// PlainPhoneApp); never called by the widget.
    func seedIfNeeded() {
        guard !hadLoadError else { return }
        let needsSeed = hasNoUsableStoredData()
        let upgraded = DefaultLayouts.upgradeNativeRoutes(in: &data)
        if needsSeed || upgraded { save() }
    }

    // MARK: - Layout mutations

    @discardableResult
    func addLayout(named name: String) -> Bool {
        guard data.layouts.count < Limits.maxLayouts else { return false }
        // Whitespace-only names would render as blank rows; substitute a
        // usable fallback title.
        let trimmed = LauncherItem.clampName(name)
        let layout = LauncherLayout(name: trimmed.isEmpty ? "未命名版面" : trimmed)
        data.layouts.append(layout)
        save()
        return true
    }

    func deleteLayout(at offsets: IndexSet) {
        data.layouts.remove(atOffsets: offsets)
        save()
    }

    func deleteLayout(id: UUID) {
        data.layouts.removeAll { $0.id == id }
        save()
    }

    func renameLayout(id: UUID, to newName: String) {
        let trimmed = LauncherItem.clampName(newName)
        // A blank name would render as an empty row; refuse it.
        guard !trimmed.isEmpty, index(of: id) != nil else { return }
        data.layouts[index(of: id)!].name = trimmed
        save()
    }

    // MARK: - Item mutations

    @discardableResult
    func addItem(_ item: LauncherItem, to layoutID: UUID) -> Bool {
        guard let idx = index(of: layoutID),
              data.layouts[idx].items.count < Limits.maxItemsPerLayout else { return false }
        data.layouts[idx].items.append(item)
        save()
        return true
    }

    func updateItem(_ item: LauncherItem, in layoutID: UUID) {
        guard let li = index(of: layoutID),
              let ii = data.layouts[li].items.firstIndex(where: { $0.id == item.id }) else { return }
        data.layouts[li].items[ii] = item
        save()
    }

    func deleteItems(at offsets: IndexSet, in layoutID: UUID) {
        guard let li = index(of: layoutID) else { return }
        data.layouts[li].items.remove(atOffsets: offsets)
        save()
    }

    func moveItems(in layoutID: UUID, from source: IndexSet, to destination: Int) {
        guard let li = index(of: layoutID) else { return }
        data.layouts[li].items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Layout settings

    /// Replaces the layout settings (SPEC-NEXT §6 L-1/W-2). Runs through the
    /// ordinary save path, so shared-channel write-through and the
    /// WidgetKit timeline reload (W-5) behave exactly like item edits: the
    /// widgets re-resolve `LauncherData.settings` on their next timeline.
    func updateSettings(_ newSettings: LayoutSettings) {
        data.settings = newSettings
        save()
    }

    // MARK: - Persistence

    private func index(of layoutID: UUID) -> Array<LauncherLayout>.Index? {
        data.layouts.firstIndex { $0.id == layoutID }
    }

    private func save() {
        // While stored bytes are unreadable, ordinary edits must NOT overwrite
        // the preserved blob. Recovery is an explicit user action.
        guard !hadLoadError else { return }
        if let blob = try? JSONEncoder().encode(data) {
            writeToChannel(blob)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// True when the resolved channel holds NO usable data — absent item, or
    /// an item whose payload version differs (S-2: reseed instead of
    /// hard-decode). Corrupt bytes count as PRESENT (K-11 recovery is
    /// explicit, never reseeded over). In keychain mode `defaults` is NOT
    /// consulted — the channels must never be mixed, or app edits would land
    /// in one place while widget reads come from the other.
    private func hasNoUsableStoredData() -> Bool {
        if let keychainChannel {
            if case .empty = Self.decodeKeychainBlob(keychainChannel.data()) { return true }
            return false
        }
        return defaults.data(forKey: Self.storageKey) == nil
    }

    /// Decodes the shared keychain item into one of three outcomes. Static so
    /// tests can drive it directly.
    static func decodeKeychainBlob(_ blob: Data?) -> KeychainReadOutcome {
        guard let blob, !blob.isEmpty else { return .empty }
        guard let envelope = try? JSONDecoder().decode(KeychainBlobEnvelope.self, from: blob) else {
            return .corrupt(blob) // not an envelope — K-11 path
        }
        guard envelope.version == KeychainBlobEnvelope.currentVersion else {
            NSLog("PlainPhone: keychain payload version %ld ≠ current %ld — treating as empty and reseeding.", envelope.version, KeychainBlobEnvelope.currentVersion)
            return .empty // foreign version: never hard-decode (S-2)
        }
        guard let decoded = try? JSONDecoder().decode(LauncherData.self, from: envelope.payload) else {
            return .corrupt(blob) // envelope intact, payload unreadable — K-11 path
        }
        return .payload(decoded)
    }

    /// Wraps a clamped LauncherData blob in the current-version envelope.
    static func encodeKeychainBlob(_ payload: Data) -> Data {
        let envelope = KeychainBlobEnvelope(version: KeychainBlobEnvelope.currentVersion,
                                            payload: payload)
        return (try? JSONEncoder().encode(envelope)) ?? Data()
    }

    /// Writes through the resolved channel. A keychain write failure is
    /// never silent: it is logged and the store degrades to the local
    /// `.standard` defaults, reporting `.standardFallback` so the UI banner
    /// appears (K-13 / G1-5). Later saves retry the keychain first — a
    /// transient failure self-heals, while the banner keeps the shaky
    /// session visible.
    private func writeToChannel(_ blob: Data) {
        if let keychainChannel {
            // The shared item carries the versioned envelope (S-2); the
            // payload stays the clamped LauncherData JSON — small by
            // construction, no history/log data.
            guard keychainChannel.store(Self.encodeKeychainBlob(blob)) else {
                NSLog("PlainPhone: shared keychain write failed — degrading to standard defaults. Widgets cannot see data written from here until the shared channel works again.")
                storageSource = .standardFallback
                defaults.set(blob, forKey: Self.storageKey)
                return
            }
            return
        }
        defaults.set(blob, forKey: Self.storageKey)
    }

    /// Explicit recovery from a decode failure: keeps the current in-memory
    /// state and overwrites the corrupt blob. Only reachable through the
    /// user-visible recovery button.
    func recoverFromCorruption() {
        guard hadLoadError else { return }
        hadLoadError = false
        save()
    }
}

extension LauncherStore {
    /// Detects whether the App Group container actually exists (not merely
    /// that UserDefaults accepts a suite name).
    static var appGroupContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }
}
