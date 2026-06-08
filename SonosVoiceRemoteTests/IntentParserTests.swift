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

    func testInlineCommandContractCases() {
        let cases: [IntentParserCase] = [
            .init(
                name: "pause selected room",
                transcript: "pause",
                selectedRoom: "Kitchen",
                expected: .init(action: .pause, targetRoom: "Kitchen", contentQuery: nil, volumeValue: nil, scope: .singleRoom)
            ),
            .init(
                name: "skip selected room",
                transcript: "next song",
                selectedRoom: "Living Room",
                expected: .init(action: .skip, targetRoom: "Living Room", contentQuery: nil, volumeValue: nil, scope: .singleRoom)
            ),
            .init(
                name: "volume words",
                transcript: "turn it down in the dining room",
                selectedRoom: "Kitchen",
                expected: .init(action: .volumeDown, targetRoom: "Dining Room", contentQuery: nil, volumeValue: nil, scope: .singleRoom)
            ),
            .init(
                name: "play content in room",
                transcript: "play miles davis in living room",
                selectedRoom: "Kitchen",
                expected: .init(action: .play, targetRoom: "Living Room", contentQuery: "miles davis", volumeValue: nil, scope: .singleRoom)
            ),
            .init(
                name: "play all rooms with query",
                transcript: "play jazz in every room",
                selectedRoom: "Kitchen",
                expected: .init(action: .groupAll, targetRoom: nil, contentQuery: "jazz", volumeValue: nil, scope: .allRooms)
            ),
            .init(
                name: "unknown command",
                transcript: "what is the weather",
                selectedRoom: "Kitchen",
                expected: nil
            )
        ]

        for testCase in cases {
            let selectedRoom = rooms.first(where: { $0.name == testCase.selectedRoom })
            let intent = parser.parse(testCase.transcript, availableRooms: rooms, selectedRoom: selectedRoom)

            if let expected = testCase.expected {
                XCTAssertEqual(intent?.originalTranscript, testCase.transcript, testCase.name)
                XCTAssertEqual(intent?.action, expected.action, testCase.name)
                XCTAssertEqual(intent?.targetRoom, expected.targetRoom, testCase.name)
                XCTAssertEqual(intent?.contentQuery, expected.contentQuery, testCase.name)
                XCTAssertEqual(intent?.volumeValue, expected.volumeValue, testCase.name)
                XCTAssertEqual(intent?.scope, expected.scope, testCase.name)
            } else {
                XCTAssertNil(intent, testCase.name)
            }
        }
    }
}

private struct IntentParserCase {
    let name: String
    let transcript: String
    let selectedRoom: String
    let expected: ExpectedIntent?
}

private struct ExpectedIntent {
    let action: SonosAction
    let targetRoom: String?
    let contentQuery: String?
    let volumeValue: Int?
    let scope: IntentScope
}
