import XCTest
@testable import PlainPhone

final class PersistenceTests: XCTestCase {

    // uses TestStorage (file scope, bottom of this file)

    private func makeStore(_ suite: UserDefaults, items: Int = 0) -> LauncherStore {
        let store = LauncherStore(defaults: suite)
        XCTAssertTrue(store.addLayout(named: "測試用"))
        guard var first = store.data.layouts.last else { fatalError("no layout") }
        while first.items.count < items {
            _ = store.addItem(LauncherItem(name: "extra\(first.items.count)", url: "https://example.co"), to: first.id)
            first = store.data.layouts[store.data.layouts.count - 1]
        }
        return store
    }

    func testRoundTripPersistsData() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)
        _ = store.addLayout(named: "測試版面")

        let reloaded = LauncherStore(defaults: suite)
        XCTAssertTrue(reloaded.data.layouts.contains { $0.name == "測試版面" })
        XCTAssertFalse(reloaded.hadLoadError)
    }

    func testCorruptBlobIsNotSilentlyOverwritten() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        // Seed valid data, then corrupt it behind the store's back.
        let seeder = LauncherStore(defaults: suite)
        seeder.seedIfNeeded()
        let key = LauncherStore.storageKey
        suite.set(Data("not json".utf8), forKey: key)

        let store = LauncherStore(defaults: suite)
        XCTAssertTrue(store.hadLoadError, "decode failure must be surfaced")
        XCTAssertEqual(store.data.layouts.map(\.name), DefaultLayouts.all.map(\.name),
                       "falls back to defaults in memory")

        // An ordinary edit mutates memory but must NOT overwrite preserved bytes.
        _ = store.addLayout(named: "搶救編輯")
        XCTAssertEqual(suite.data(forKey: key), Data("not json".utf8),
                       "ordinary edit must not overwrite corrupt bytes")
        XCTAssertFalse(store.hadLoadError == false, "stays in recovery mode")

        // Explicit user recovery action overwrites the blob.
        store.recoverFromCorruption()
        let recovered = try JSONDecoder().decode(LauncherData.self,
                                                 from: XCTUnwrap(suite.data(forKey: key)))
        XCTAssertTrue(recovered.layouts.contains { $0.name == "搶救編輯" })
    }

    func testAddLayoutCapsAtTwelve() {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)
        let seeded = store.data.layouts.count
        XCTAssertEqual(seeded, DefaultLayouts.all.count)

        for i in 0..<(Limits.maxLayouts - seeded) {
            XCTAssertTrue(store.addLayout(named: "L\(i)"))
        }
        XCTAssertEqual(store.data.layouts.count, Limits.maxLayouts)
        XCTAssertFalse(store.addLayout(named: "overflow"),
                       "layout beyond \(Limits.maxLayouts) must be refused")
    }

    func testAddItemCapsAtLimitPerLayout() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = makeStore(suite, items: 0)
        // Target the dedicated empty layout created by makeStore.
        let layoutID = try XCTUnwrap(store.data.layouts.last?.id)

        for i in 0..<Limits.maxItemsPerLayout {
            XCTAssertTrue(store.addItem(LauncherItem(name: "i\(i)", url: "https://e.co/\(i)"), to: layoutID))
        }
        XCTAssertFalse(store.addItem(LauncherItem(name: "over", url: "https://e.co/x"), to: layoutID))
        XCTAssertEqual(store.data.layouts.last?.items.count, Limits.maxItemsPerLayout)
    }

    func testDeleteLayoutRemovesItAndKeepsTheRest() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)
        _ = store.addLayout(named: "臨時")
        let victim = try XCTUnwrap(store.data.layouts.last?.id)
        let survivors = store.data.layouts.filter { $0.id != victim }.map(\.id)

        store.deleteLayout(id: victim)

        XCTAssertFalse(store.data.layouts.contains { $0.id == victim })
        XCTAssertEqual(store.data.layouts.map(\.id), survivors)
    }

    func testRenameLayoutPersists() throws {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)
        _ = store.addLayout(named: "臨時")
        let id = try XCTUnwrap(store.data.layouts.last?.id)

        store.renameLayout(id: id, to: "改名後")

        let reloaded = LauncherStore(defaults: suite)
        XCTAssertEqual(reloaded.data.layouts.first { $0.id == id }?.name, "改名後")
    }
}

