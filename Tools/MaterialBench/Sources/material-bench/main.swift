// material-bench: reproduce un PGN con fischer-core y mide ChessMaterial.
//
//   swift run -c release material-bench <pgn> [partidas=50000] [hilos=4] [salida.json]
//
// Saca la distribución de clases visitadas, qué fracción descarta cada consulta típica
// (y cuántas cumplen de verdad) y la distribución de finales más largos.

import ChessMaterial
import FischerCore
import Foundation

// MARK: - Consultas típicas

struct NamedQuery: Sendable {
    let name: String
    let query: MaterialQuery
}

func pieces(_ text: String, ignoreColors: Bool = true, bishops: BishopCondition = .any) -> MaterialQuery {
    var q = MaterialQuery(text, ignoreColors: ignoreColors)!
    q.bishops = bishops
    return q
}

let typicalQueries: [NamedQuery] = {
    var list: [NamedQuery] = []
    list.append(NamedQuery(name: "Final de peones (sin piezas)", query: pieces("R-R")))
    list.append(NamedQuery(name: "R+P contra R", query: pieces("P-R")))
    list.append(NamedQuery(name: "T-T (finales de torres)", query: pieces("T-T")))
    list.append(NamedQuery(name: "T+P contra T", query: pieces("TP-T")))
    list.append(NamedQuery(name: "TT-TT", query: pieces("TT-TT")))
    list.append(NamedQuery(name: "A-C", query: pieces("A-C")))
    list.append(NamedQuery(name: "C-C", query: pieces("C-C")))
    list.append(NamedQuery(name: "A-A de distinto color", query: pieces("A-A", bishops: .opposite)))
    list.append(NamedQuery(name: "TA-TA de distinto color", query: pieces("TA-TA", bishops: .opposite)))
    list.append(NamedQuery(name: "TA-TC", query: pieces("TA-TC")))
    list.append(NamedQuery(name: "D-D", query: pieces("D-D")))
    list.append(NamedQuery(name: "D-T", query: pieces("D-T")))

    var exchange = PieceRanges.anyDifference
    exchange.queens = 0 ... 0
    exchange.rooks = 1 ... 1
    exchange.minors = -1 ... -1
    exchange.pawns = -15 ... -1
    list.append(NamedQuery(name: "Calidad por peón(es)", query: MaterialQuery(difference: exchange, ignoreColors: true)))

    var queenRooks = PieceRanges.anyDifference
    queenRooks.queens = 1 ... 1
    queenRooks.rooks = -2 ... -2
    queenRooks.minors = 0 ... 0
    list.append(NamedQuery(name: "D contra TT", query: MaterialQuery(difference: queenRooks, ignoreColors: true)))

    var middle = PieceRanges.anyCount
    middle.queens = 1 ... 15
    middle.rooks = 1 ... 15
    middle.minors = 2 ... 30
    list.append(NamedQuery(name: "Medio juego con damas (D, T y 2 menores por bando)", query: MaterialQuery(white: middle, black: middle)))
    middle.queens = 0 ... 0
    list.append(NamedQuery(name: "Medio juego sin damas (T y 2 menores por bando)", query: MaterialQuery(white: middle, black: middle)))
    return list
}()

let typicalMasks = typicalQueries.map { MaterialClass.classesMatching($0.query) }

// MARK: - Estadísticas

struct QueryStats: Codable {
    var candidates = 0
    var matches1 = 0
    var matches6 = 0
    var falseNegatives = 0
}

struct Stats: Codable {
    var games = 0
    var skippedFEN = 0
    var sanErrors = 0
    var positions = 0
    var classGames = [Int](repeating: 0, count: MaterialClass.allCases.count)
    var classPositions = [Int](repeating: 0, count: MaterialClass.allCases.count)
    var distinctClasses = 0
    var queries = [QueryStats](repeating: QueryStats(), count: typicalQueries.count)
    var endings: [String: Int] = [:]
    var endingsColorless: [String: Int] = [:]
    var families = [Int](repeating: 0, count: EndingFamily.allCases.count)
    var noEnding = 0
    var endingPlies = [Int](repeating: 0, count: 301)
    var referenceGames = 0
    var referenceAgree = 0

