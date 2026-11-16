import Testing
@testable import ChessMaterial

/// Repite cada texto el número de plies indicado.
func sequence(_ parts: [(String, Int)]) -> [MaterialSignature] {
    parts.flatMap { text, plies in Array(repeating: sig(text), count: plies) }
}

@Suite("Finales")
struct EndgameTests {
    @Test("Criterio de final", arguments: [
        ("R-R", true), ("TA-TC", true), ("TT-TA", true), ("TTA-TT", false),
        ("D-D", true), ("D-TT", true), ("DT-D", true), ("DT-DT", false), ("DA-C", true),
        ("DTTAACC-DTTAACC", false),
    ])
    func isEnding(text: String, expected: Bool) {
        #expect(Endgame.isEnding(sig(text)) == expected)
    }

    @Test("El final más largo de una partida")
    func longest() throws {
        let game = sequence([
            ("DTTAACCPPPPPPPP-DTTAACCPPPPPPPP", 40),
            ("TTPPPPP-TTPPPPP", 10),
            ("TAPPPP-TCPPPP", 12),
            ("TPPP-TPPP", 20),
            ("TPP-TPP", 6),
            ("PP-P", 3),
        ])
        let ending = try #require(Endgame.longestEnding(in: game))
        #expect(ending.name() == "T-T")
        #expect(ending.family == .rooks)
        #expect(ending.startPly == 62)
        // Los peones no cuentan: T-T dura 26 plies seguidos.
        #expect(ending.plies == 26)
        #expect(ending.signature == sig("TPPP-TPPP"))
        #expect(ending.name(.english) == "R-R")

        let all = Endgame.endings(in: game)
        #expect(all.map { $0.name() } == ["TT-TT", "TA-TC", "T-T", "R-R"])
        #expect(all.map(\.plies) == [10, 12, 26, 3])
    }

    @Test("Empate: gana el último; duración mínima")
    func tiesAndMinimum() throws {
        let game = sequence([("TA-TC", 8), ("T-T", 8)])
        #expect(try #require(Endgame.longestEnding(in: game)).name() == "T-T")
        #expect(Endgame.longestEnding(in: game, minimumPlies: 9) == nil)
        #expect(Endgame.longestEnding(in: sequence([("DTTAACC-DTTAACC", 30)])) == nil)
    }

    @Test("Familias y nombres sin color", arguments: [
        ("R-R", EndingFamily.pawns, "R-R"), ("T-TT", .rooks, "TT-T"), ("A-C", .minors, "A-C"),
        ("C-A", .minors, "A-C"), ("D-D", .queens, "D-D"), ("T-D", .mixed, "D-T"), ("TA-T", .mixed, "TA-T"),
    ])
    func families(text: String, family: EndingFamily, colorless: String) throws {
        let ending = try #require(Endgame.longestEnding(in: [sig(text)]))
        #expect(ending.family == family)
        #expect(ending.colorlessName() == colorless)
    }

    @Test("Código de 2 B")
    func code() throws {
        var signatures = Array(repeating: signature(fen: "2b1k3/p7/8/8/8/8/P7/4K1B1 w - - 0 1"), count: 200)
        signatures.insert(sig("DTTAACC-DTTAACC"), at: 0)
        let ending = try #require(Endgame.longestEnding(in: signatures))
        let code = ending.code
        #expect(code.white?.name() == "A")
        #expect(code.black?.name() == "A")
        #expect(code.oppositeBishops)
        #expect(code.plies == 127)
        #expect(code.pieceKey == Endgame.pieceKey(signatures[1]))
        #expect(EndingCode.none.white == nil)
        // Todas las combinaciones válidas de un bando tienen código.
        for c in UInt8(0) ..< 15 {
            let side = try #require(EndingSide(code: c))
            let s = MaterialSignature(white: side.counts, black: PieceCounts())
            #expect(EndingSide(s, .white) == side)
        }
    }