/// Fixed, bounded test domain shared by every suite. Each test wipes it first
/// and removes it on exit, so test plist count cannot grow across runs.
enum TestStorage {
    static let name = "test.plainphone.shared"

    static func make() -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    static func cleanup() {
        UserDefaults().removePersistentDomain(forName: name)
    }
}

final class SeedingAndStorageSourceTests: XCTestCase {

    func testInitIsReadOnlyAndSeedingIsIdempotent() {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }

        let store = LauncherStore(defaults: suite)
        XCTAssertNil(suite.data(forKey: LauncherStore.storageKey),
                     "init must not write — widget reads stay side-effect free")

        store.seedIfNeeded()
        let blob = suite.data(forKey: LauncherStore.storageKey)
        XCTAssertNotNil(blob)

        store.seedIfNeeded()
        XCTAssertEqual(suite.data(forKey: LauncherStore.storageKey), blob,
                       "seed must be idempotent")
    }

    func testStorageSourceReporting() {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }

        XCTAssertEqual(LauncherStore(defaults: suite).storageSource, .injected)
        // Production init follows the REAL environment: container availability
        // first, then a live probe of the shared keychain channel (on a
        // simulator build the entitlement is absent, so honest degradation is
        // the expected outcome). The seam test below covers every branch
        // explicitly and deterministically.
        let productionChannel = SecKeychainStore(service: LauncherStore.keychainService,
                                                 account: LauncherStore.keychainAccount,
                                                 accessGroup: LauncherStore.keychainAccessGroup)
        let expected: StorageSource
        if LauncherStore.appGroupContainerAvailable {
            expected = .appGroup
        } else if productionChannel.isAvailable() {
            expected = .keychain
        } else {
            expected = .standardFallback
        }
        XCTAssertEqual(LauncherStore().storageSource, expected)
    }

    func testStorageResolutionExercisesBothBranchesDeterministically() {
        // Both branches are forced through the injectable seam with private
        // suite names, so neither depends on simulator entitlements nor on
        // the real shared suite being untouched by other processes.
        let groupName = "test.resolve.group"
        let group = LauncherStore.resolveStorage(groupContainerAvailable: true,
                                                 appGroupID: groupName)
        XCTAssertEqual(group.source, .appGroup)
        XCTAssertNil(group.keychain)

        // Behavioral proof it is the requested suite: writes land there.
        group.defaults.set("probe", forKey: "plainphone.resolve.probe")
        XCTAssertEqual(UserDefaults(suiteName: groupName)?.string(forKey: "plainphone.resolve.probe"),
                       "probe")
        group.defaults.removeObject(forKey: "plainphone.resolve.probe")
        defer { UserDefaults().removePersistentDomain(forName: groupName) }

        let fallbackName = "test.resolve.fallback"
        let fallbackInstance = UserDefaults(suiteName: fallbackName)!
        defer { UserDefaults().removePersistentDomain(forName: fallbackName) }
        // Keychain is forced off so resolution passes THROUGH the new shared
        // branch and reaches the local fallback deterministically.
        let fallback = LauncherStore.resolveStorage(groupContainerAvailable: false,
                                                    keychainAvailable: false,
                                                    fallbackDefaults: fallbackInstance)
        XCTAssertEqual(fallback.source, .standardFallback)
        XCTAssertNil(fallback.keychain)
        XCTAssertTrue(fallback.defaults === fallbackInstance,
                      "fallback branch must use the provided standard defaults")
    }

    func testWipeStoredDataResolvesIdenticallyToInit() {
        // Fallback-mode wipe hits exactly the instance production would use.
        let fallbackName = "test.wipe.fallback"
        let fallbackInstance = UserDefaults(suiteName: fallbackName)!
        defer { UserDefaults().removePersistentDomain(forName: fallbackName) }
        fallbackInstance.set(Data("keep?".utf8), forKey: LauncherStore.storageKey)

        LauncherStore.wipeStoredData(groupContainerAvailable: false, defaults: fallbackInstance)
        XCTAssertNil(fallbackInstance.object(forKey: LauncherStore.storageKey))

        // Group-mode wipe targets exactly the resolved group suite (private
        // name — never the real shared suite), and is scoped to the key.
        let groupName = "test.wipe.group"
        let groupInstance = UserDefaults(suiteName: groupName)!
        groupInstance.set(Data("keep?".utf8), forKey: LauncherStore.storageKey)
        groupInstance.set("unrelated", forKey: "plainphone.unrelated.key")
        LauncherStore.wipeStoredData(groupContainerAvailable: true, appGroupID: groupName)
        XCTAssertNil(groupInstance.object(forKey: LauncherStore.storageKey))
        XCTAssertEqual(groupInstance.string(forKey: "plainphone.unrelated.key"), "unrelated",
                       "wipe must be scoped to the storage key only")
    }
}

