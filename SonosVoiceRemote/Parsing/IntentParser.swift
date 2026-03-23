import Foundation

protocol IntentParsing {
    func parse(_ transcript: String, availableRooms: [SonosRoom], selectedRoom: SonosRoom?) -> ParsedVoiceIntent?
}

struct IntentParser: IntentParsing {
    func parse(_ transcript: String, availableRooms: [SonosRoom], selectedRoom: SonosRoom?) -> ParsedVoiceIntent? {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else {
            return nil
        }

        let explicitRoom = matchedRoomName(in: normalizedTranscript, availableRooms: availableRooms)
        let fallbackRoom = explicitRoom ?? selectedRoom?.name

        if isPauseCommand(normalizedTranscript) {
            let allRooms = referencesAllRooms(normalizedTranscript)
            return ParsedVoiceIntent(
                originalTranscript: transcript,
                action: .pause,
                targetRoom: allRooms ? nil : fallbackRoom,
                contentQuery: nil,
                volumeValue: nil,
                scope: allRooms ? .allRooms : .singleRoom
            )
        }

        if let setVolumeIntent = parseSetVolume(
            transcript: transcript,
            normalizedTranscript: normalizedTranscript,
            targetRoom: fallbackRoom
        ) {
            return setVolumeIntent
        }

        if isVolumeUpCommand(normalizedTranscript) {
            return ParsedVoiceIntent(
                originalTranscript: transcript,
                action: .volumeUp,
                targetRoom: fallbackRoom,
                contentQuery: nil,
                volumeValue: nil,
                scope: .singleRoom
            )
        }

        if isVolumeDownCommand(normalizedTranscript) {
            return ParsedVoiceIntent(
                originalTranscript: transcript,
                action: .volumeDown,
                targetRoom: fallbackRoom,
                contentQuery: nil,
                volumeValue: nil,
                scope: .singleRoom
            )
        }

        if isSkipCommand(normalizedTranscript) {
            return ParsedVoiceIntent(
                originalTranscript: transcript,
                action: .skip,
                targetRoom: fallbackRoom,
                contentQuery: nil,
                volumeValue: nil,
                scope: .singleRoom
            )
        }

        if isResumeCommand(normalizedTranscript) {
            let allRooms = referencesAllRooms(normalizedTranscript)
            return ParsedVoiceIntent(
                originalTranscript: transcript,
                action: .resume,
                targetRoom: allRooms ? nil : fallbackRoom,
                contentQuery: nil,
                volumeValue: nil,
                scope: allRooms ? .allRooms : .singleRoom
            )
        }

        if normalizedTranscript == "play" {
            return ParsedVoiceIntent(
                originalTranscript: transcript,
                action: .resume,
                targetRoom: fallbackRoom,
                contentQuery: nil,
                volumeValue: nil,
                scope: .singleRoom
            )
        }

        if let playIntent = parsePlay(
            transcript: transcript,
            normalizedTranscript: normalizedTranscript,
            explicitRoom: explicitRoom,
            fallbackRoom: fallbackRoom
        ) {
            return playIntent
        }

        return nil
    }

    private func parseSetVolume(
        transcript: String,
        normalizedTranscript: String,
        targetRoom: String?
    ) -> ParsedVoiceIntent? {
        let startsLikeSetVolume = normalizedTranscript.hasPrefix("set ")
            || normalizedTranscript.contains(" volume ")
            || normalizedTranscript.hasPrefix("volume ")

        guard startsLikeSetVolume else {
            return nil
        }

        guard let value = extractFirstNumber(from: normalizedTranscript) else {
            return nil
        }

        return ParsedVoiceIntent(
            originalTranscript: transcript,
            action: .setVolume,
            targetRoom: targetRoom,
            contentQuery: nil,
            volumeValue: max(0, min(100, value)),
            scope: .singleRoom
        )
    }