    mutating func merge(_ o: Stats) {
        games += o.games
        skippedFEN += o.skippedFEN
        sanErrors += o.sanErrors
        positions += o.positions
        for i in classGames.indices {
            classGames[i] += o.classGames[i]
            classPositions[i] += o.classPositions[i]
        }
        distinctClasses += o.distinctClasses
        for i in queries.indices {
            queries[i].candidates += o.queries[i].candidates
            queries[i].matches1 += o.queries[i].matches1
            queries[i].matches6 += o.queries[i].matches6
            queries[i].falseNegatives += o.queries[i].falseNegatives
        }
        endings.merge(o.endings, uniquingKeysWith: +)
        endingsColorless.merge(o.endingsColorless, uniquingKeysWith: +)
        for i in families.indices { families[i] += o.families[i] }
        noEnding += o.noEnding
        for i in endingPlies.indices { endingPlies[i] += o.endingPlies[i] }
        referenceGames += o.referenceGames
        referenceAgree += o.referenceAgree
    }
}

// MARK: - Reproducción

/// Jugadas SAN de la línea principal (sin comentarios, variantes, NAG ni números).
func sanTokens(_ movetext: String) -> [Substring] {
    var tokens: [Substring] = []
    var depth = 0
    var inComment = false
    var inLineComment = false
    var start: String.Index?
    let text = movetext
    var i = text.startIndex
    func close(_ end: String.Index) {
        guard let s = start else { return }
        start = nil
        var token = text[s ..< end]
        // "12." / "12..." / "12.e4"
        if let first = token.first, first.isNumber {
            guard let dot = token.lastIndex(of: ".") else { return }  // resultado 1-0, 0-1, 1/2-1/2
            token = token[token.index(after: dot)...]
        }
        while let last = token.last, "!?".contains(last) { token = token.dropLast() }
        if token.isEmpty || token == "*" || token.first == "$" { return }
        tokens.append(token)
    }
    while i < text.endIndex {
        let c = text[i]
        if inComment {
            if c == "}" { inComment = false }
        } else if inLineComment {
            if c == "\n" { inLineComment = false }
        } else if c == "{" {
            close(i); inComment = true
        } else if c == ";" {
            close(i); inLineComment = true
        } else if c == "(" {
            close(i); depth += 1
        } else if c == ")" {
            close(i); depth = max(0, depth - 1)
        } else if depth > 0 {
            // dentro de una variante
        } else if c.isWhitespace {
            close(i)
        } else if start == nil {
            start = i
        }
        i = text.index(after: i)
    }
    close(text.endIndex)
    return tokens
}

let kinds: [(Piece.Kind, Int)] = [(.pawn, 0), (.knight, 1), (.bishop, 2), (.rook, 3), (.queen, 4), (.king, 5)]

/// Los 12 bitboards en orden de lanes de Polyglot, como el códec de MindChess.
func lanes(_ board: Board, into buffer: inout [UInt64]) {
    for (kind, type) in kinds {
        for (color, c) in [(PlayerColor.black, 0), (.white, 1)] {
            var raw: UInt64 = 0
            for square in board.bitboard(for: Piece(kind: kind, color: color)) { raw |= 1 << UInt64(square.rawValue) }
            buffer[2 * type + c] = raw
        }
    }
}

/// Criterio sencillo de una medida anterior: sin damas, ≤ 2
/// piezas por bando; gana la clave con más plies en total (empate: la primera vista).
struct ReferenceEnding {
    var counts: [String: Int] = [:]
    var order: [String] = []
    mutating func add(_ s: MaterialSignature) {
        guard s[.queen, .white] + s[.queen, .black] == 0, s.pieceCount(.white) <= 2, s.pieceCount(.black) <= 2 else { return }
        let key = s.formatted(.chessBaseSpanish)
        if counts[key] == nil { order.append(key) }
        counts[key, default: 0] += 1
    }
    var winner: String? {
        var best: String?
        for key in order where best == nil || counts[key]! > counts[best!]! { best = key }
        return best
    }
}