/// S-2/F-2: the shared keychain item is the free-team channel connecting the
/// app and the widget. These tests exercise the channel itself, the
/// resolution chain around it, and the K-11/K-14/K-13 contracts on the
/// keychain path.
final class KeychainSharedStorageTests: XCTestCase {

    /// Private test coordinates — never the production service. No access
    /// group: simulator tests run in the host process's default group.
    private let service = "test.plainphone.keychain"
    private let account = "layouts.v1"

    private func makeChannel() -> SecKeychainStore {
        SecKeychainStore(service: service, account: account, accessGroup: nil)
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func releaseDefaults(_ name: String) {
        UserDefaults().removePersistentDomain(forName: name)
    }

    override func setUp() {
        super.setUp()
        makeChannel().delete()
    }

    override func tearDown() {
        makeChannel().delete()
        super.tearDown()
    }

    // MARK: - Shared dataset (S-1)

    func testTwoStoresShareOneKeychainBlob() {
        // "App" instance writes; a fully separate "widget" instance reading
        // the same shared item must see the identical dataset.
        let app = LauncherStore(keychain: makeChannel(),
                                fallbackDefaults: isolatedDefaults("test.kc.app"))
        defer { releaseDefaults("test.kc.app") }
        XCTAssertEqual(app.storageSource, .keychain)
        app.seedIfNeeded()
        XCTAssertTrue(app.addLayout(named: "鑰匙圈共享"))

        let widget = LauncherStore(keychain: makeChannel(),
                                   fallbackDefaults: isolatedDefaults("test.kc.widget"))
        defer { releaseDefaults("test.kc.widget") }
        XCTAssertEqual(widget.storageSource, .keychain)
        XCTAssertFalse(widget.hadLoadError)
        XCTAssertEqual(widget.data.layouts.map(\.name), app.data.layouts.map(\.name),
                       "both instances must see the same shared dataset")
        XCTAssertTrue(widget.data.layouts.contains { $0.name == "鑰匙圈共享" },
                      "widget store must read the app's keychain write")
    }

    // MARK: - Resolution chain (S-2)

    func testResolutionChainAppGroupThenKeychainThenLocal() {
        // 1. App Group available — the keychain is not consulted.
        let group = LauncherStore.resolveStorage(groupContainerAvailable: true,
                                                 appGroupID: "test.kc.group")
        defer { releaseDefaults("test.kc.group") }
        XCTAssertEqual(group.source, .appGroup)
        XCTAssertNil(group.keychain)

        // 2. App Group unavailable — the resolved channel is exactly the
        //    injected keychain (identity proves it is used, not copied).
        let fake = RecordingKeychainFake()
        let shared = LauncherStore.resolveStorage(groupContainerAvailable: false,
                                                  keychain: fake)
        XCTAssertEqual(shared.source, .keychain)
        XCTAssertTrue(shared.keychain === fake,
                      "keychain branch must run on the injected channel")

        // 2b. Production builds the real store on the shared constants. The
        //     probe outcome depends on the host's entitlement: on an
        //     entitled (device) build the channel resolves; on an
        //     un-entitled (simulator) build it must honestly degrade.
        let production = LauncherStore.resolveStorage(groupContainerAvailable: false)
        if SecKeychainStore(service: LauncherStore.keychainService,
                            account: LauncherStore.keychainAccount,
                            accessGroup: LauncherStore.keychainAccessGroup).isAvailable() {
            XCTAssertEqual(production.source, .keychain)
            let productionStore = production.keychain as? SecKeychainStore
            XCTAssertNotNil(productionStore)
            XCTAssertEqual(productionStore?.service, LauncherStore.keychainService)
            XCTAssertEqual(productionStore?.account, LauncherStore.keychainAccount)
            XCTAssertEqual(productionStore?.accessGroup, LauncherStore.keychainAccessGroup,
                           "production must target the SHARED access group")
        } else {
            XCTAssertEqual(production.source, .standardFallback,
                           "un-entitled host must degrade honestly, not assume the keychain works")
            XCTAssertNil(production.keychain)
        }

        // 2c. `keychainAvailable` alone is not enough — a channel that fails
        //     its probe degrades (K-13). Deterministic via the seam.
        let deadFake = RecordingKeychainFake()
        deadFake.available = false
        let dead = LauncherStore.resolveStorage(groupContainerAvailable: false,
                                                keychain: deadFake)
        XCTAssertEqual(dead.source, .standardFallback)
        XCTAssertNil(dead.keychain)

        // 3. Both shared channels unavailable — local defaults + degraded
        //    source (G1-5).
        let fallbackInstance = isolatedDefaults("test.kc.fallback")
        defer { releaseDefaults("test.kc.fallback") }
        let local = LauncherStore.resolveStorage(groupContainerAvailable: false,
                                                 keychainAvailable: false,
                                                 fallbackDefaults: fallbackInstance)
        XCTAssertEqual(local.source, .standardFallback)
        XCTAssertNil(local.keychain)
        XCTAssertTrue(local.defaults === fallbackInstance)
    }

    // MARK: - Degradation (K-13 / G1-5)

    func testKeychainWriteFailureDegradesLoudlyToLocalDefaults() throws {
        let fake = RecordingKeychainFake()
        fake.failWrites = true
        let suite = isolatedDefaults("test.kc.degrade")
        defer { releaseDefaults("test.kc.degrade") }
        let store = LauncherStore(keychain: fake, fallbackDefaults: suite)
        XCTAssertEqual(store.storageSource, .keychain)

        store.seedIfNeeded() // first shared write fails

        XCTAssertEqual(store.storageSource, .standardFallback,
                       "a failed shared write must degrade loudly, never silently drop")
        // The app keeps working: the blob landed in the local defaults.
        let localBlob = try XCTUnwrap(suite.data(forKey: LauncherStore.storageKey))
        let decoded = try JSONDecoder().decode(LauncherData.self, from: localBlob)
        XCTAssertEqual(decoded.layouts.map(\.name), DefaultLayouts.all.map(\.name))

        // Later edits keep persisting while degraded.
        XCTAssertTrue(store.addLayout(named: "降級後編輯"))
        let after = try JSONDecoder().decode(
            LauncherData.self,
            from: XCTUnwrap(suite.data(forKey: LauncherStore.storageKey)))
        XCTAssertTrue(after.layouts.contains { $0.name == "降級後編輯" })
    }

    // MARK: - Corruption contract on the keychain path (K-11)

    func testCorruptKeychainBlobIsNotSilentlyOverwritten() throws {
        let fake = RecordingKeychainFake()
        fake.blob = Data("not json".utf8)
        let suite = isolatedDefaults("test.kc.corrupt")
        defer { releaseDefaults("test.kc.corrupt") }
        let store = LauncherStore(keychain: fake, fallbackDefaults: suite)

        XCTAssertTrue(store.hadLoadError, "keychain decode failure must be surfaced")
        XCTAssertEqual(fake.blob, Data("not json".utf8), "init must not touch the corrupt blob")

        XCTAssertTrue(store.addLayout(named: "搶救編輯"))
        XCTAssertEqual(fake.blob, Data("not json".utf8),
                       "ordinary edit must not overwrite corrupt shared bytes")
        XCTAssertNil(suite.object(forKey: LauncherStore.storageKey),
                     "corruption must not leak into the local fallback either")

        // Explicit user recovery overwrites the shared item with a readable
        // current-version envelope.
        store.recoverFromCorruption()
        guard case let .payload(recovered) = LauncherStore.decodeKeychainBlob(fake.blob) else {
            return XCTFail("recovery must write a readable current-version envelope")
        }
        XCTAssertTrue(recovered.layouts.contains { $0.name == "搶救編輯" })
    }

    /// S-2 (owner rule): a payload written by a DIFFERENT version is treated
    /// as empty and reseeded — never hard-decoded, never flagged corrupt.
    func testForeignVersionKeychainBlobReseedsWithoutCorruptionBanner() throws {
        let foreign = KeychainBlobEnvelope(version: KeychainBlobEnvelope.currentVersion + 1,
                                           payload: Data("future format".utf8))
        let fake = RecordingKeychainFake()
        fake.blob = try JSONEncoder().encode(foreign)
        let suite = isolatedDefaults("test.kc.version")
        defer { releaseDefaults("test.kc.version") }
        let store = LauncherStore(keychain: fake, fallbackDefaults: suite)

        XCTAssertFalse(store.hadLoadError,
                       "a foreign payload version is not corruption — no banner")
        XCTAssertEqual(store.data.layouts.map(\.name), DefaultLayouts.all.map(\.name),
                       "foreign version must be treated as empty")

        // Seeding flow proceeds: the next save writes a current-version
        // envelope over the foreign bytes (logged, by design).
        store.seedIfNeeded()
        let envelope = try JSONDecoder().decode(KeychainBlobEnvelope.self,
                                                from: XCTUnwrap(fake.blob))
        XCTAssertEqual(envelope.version, KeychainBlobEnvelope.currentVersion,
                       "reseed must write the current version")
        guard case let .payload(reseeded) = LauncherStore.decodeKeychainBlob(fake.blob) else {
            return XCTFail("reseeded item must decode as the current version")
        }
        XCTAssertEqual(reseeded.layouts.map(\.name), DefaultLayouts.all.map(\.name))
        XCTAssertNil(suite.object(forKey: LauncherStore.storageKey),
                     "keychain mode must not write into the local fallback")
    }

    /// K-11 on the keychain path, second stage: a well-formed CURRENT-version
    /// envelope whose payload is garbage must also surface corruption and
    /// keep the original bytes.
    func testCorruptPayloadInsideValidKeychainEnvelopeIsNotOverwritten() throws {
        let corruptPayload = Data("garbage payload".utf8)
        let envelope = KeychainBlobEnvelope(version: KeychainBlobEnvelope.currentVersion,
                                            payload: corruptPayload)
        let fake = RecordingKeychainFake()
        fake.blob = try JSONEncoder().encode(envelope)
        let suite = isolatedDefaults("test.kc.payload")
        defer { releaseDefaults("test.kc.payload") }
        let store = LauncherStore(keychain: fake, fallbackDefaults: suite)

        XCTAssertTrue(store.hadLoadError, "undecodable payload must be surfaced")
        // JSONEncoder key order is not stable across calls — compare the
        // envelope CONTENT when asserting the bytes were preserved.
        func preservedPayload() throws -> Data {
            try JSONDecoder().decode(KeychainBlobEnvelope.self,
                                     from: XCTUnwrap(fake.blob)).payload
        }
        XCTAssertEqual(try preservedPayload(), corruptPayload,
                       "original envelope bytes must stay untouched")

        // Ordinary edit must not overwrite the preserved bytes.
        XCTAssertTrue(store.addLayout(named: "修復編輯"))
        XCTAssertEqual(try preservedPayload(), corruptPayload)

        // Explicit user recovery overwrites with a readable envelope.
        store.recoverFromCorruption()
        guard case let .payload(recovered) = LauncherStore.decodeKeychainBlob(fake.blob) else {
            return XCTFail("recovery must write a readable envelope")
        }
        XCTAssertTrue(recovered.layouts.contains { $0.name == "修復編輯" })
        XCTAssertNil(suite.object(forKey: LauncherStore.storageKey),
                     "corruption must not leak into the local fallback either")
    }

    // MARK: - Channel-aware test hooks

    func testWipeAndPlantGoThroughResolvedKeychainChannel() {
        let fake = RecordingKeychainFake()
        fake.blob = Data("keep?".utf8)

        LauncherStore.wipeStoredData(groupContainerAvailable: false, keychain: fake)
        XCTAssertNil(fake.blob, "wipe must remove the resolved keychain item")

        LauncherStore.plantCorruptData(keychain: fake)
        XCTAssertEqual(fake.blob, Data("corrupted-by-test".utf8),
                       "plant must write through the resolved keychain channel")
    }

}

/// In-memory channel; `failWrites` simulates failing shared writes,
/// `available = false` simulates an unusable keychain (missing entitlement,
/// device locked before first unlock, …).
final class RecordingKeychainFake: LauncherKeychainStore {
    var blob: Data?
    var failWrites = false
    var available = true

