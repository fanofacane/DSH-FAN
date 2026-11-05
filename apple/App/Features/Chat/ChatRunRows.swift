// SPDX-License-Identifier: AGPL-3.0-or-later
// Port of deriveRows and TurnProcessRow in DSH Go app/lib/ui/chat/chat_rows.dart.
import DSHClient
import Foundation

enum ChatRunRow: Identifiable {
    case message(ChatItem, actions: Bool = false, footnote: TurnTrace? = nil)
    case process([ChatItem])
    case footnote(TurnTrace)
    case changes(TurnTrace)

    var id: String {
        switch self {
        case .message(let item, _, _): item.id
        case .process(let items): "process-\(items.first?.id ?? "")"
        case .footnote(let turn): "footnote-\(turn.id)"
        case .changes(let turn): "changes-\(turn.id)"
        }
    }

    var isUser: Bool {
        if case .message(let item, _, _) = self { return item.role == .user }
        return false
    }

    static func derive(items: [ChatItem], turns: [TurnTrace], running: Bool, fold: Bool) -> [ChatRunRow] {
        var rows: [ChatRunRow] = []
        var piece: [ChatItem] = []
        var turn: TurnTrace?
        var cursor = 0

        func owner(of seq: Int) -> TurnTrace? {
            while cursor + 1 < turns.count, turns[cursor + 1].startSeq <= seq { cursor += 1 }
            guard turns.indices.contains(cursor), turns[cursor].startSeq <= seq else { return nil }
            let owner = turns[cursor]
            return seq <= (owner.endSeq ?? Int.max) ? owner : nil
        }

        func closePiece(footnote: TurnTrace? = nil, showActions: Bool = true) {
            var reply = piece.lastIndex { $0.role == .assistant && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if fold, turn?.endReason == "completed" {
                if let index = reply, !piece[index].tools.isEmpty || piece.dropFirst(index + 1).contains(where: { $0.role == .assistant }) {
                    reply = nil
                }
                var process = Array(piece.prefix(reply ?? piece.count))
                if let reply, !piece[reply].reasoning.isEmpty {
                    let source = piece[reply]
                    process.append(ChatItem(id: source.id + "-thought", role: .assistant, reasoning: source.reasoning))
                }
                let isOnlyThought = process.count == 1 && process[0].role == .assistant &&
                    process[0].tools.isEmpty && process[0].text.isEmpty
                if !process.isEmpty, !isOnlyThought {
                    rows.append(.process(process))
                    if let reply {
                        var answer = piece[reply]
                        answer.reasoning = ""
                        rows.append(.message(answer, actions: showActions, footnote: footnote))
                        rows += piece.dropFirst(reply + 1).map { .message($0) }
                    } else if let footnote {
                        rows.append(.footnote(footnote))
                    }
                    piece.removeAll(keepingCapacity: true)
                    return
                }
            }
            for (index, item) in piece.enumerated() {
                rows.append(.message(item, actions: showActions && index == reply, footnote: index == reply ? footnote : nil))
            }
            if reply == nil, let footnote { rows.append(.footnote(footnote)) }
            piece.removeAll(keepingCapacity: true)
        }

        func closeTurn(stillRunning: Bool = false) {
            let footnote = turn.flatMap { $0.endSeq == nil ? nil : $0 }
            closePiece(footnote: footnote, showActions: !stillRunning)
            if let turn, !turn.changes.isEmpty { rows.append(.changes(turn)) }
        }

        for item in items {
            if let seq = item.seq {
                let next = owner(of: seq)
                if turn?.id != next?.id {
                    closeTurn()
                    turn = next
                }
            }
            if item.role == .user {
                closePiece(showActions: item.state != .pending)
                rows.append(.message(item))
            } else {
                piece.append(item)
            }
        }
        closeTurn(stillRunning: running && turn?.endSeq == nil)
        return rows
    }
}