func process(_ chunk: PGNGameChunk, into stats: inout Stats, buffer: inout [UInt64]) {
    guard let basic = try? chunk.basicGame() else { stats.sanErrors += 1; return }
    if basic[tagName: "FEN"] != nil { stats.skippedFEN += 1; return }
    var game = Game()
    lanes(game.board, into: &buffer)
    var current = MaterialSignature(bitboards: buffer)
    var signatures: [MaterialSignature] = [current]
    for token in sanTokens(basic.movetext) {
        guard let resolved = try? game.resolve(san: String(token)) else { stats.sanErrors += 1; return }
        do {
            try game.execute(uncheckedMove: resolved.move) { resolved.promotion ?? .queen }
        } catch {
            stats.sanErrors += 1
            return
        }
        // El material solo cambia con capturas y coronaciones.
        if token.contains("x") || token.contains("=") || resolved.promotion != nil {
            lanes(game.board, into: &buffer)
            current = MaterialSignature(bitboards: buffer)
        }
        signatures.append(current)
    }

    stats.games += 1
    stats.positions += signatures.count
    var summary = GameMaterialSummary()
    var reference = ReferenceEnding()
    for s in signatures {
        summary.append(s)
        stats.classPositions[MaterialClass(s).rawValue] += 1
        reference.add(s)
    }
    let visited = summary.visited
    stats.distinctClasses += visited.nonzeroBitCount
    for c in MaterialClass.members(of: visited) { stats.classGames[c.rawValue] += 1 }

    for (i, named) in typicalQueries.enumerated() {
        let candidate = visited & typicalMasks[i] != 0
        if candidate { stats.queries[i].candidates += 1 }
        var q = named.query
        let m1 = q.matchesGame(signatures)
        if m1 {
            stats.queries[i].matches1 += 1
            if !candidate { stats.queries[i].falseNegatives += 1 }
            q.minimumPlies = 6
            if q.matchesGame(signatures) { stats.queries[i].matches6 += 1 }
        }
    }

    if let ending = summary.longestEnding {
        stats.endings[ending.name() + (ending.oppositeBishops ? " (opuestos)" : ""), default: 0] += 1
        stats.endingsColorless[ending.colorlessName(), default: 0] += 1
        stats.families[ending.family.rawValue] += 1
        stats.endingPlies[min(ending.plies, 300)] += 1
        if let ref = reference.winner {
            stats.referenceGames += 1
            if ref == ending.name() { stats.referenceAgree += 1 }
        }
    } else {
        stats.noEnding += 1
    }
}

// MARK: - Principal

final class Accumulator: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var stats = Stats()
    func merge(_ s: Stats) { lock.lock(); stats.merge(s); lock.unlock() }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("uso: material-bench <pgn> [partidas=50000] [hilos=4] [salida.json]")
    exit(1)
}
let path = args[1]
let limit = args.count > 2 ? Int(args[2]) ?? 50000 : 50000
let threads = args.count > 3 ? Int(args[3]) ?? 4 : 4
let output = args.count > 4 ? args[4] : nil

// Comprobación: la posición inicial de fischer-core da la firma inicial.
var check = [UInt64](repeating: 0, count: 12)
lanes(Game().board, into: &check)
precondition(MaterialSignature(bitboards: check) == .initial, "lanes mal ordenados")

// Coste de classesMatching en CPU del hilo (la máquina puede estar cargada).
func cpuMicros() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1000 }
var t0 = cpuMicros()
_ = MaterialClass.classesMatching(MaterialQuery())
let firstMicros = cpuMicros() - t0  // incluye construir la tabla
t0 = cpuMicros()
_ = MaterialClass.classesMatching(MaterialQuery())
let anyMicros = cpuMicros() - t0
t0 = cpuMicros()
for _ in 0 ..< 20 { for q in typicalQueries { _ = MaterialClass.classesMatching(q.query) } }
let maskMicros = (cpuMicros() - t0) / Double(20 * typicalQueries.count)

guard let handle = FileHandle(forReadingAtPath: path) else {
    print("no se puede abrir \(path)")
    exit(1)
}
let accumulator = Accumulator()
var chunker = PGNByteChunker()
var pending: [PGNGameChunk] = []
var read = 0
let start = Date()

func flush(_ batch: [PGNGameChunk]) {
    DispatchQueue.concurrentPerform(iterations: threads) { worker in
        var local = Stats()
        var buffer = [UInt64](repeating: 0, count: 12)
        var i = worker
        while i < batch.count {
            process(batch[i], into: &local, buffer: &buffer)
            i += threads
        }
        accumulator.merge(local)
    }
}