    func isAvailable() -> Bool { available }

    func data() -> Data? { blob }

    @discardableResult
    func store(_ data: Data) -> Bool {
        if failWrites { return false }
        blob = data
        return true
    }

    @discardableResult
    func delete() -> Bool {
        blob = nil
        return true
    }
}

final class LayoutCreationValidationTests: XCTestCase {

    @MainActor
    func testAddLayoutWithWhitespaceOnlyNameGetsFallbackTitle() throws {
        let suiteName = "test.create.blank"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        defer { d.removePersistentDomain(forName: suiteName) }
        let store = LauncherStore(defaults: d)

        // Whitespace-only names must not create a blank row.
        let before = store.data.layouts.count
        XCTAssertTrue(store.addLayout(named: "   "))
        XCTAssertEqual(store.data.layouts.count, before + 1)
        XCTAssertNotEqual(store.data.layouts.last?.name, "",
                          "blank-named layout created")
    }
}

final class EmptyStateEdgeTests: XCTestCase {

    @MainActor
    func testDeletingAllLayoutsKeepsAppFunctional() {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)

        while !store.data.layouts.isEmpty {
            store.deleteLayout(at: IndexSet(integer: 0))
        }
        XCTAssertTrue(store.data.layouts.isEmpty)

        // App remains functional: creating still works after a full wipe.
        XCTAssertTrue(store.addLayout(named: "重生"))
        XCTAssertEqual(store.data.layouts.count, 1)
    }

