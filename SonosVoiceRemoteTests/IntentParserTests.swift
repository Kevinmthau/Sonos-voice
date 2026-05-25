import XCTest
@testable import SonosVoiceRemote

final class IntentParserTests: XCTestCase {
    private let parser = IntentParser()
    private let rooms = [
        SonosRoom(name: "Kitchen"),
        SonosRoom(name: "Living Room"),
        SonosRoom(name: "Bedroom"),
        SonosRoom(name: "Dining Room")
    ]

    func testPauseFallsBackToSelectedRoom() {
        let intent = parser.parse("pause", availableRooms: rooms, selectedRoom: rooms[0])

        XCTAssertEqual(intent?.action, .pause)
        XCTAssertEqual(intent?.targetRoom, "Kitchen")
        XCTAssertEqual(intent?.scope, .singleRoom)
    }

    func testResumeFallsBackToSelectedRoom() {
        let intent = parser.parse("resume", availableRooms: rooms, selectedRoom: rooms[1])

        XCTAssertEqual(intent?.action, .resume)
        XCTAssertEqual(intent?.targetRoom, "Living Room")
        XCTAssertEqual(intent?.scope, .singleRoom)
    }

    func testSkipCommandParses() {
        let intent = parser.parse("skip", availableRooms: rooms, selectedRoom: rooms[2])

        XCTAssertEqual(intent?.action, .skip)
        XCTAssertEqual(intent?.targetRoom, "Bedroom")
    }

    func testTurnItUpParses() {
        let intent = parser.parse("turn it up", availableRooms: rooms, selectedRoom: rooms[3])

        XCTAssertEqual(intent?.action, .volumeUp)
        XCTAssertEqual(intent?.targetRoom, "Dining Room")
    }

    func testTurnItDownParses() {
        let intent = parser.parse("turn it down", availableRooms: rooms, selectedRoom: rooms[3])

        XCTAssertEqual(intent?.action, .volumeDown)
        XCTAssertEqual(intent?.targetRoom, "Dining Room")
    }

    func testSetKitchenToTwentyParses() {
        let intent = parser.parse("Set kitchen to 20", availableRooms: rooms, selectedRoom: rooms[1])

        XCTAssertEqual(intent?.action, .setVolume)
        XCTAssertEqual(intent?.targetRoom, "Kitchen")
        XCTAssertEqual(intent?.volumeValue, 20)
    }

    func testVolumeClampsToHundred() {
        let intent = parser.parse("set bedroom to 110", availableRooms: rooms, selectedRoom: rooms[1])

        XCTAssertEqual(intent?.action, .setVolume)
        XCTAssertEqual(intent?.targetRoom, "Bedroom")
        XCTAssertEqual(intent?.volumeValue, 100)
    }

    func testPlayJazzInTheKitchenParses() {
        let intent = parser.parse("Play jazz in the kitchen", availableRooms: rooms, selectedRoom: rooms[1])

        XCTAssertEqual(intent?.action, .play)
        XCTAssertEqual(intent?.targetRoom, "Kitchen")
        XCTAssertEqual(intent?.contentQuery, "jazz")
    }

    func testPlayMilesDavisInLivingRoomParses() {
        let intent = parser.parse("Play Miles Davis in the living room", availableRooms: rooms, selectedRoom: rooms[0])

        XCTAssertEqual(intent?.action, .play)
        XCTAssertEqual(intent?.targetRoom, "Living Room")
        XCTAssertEqual(intent?.contentQuery, "miles davis")
    }

    func testPlayEverywhereParsesAsGroupAll() {
        let intent = parser.parse("play everywhere", availableRooms: rooms, selectedRoom: rooms[0])

        XCTAssertEqual(intent?.action, .groupAll)
        XCTAssertEqual(intent?.scope, .allRooms)
        XCTAssertNil(intent?.contentQuery)
    }

    func testPlayJazzEverywhereParsesQuery() {
        let intent = parser.parse("play jazz everywhere", availableRooms: rooms, selectedRoom: rooms[0])

        XCTAssertEqual(intent?.action, .groupAll)
        XCTAssertEqual(intent?.scope, .allRooms)
        XCTAssertEqual(intent?.contentQuery, "jazz")
    }

    func testPauseEverywhereParsesAllRoomsScope() {
        let intent = parser.parse("pause everywhere", availableRooms: rooms, selectedRoom: rooms[0])

        XCTAssertEqual(intent?.action, .pause)
        XCTAssertEqual(intent?.scope, .allRooms)
        XCTAssertNil(intent?.targetRoom)
    }

    func testPlayAloneFallsBackToResume() {
        let intent = parser.parse("play", availableRooms: rooms, selectedRoom: rooms[2])

        XCTAssertEqual(intent?.action, .resume)
        XCTAssertEqual(intent?.targetRoom, "Bedroom")
    }

    func testSharedFixtures() throws {
        let fixture = try SharedIntentFixture.load()
        let fixtureRooms = fixture.rooms.map { SonosRoom(name: $0) }

        for testCase in fixture.cases {
            let selectedRoom = fixtureRooms.first(where: { $0.name == testCase.selectedRoom })
            let intent = parser.parse(testCase.transcript, availableRooms: fixtureRooms, selectedRoom: selectedRoom)

            if let expected = testCase.expected {
                XCTAssertEqual(intent?.originalTranscript, testCase.transcript, testCase.name)
                XCTAssertEqual(intent?.action.rawValue, expected.action, testCase.name)
                XCTAssertEqual(intent?.targetRoom, expected.targetRoom, testCase.name)
                XCTAssertEqual(intent?.contentQuery, expected.contentQuery, testCase.name)
                XCTAssertEqual(intent?.volumeValue, expected.volumeValue, testCase.name)
                XCTAssertEqual(intent?.scope.rawValue, expected.scope, testCase.name)
            } else {
                XCTAssertNil(intent, testCase.name)
            }
        }
    }
}

private struct SharedIntentFixture: Decodable {
    let rooms: [String]
    let cases: [SharedIntentCase]

    static func load() throws -> SharedIntentFixture {
        if let bundledFixtureURL = Bundle(for: IntentParserTests.self).url(
            forResource: "intent-parser-fixtures",
            withExtension: "json"
        ) {
            let data = try Data(contentsOf: bundledFixtureURL)
            return try JSONDecoder().decode(SharedIntentFixture.self, from: data)
        }

        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent()
        let fixtureURL = repositoryRoot.appendingPathComponent("shared/intent-parser-fixtures.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(SharedIntentFixture.self, from: data)
    }
}

private struct SharedIntentCase: Decodable {
    let name: String
    let transcript: String
    let selectedRoom: String
    let expected: SharedExpectedIntent?
}

private struct SharedExpectedIntent: Decodable {
    let action: String
    let targetRoom: String?
    let contentQuery: String?
    let volumeValue: Int?
    let scope: String
}
