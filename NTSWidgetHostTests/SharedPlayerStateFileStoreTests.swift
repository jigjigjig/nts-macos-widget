import XCTest
@testable import NTSWidgetHost

final class SharedPlayerStateFileStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("sharedPlayerState.json", isDirectory: false)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    func testMissingFileLoadsIdle() {
        let store = SharedPlayerStateFileStore(fileURL: fileURL)

        let state = store.load()

        XCTAssertNil(state.currentStation)
        XCTAssertFalse(state.isPlaying)
    }

    func testSaveCreatesIntermediateDirectories() {
        let store = SharedPlayerStateFileStore(fileURL: fileURL)

        store.save(.idle())

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// The host writes and the widget extension reads from a *separate
    /// process*, so a saved state must be readable by an independent store
    /// instance holding no in-memory cache.
    func testStateRoundTripsThroughAFreshStoreInstance() {
        let written = SharedPlayerState(
            currentStation: .nts2,
            isPlaying: true,
            statusText: "Playing NTS 2",
            lastError: nil,
            updatedAt: .now,
            nts1NowTitle: "Show One",
            nts2NowTitle: "Show Two",
            metadataUpdatedAt: .now
        )

        SharedPlayerStateFileStore(fileURL: fileURL).save(written)
        let read = SharedPlayerStateFileStore(fileURL: fileURL).load()

        XCTAssertEqual(read.currentStation, .nts2)
        XCTAssertTrue(read.isPlaying)
        XCTAssertEqual(read.statusText, "Playing NTS 2")
        XCTAssertEqual(read.nts1NowTitle, "Show One")
        XCTAssertEqual(read.nts2NowTitle, "Show Two")
    }

    func testCorruptFileLoadsIdleRatherThanCrashing() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: fileURL)

        let state = SharedPlayerStateFileStore(fileURL: fileURL).load()

        XCTAssertFalse(state.isPlaying)
        XCTAssertNil(state.currentStation)
    }

    /// Both processes must resolve the same absolute path: the sandboxed widget
    /// extension can only reach its own container, so that container is where
    /// the shared file lives. The path must be built from the real home rather
    /// than `NSHomeDirectory()`, which is already container-relative inside the
    /// extension and would otherwise nest a second container path.
    func testDefaultLocationIsInsideTheWidgetExtensionContainer() {
        let path = SharedPlayerStateFileStore.defaultFileURL().path

        XCTAssertTrue(path.hasSuffix(
            "Library/Containers/com.fede.NTSWidgetHost.NTSWidgetExtension"
            + "/Data/Library/Application Support/NTSWidgetHost/sharedPlayerState.json"
        ), path)
        // A doubled container segment would mean the home was resolved from a
        // sandbox-redirected API.
        XCTAssertEqual(path.components(separatedBy: "/Library/Containers/").count, 2, path)
        XCTAssertFalse(path.contains("/Group Containers/"), path)
    }
}