    private func parsePlay(
        transcript: String,
        normalizedTranscript: String,
        explicitRoom: String?,
        fallbackRoom: String?
    ) -> ParsedVoiceIntent? {
        guard normalizedTranscript.hasPrefix("play ") else {
            return nil
        }

        if referencesAllRooms(normalizedTranscript) {
            return ParsedVoiceIntent(
                originalTranscript: transcript,
                action: .groupAll,
                targetRoom: nil,
                contentQuery: extractAllRoomsPlayQuery(from: normalizedTranscript),
                volumeValue: nil,
                scope: .allRooms
            )
        }

        let payload = String(normalizedTranscript.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        var query = payload

        if let explicitRoom {
            let normalizedRoom = normalize(explicitRoom)
            let suffixes = [
                " in the \(normalizedRoom)",
                " in \(normalizedRoom)",
                " on the \(normalizedRoom)",
                " on \(normalizedRoom)"
            ]

            for suffix in suffixes where query.hasSuffix(suffix) {
                query.removeLast(suffix.count)
                query = query.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }

            if query == normalizedRoom {
                query = ""
            }
        }

        guard let cleanedQuery = cleanQuery(query), !cleanedQuery.isEmpty else {
            return ParsedVoiceIntent(
                originalTranscript: transcript,
                action: .resume,
                targetRoom: fallbackRoom,
                contentQuery: nil,
                volumeValue: nil,
                scope: .singleRoom
            )
        }

        return ParsedVoiceIntent(
            originalTranscript: transcript,
            action: .play,
            targetRoom: fallbackRoom,
            contentQuery: cleanedQuery,
            volumeValue: nil,
            scope: .singleRoom
        )
    }

    private func extractAllRoomsPlayQuery(from normalizedTranscript: String) -> String? {
        let noQueryPhrases = [
            "play everywhere",
            "play all",
            "play all rooms",
            "play in all rooms",
            "play in every room"
        ]

        if noQueryPhrases.contains(normalizedTranscript) {
            return nil
        }

        let suffixes = [
            " everywhere",
            " in all rooms",
            " in every room"
        ]

        for suffix in suffixes where normalizedTranscript.hasSuffix(suffix) {
            let startIndex = normalizedTranscript.index(normalizedTranscript.startIndex, offsetBy: 5)
            let endIndex = normalizedTranscript.index(normalizedTranscript.endIndex, offsetBy: -suffix.count)
            let query = normalizedTranscript[startIndex..<endIndex]
            return cleanQuery(String(query))
        }

        return nil
    }

    private func matchedRoomName(in normalizedTranscript: String, availableRooms: [SonosRoom]) -> String? {
        let sortedRooms = availableRooms.sorted {
            normalize($0.name).count > normalize($1.name).count
        }

        for room in sortedRooms {
            let normalizedRoom = normalize(room.name)
            let pattern = "(^|\\b)\(NSRegularExpression.escapedPattern(for: normalizedRoom))(\\b|$)"
            if normalizedTranscript.range(of: pattern, options: .regularExpression) != nil {
                return room.name
            }
        }

        return nil
    }

    private func cleanQuery(_ query: String) -> String? {
        let cleaned = normalize(query)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractFirstNumber(from normalizedTranscript: String) -> Int? {
        let pattern = "\\b(\\d{1,3})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(normalizedTranscript.startIndex..<normalizedTranscript.endIndex, in: normalizedTranscript)
        guard
            let match = regex.firstMatch(in: normalizedTranscript, options: [], range: range),
            let numberRange = Range(match.range(at: 1), in: normalizedTranscript)
        else {
            return nil
        }

        return Int(normalizedTranscript[numberRange])
    }

    private func isPauseCommand(_ transcript: String) -> Bool {
        matchesAny(transcript, phrases: ["pause", "pause everywhere", "pause all", "pause all rooms", "stop", "stop everywhere"])
    }

    private func isResumeCommand(_ transcript: String) -> Bool {
        matchesAny(transcript, phrases: ["resume", "resume everywhere", "continue", "continue everywhere"])
    }

    private func isSkipCommand(_ transcript: String) -> Bool {
        matchesAny(transcript, phrases: ["skip", "next", "next song", "skip this"])
    }

    private func isVolumeUpCommand(_ transcript: String) -> Bool {
        containsAny(transcript, phrases: ["turn it up", "turn up", "volume up", "louder", "increase volume"])
    }

    private func isVolumeDownCommand(_ transcript: String) -> Bool {
        containsAny(transcript, phrases: ["turn it down", "turn down", "volume down", "quieter", "decrease volume"])
    }

    private func referencesAllRooms(_ transcript: String) -> Bool {
        containsAny(transcript, phrases: ["everywhere", "all rooms", "every room"])
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesAny(_ transcript: String, phrases: [String]) -> Bool {
        phrases.contains(transcript)
    }

    private func containsAny(_ transcript: String, phrases: [String]) -> Bool {
        phrases.contains { transcript.contains($0) }
    }
}