    @Test("Resumen de partida en una pasada")
    func summary() {
        let game = sequence([("DTTAACCPPPPPPPP-DTTAACCPPPPPPPP", 20), ("TPP-TP", 30)])
        var summary = GameMaterialSummary()
        game.forEach { summary.append($0) }
        #expect(summary.visited == MaterialClass.visited(game))
        #expect(MaterialClass.members(of: summary.visited) == [.rookRookUpOne, .queensFullEqual])
        #expect(summary.longestEnding?.name() == "T-T")
        #expect(summary.longestEndingCode.plies == 30)
    }
}

@Suite("Consultas de material")
struct MaterialQueryTests {
    @Test("Rangos por bando e ignorar colores")
    func rangesAndColors() throws {
        let q = try #require(MaterialQuery("TP-T"))
        #expect(q.matches(sig("TP-T")))
        #expect(!q.matches(sig("T-TP")))
        #expect(try #require(MaterialQuery("TP-T", ignoreColors: true)).matches(sig("T-TP")))
        // Sin peones en el texto, los peones son libres.
        let rooks = try #require(MaterialQuery("T-T"))
        #expect(rooks.matches(sig("TPPPP-TPP")))
        #expect(!rooks.matches(sig("TA-T")))
    }

    @Test("Modo diferencia: calidad por peón")
    func difference() {
        var d = PieceRanges.anyDifference
        d.rooks = 1 ... 1
        d.minors = -1 ... -1
        d.pawns = -15 ... -1
        let q = MaterialQuery(difference: d, ignoreColors: true)
        #expect(q.matches(sig("DTTAPPPPP-DTACPPPPPP")))
        #expect(q.matches(sig("TPPPP-APPPPP")))
        #expect(q.matches(sig("APPPPP-TPPPP")))
        #expect(!q.matches(sig("TPPPPP-APPPPP")))
        #expect(q.classMask & MaterialClass.classes(of: sig("TPPPP-APPPPP")) != 0)
        #expect(MaterialClass.members(of: q.classMask).contains(.rookVsMinorWithPawns))
        #expect(!MaterialClass.members(of: q.classMask).contains(.rookVsMinor))
    }

    @Test("Alfiles de distinto color")
    func bishops() {
        var q = MaterialQuery()
        q.bishops = .opposite
        #expect(q.matches(signature(fen: "2b1k3/p7/8/8/8/8/P7/4K1B1 w - - 0 1")))
        #expect(!q.matches(signature(fen: "2b1k3/p7/8/8/8/8/P7/4KB2 w - - 0 1")))
    }

    @Test("Duración mínima en plies")
    func stability() throws {
        let game = sequence([("TA-TC", 5), ("T-T", 3), ("TA-TC", 2), ("T-T", 8)])
        var q = try #require(MaterialQuery("T-T"))
        #expect(q.runs(in: game) == [5 ..< 8, 10 ..< 18])
        q.minimumPlies = 4
        #expect(q.runs(in: game) == [10 ..< 18])
        #expect(q.firstMatch(in: game) == 10 ..< 18)
        #expect(q.matchesGame(game))
        q.minimumPlies = 9
        #expect(!q.matchesGame(game))
        #expect(q.firstMatch(in: game) == nil)
    }

    @Test("El seguimiento incremental da lo mismo que la secuencia")
    func tracker() {
        var rng = SplitMix64(seed: 99)
        let pool = ["T-T", "TP-T", "TA-TC", "R-R", "D-D", "TT-TT"].map(sig)
        for _ in 0 ..< 500 {
            let game = (0 ..< Int.random(in: 1 ... 40, using: &rng)).map { _ in pool.randomElement(using: &rng)! }
            var query = MaterialQuery.random(using: &rng)
            if Bool.random(using: &rng) { query = MaterialQuery("T-T")! }
            query.minimumPlies = Int.random(in: 1 ... 6, using: &rng)
            var tracker = MaterialQueryTracker(query)
            var matched = false
            for s in game { matched = tracker.append(s) || matched }
            #expect(matched == query.matchesGame(game))
            #expect(matched == !query.runs(in: game).isEmpty)
            if let first = tracker.firstMatch, let run = query.firstMatch(in: game) {
                #expect(first.lowerBound == run.lowerBound)
            }
        }
    }
}
