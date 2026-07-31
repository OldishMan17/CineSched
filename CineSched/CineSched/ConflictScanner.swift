// ConflictScanner.swift
// Cross-references the schedule against each cast member's marked unavailable dates
// and reports every scene where a character is scheduled to work while their actor is
// marked unavailable that day.

import Foundation

struct ScheduleConflict: Identifiable {
    let id = UUID()
    let date: Date
    let sceneID: UUID
    let sceneTitle: String
    let character: String
    let actorDisplayName: String
}

struct ConflictScanner {

    /// Scans every scheduled scene against Production Setup's cast availability. A
    /// character only produces a conflict if they're matched to a cast member (by name)
    /// who has at least one unavailable range covering that day — unmatched/background
    /// character names are silently skipped, since there's no availability data for them.
    static func scan(shootDays: [ShootDay], productionInfo: ProductionInfo) -> [ScheduleConflict] {
        guard !productionInfo.castList.isEmpty else { return [] }
        var conflicts: [ScheduleConflict] = []

        for day in shootDays {
            for scene in day.scenes {
                for character in scene.cast {
                    guard let member = productionInfo.castList.first(where: {
                        $0.characterName.trimmingCharacters(in: .whitespaces)
                            .caseInsensitiveCompare(character.trimmingCharacters(in: .whitespaces)) == .orderedSame
                    }), !member.unavailableRanges.isEmpty else { continue }

                    if member.unavailableRanges.contains(where: { $0.contains(day.date) }) {
                        conflicts.append(ScheduleConflict(
                            date: day.date,
                            sceneID: scene.id,
                            sceneTitle: scene.title,
                            character: character,
                            actorDisplayName: member.displayString
                        ))
                    }
                }
            }
        }
        return conflicts.sorted { $0.date < $1.date }
    }

    /// Just the set of dates with at least one conflict — cheap to check per date header
    /// when deciding whether to show a warning badge on the calendar.
    static func conflictDates(_ conflicts: [ScheduleConflict]) -> Set<Date> {
        let cal = Calendar.current
        return Set(conflicts.map { cal.startOfDay(for: $0.date) })
    }

    /// The IDs of scenes that specifically contain a conflicting cast member — used to
    /// turn just those scene strips red, rather than every strip on a day that merely
    /// happens to share a date with an unrelated conflict.
    static func conflictSceneIDs(_ conflicts: [ScheduleConflict]) -> Set<UUID> {
        Set(conflicts.map { $0.sceneID })
    }
}
