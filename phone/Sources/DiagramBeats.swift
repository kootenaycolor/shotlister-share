import Foundation

/// **Beat edits, as the engine's ops** — each one batch, so one undo.
/// Beats are numbers on every piece's steps; taking one out or moving one is
/// only renumbering steps (`step_remove`, `step_set`), the same ops the Mac
/// sends for a step.
enum DiagramBeats {
    typealias Piece = (id: String, spots: [(index: Int, beat: Int, home: Bool)])

    /// Each piece's step on beat `n` goes, and every later beat comes down one.
    static func removeOps(_ n: Int, pieces: [Piece]) -> [[String: Any]] {
        guard n > 1 else { return [] }
        var ops: [[String: Any]] = []
        for piece in pieces {
            var spots = piece.spots
            if let k = spots.firstIndex(where: { $0.beat == n && !$0.home }) {
                let gone = spots[k].index
                ops.append(["op": "step_remove", "id": piece.id, "step": gone])
                spots.remove(at: k)
                for j in spots.indices where spots[j].index > gone { spots[j].index -= 1 }
            }
            for t in spots where t.beat > n {
                ops.append(["op": "step_set", "id": piece.id, "step": t.index, "beat": t.beat - 1])
            }
        }
        return ops
    }

    /// Beat `n` and the one `by` away trade places on every piece.
    static func moveOps(_ n: Int, by d: Int, pieces: [Piece]) -> [[String: Any]] {
        let m = n + d
        guard n > 1, m > 1 else { return [] }
        var ops: [[String: Any]] = []
        for piece in pieces {
            if let a = piece.spots.first(where: { $0.beat == n && !$0.home }) {
                ops.append(["op": "step_set", "id": piece.id, "step": a.index, "beat": m])
            } else if let b = piece.spots.first(where: { $0.beat == m && !$0.home }) {
                ops.append(["op": "step_set", "id": piece.id, "step": b.index, "beat": n])
            }
        }
        return ops
    }
}
