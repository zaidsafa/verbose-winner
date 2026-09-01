import Foundation

public struct MergeResult<Record: VersionedRecord>: Equatable, Sendable {
    public let records: [Record]
    public let remoteWins: Int
    public let localWins: Int
    public let insertedFromRemote: Int
}

/// Matches Pinbook's existing last-write-wins backup behavior. Local data wins exact timestamp ties.
public func mergeNewest<Record: VersionedRecord>(
    local: [Record],
    remote: [Record]
) -> MergeResult<Record> {
    var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
    var remoteWins = 0
    var localWins = 0
    var insertedFromRemote = 0

    for record in remote {
        if let existing = merged[record.id] {
            if record.updatedAt > existing.updatedAt {
                merged[record.id] = record
                remoteWins += 1
            } else {
                localWins += 1
            }
        } else {
            merged[record.id] = record
            insertedFromRemote += 1
        }
    }

    return MergeResult(
        records: merged.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        },
        remoteWins: remoteWins,
        localWins: localWins,
        insertedFromRemote: insertedFromRemote
    )
}