reading: while read < limit {
    let data = handle.readData(ofLength: 4 << 20)
    let chunks = data.isEmpty ? chunker.finish() : chunker.consume(data)
    for chunk in chunks {
        pending.append(chunk)
        read += 1
        if pending.count >= 4000 {
            flush(pending)
            pending.removeAll(keepingCapacity: true)
            FileHandle.standardError.write("… \(read)\n".data(using: .utf8)!)
        }
        if read >= limit { break reading }
    }
    if data.isEmpty { break }
}
flush(pending)
let seconds = Date().timeIntervalSince(start)
let stats = accumulator.stats

// MARK: - Informe

func pct(_ n: Int, _ d: Int) -> String { d == 0 ? "–" : String(format: "%.2f %%", 100 * Double(n) / Double(d)) }

print("# Medida ChessMaterial\n")
print("PGN: \(URL(fileURLWithPath: path).lastPathComponent) · leídas \(read) · reproducidas \(stats.games) · con FEN \(stats.skippedFEN) · SAN con error \(stats.sanErrors) · posiciones \(stats.positions)")
print(String(format: "Tiempo: %.1f s de reloj con %d hilos (%.0f partidas/s).", seconds, threads, Double(stats.games) / seconds))
print(String(format: "classesMatching (CPU): %.0f µs de media en las consultas típicas, %.0f µs la consulta vacía, %.0f µs la primera llamada.\n", maskMicros, anyMicros, firstMicros))
print(String(format: "Clases distintas por partida: %.2f de media\n", Double(stats.distinctClasses) / Double(max(stats.games, 1))))

print("## Clases visitadas\n")
print("| # | Clase | Partidas | % partidas | % posiciones |")
print("|--:|---|--:|--:|--:|")
for c in MaterialClass.allCases {
    print("| \(c.rawValue) | \(c.name) | \(stats.classGames[c.rawValue]) | \(pct(stats.classGames[c.rawValue], stats.games)) | \(pct(stats.classPositions[c.rawValue], stats.positions)) |")
}

print("\n## Consultas típicas\n")
print("| Consulta | Clases | Descarta | Candidatas | Cumplen (≥1 ply) | Cumplen (≥6 plies) | Falsos negativos |")
print("|---|--:|--:|--:|--:|--:|--:|")
for (i, named) in typicalQueries.enumerated() {
    let q = stats.queries[i]
    print("| \(named.name) | \(MaterialClass.members(of: typicalMasks[i]).map { String($0.rawValue) }.joined(separator: " ")) | \(pct(stats.games - q.candidates, stats.games)) | \(q.candidates) | \(q.matches1) | \(q.matches6) | \(q.falseNegatives) |")
}

print("\n## Final más largo\n")
var cumulative = 0
var median = 0
let withEnding = stats.games - stats.noEnding
for (plies, n) in stats.endingPlies.enumerated() {
    cumulative += n
    if cumulative * 2 >= withEnding { median = plies; break }
}
print("Partidas con final: \(withEnding) (\(pct(withEnding, stats.games))) · mediana de duración \(median) plies")
print("Coincidencia con el criterio sencillo (sin damas, ≤ 2 piezas por bando, más plies en total): \(pct(stats.referenceAgree, stats.referenceGames)) de \(stats.referenceGames)\n")
print("| Familia | Partidas | % |")
print("|---|--:|--:|")
for f in EndingFamily.allCases { print("| \(f.name) | \(stats.families[f.rawValue]) | \(pct(stats.families[f.rawValue], stats.games)) |") }
print("| Sin final | \(stats.noEnding) | \(pct(stats.noEnding, stats.games)) |")
print("\n| Final (sin color) | Partidas | % |")
print("|---|--:|--:|")
for (name, n) in stats.endingsColorless.sorted(by: { $0.value > $1.value }).prefix(25) { print("| \(name) | \(n) | \(pct(n, stats.games)) |") }
print("\n| Final (blancas-negras) | Partidas |")
print("|---|--:|")
for (name, n) in stats.endings.sorted(by: { $0.value > $1.value }).prefix(15) { print("| \(name) | \(n) |") }

if let output {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(stats).write(to: URL(fileURLWithPath: output))
}