    @MainActor
    func testWipeThenSeedCycleIsStable() {
        let suite = TestStorage.make()
        defer { TestStorage.cleanup() }
        let store = LauncherStore(defaults: suite)
        store.seedIfNeeded()

        while !store.data.layouts.isEmpty {
            store.deleteLayout(at: IndexSet(integer: 0))
        }

        // Reloading from deliberately-emptied storage must respect the user's
        // deletion: no resurrection of examples, no error state.
        let reloaded = LauncherStore(defaults: suite)
        XCTAssertFalse(reloaded.hadLoadError)
        XCTAssertTrue(reloaded.data.layouts.isEmpty)

        // And the app stays functional afterwards.
        _ = reloaded.addLayout(named: "重新開始")
        XCTAssertEqual(reloaded.data.layouts.count, 1)
    }
}

final class RenameValidationTests: XCTestCase {

    @MainActor
    func testRenameToWhitespaceOnlyIsRefused() throws {
        let suiteName = "test.rename.blank"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        defer { d.removePersistentDomain(forName: suiteName) }
        let store = LauncherStore(defaults: d)
        store.seedIfNeeded()
        let id = try XCTUnwrap(store.data.layouts.first?.id)

        store.renameLayout(id: id, to: "   ")
        XCTAssertEqual(try XCTUnwrap(store.data.layouts.first { $0.id == id }).name,
                       try XCTUnwrap(DefaultLayouts.all.first).name,
                       "whitespace-only rename must be refused")
    }
}
