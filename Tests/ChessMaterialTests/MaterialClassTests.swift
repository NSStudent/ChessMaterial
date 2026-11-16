import Testing
@testable import ChessMaterial

@Suite("Clases de material")
struct MaterialClassTests {
    @Test("Caben en 64 bits y los nombres están completos")
    func fitsInUInt64() {
        #expect(MaterialClass.allCases.count <= 64)
        #expect(MaterialClass.allCases.count == MaterialClass.names.count)
        #expect(MaterialClass.allCases.map(\.rawValue) == Array(0 ..< MaterialClass.allCases.count))
    }

    @Test("Todas las clases se alcanzan")
    func everyClassIsReachable() {
        var seen: UInt64 = 0
        let counts = 0 ... 3
        for qw in 0 ... 2 { for qb in 0 ... 2 { for rw in counts { for rb in counts {
            for bw in counts { for bb in counts { for nw in counts { for nb in counts {
                for (pw, pb) in [(0, 0), (1, 1), (1, 0), (0, 1), (3, 0), (0, 3)] {
                    var s = MaterialSignature(white: PieceCounts(pawns: pw, knights: nw, bishops: bw, rooks: rw, queens: qw),
                                              black: PieceCounts(pawns: pb, knights: nb, bishops: bb, rooks: rb, queens: qb))
                    seen |= MaterialClass.classes(of: s)
                    if bw == 1, bb == 1 {
                        s.bishopColors = [.whiteLight, .blackDark]
                        seen |= MaterialClass.classes(of: s)
                    }
                }
            } } } }
        } } } }
        #expect(seen == MaterialClass.allMask)
        #expect(MaterialClass.members(of: seen).count == MaterialClass.allCases.count)
    }

    @Test("No dependen del color")
    func colorIndependent() {
        var rng = SplitMix64(seed: 42)
        for _ in 0 ..< 20000 {
            let s = MaterialSignature.random(using: &rng, anyBishopColors: true)
            #expect(MaterialClass(s) == MaterialClass(s.colorSwapped))
        }
    }

    @Test("Ejemplos", arguments: [
        ("R-R", MaterialClass.bareKings),
        ("RPP-RPP", .pawnsEqual),
        ("RP-R", .pawnsUpOne),
        ("R-RPPP", .pawnsUpTwoOrMore),
        ("TP-R", .rookVsBare),
        ("TPPP-TPPP", .rookRookEqual),
        ("TP-T", .rookRookUpOne),
        ("TPPPP-TPP", .rookRookUpTwoOrMore),
        ("TTPP-TTPP", .twoRooksEach),
        ("T-TT", .twoRooksVsRook),
        ("AP-R", .minorVsBare),
        ("AP-CP", .bishopVsKnight),
        ("CPP-CP", .knightVsKnight),
        ("AC-A", .twoMinorsVsMinor),
        ("AA-AC", .twoMinorsEach),
        ("TPPP-APPPP", .rookVsMinorWithPawns),
        ("TPPP-APPP", .rookVsMinor),
        ("TC-T", .rookMinorVsRook),
        ("TC-TC", .rookKnightEach),
        ("TA-TC", .rookBishopVsRookKnight),
        ("T-AC", .rookVsTwoMinors),
        ("TT-TA", .otherRookMinorEnding),
        ("DP-R", .queenVsBare),
        ("DPP-DPP", .queenQueenEqual),
        ("DPPP-DPP", .queenQueenUp),
        ("D-T", .queenVsRook),
        ("D-TT", .queenVsPieces),
        ("DT-D", .queenPieceVsQueen),
        ("DTTAACCPPPPPPPP-DTTAACCPPPPPPPP", .queensFullEqual),
        ("DTTACCPPPPPPP-DTAACCPPPPPPPP", .queensFullExchangeForPawns),
        ("DTT-DTA", .queensReducedExchange),
        ("TTAACCPPPPPPPP-TTAACCPPPPPPPP", .noQueensFullEqual),
        ("TTA-TTC", .noQueensReducedEqual),
        ("TTAC-TTA", .noQueensReducedMinorPiece),
        ("DTT-TTAA", .queenImbalanceReduced),
    ])
    func examples(text: String, expected: MaterialClass) {
        #expect(MaterialClass(sig(text)) == expected)
    }

    @Test("Alfiles de distinto color desde el tablero")
    func oppositeBishopsFromBoard() {
        // c8 clara, c1 oscura, f1 clara, g1 oscura.
        #expect(MaterialClass(signature(fen: "2b1k3/p7/8/8/8/8/P7/2B1K3 w - - 0 1")) == .bishopsOppositeColor)
        #expect(MaterialClass(signature(fen: "2b1k3/p7/8/8/8/8/P7/4KB2 w - - 0 1")) == .bishopsSameColor)
        #expect(MaterialClass(signature(fen: "2b1k3/p7/8/8/8/8/P7/4K1B1 w - - 0 1")) == .bishopsOppositeColor)
        #expect(MaterialClass(signature(fen: "r1b1k3/p7/8/8/8/8/P7/R3K1B1 w - - 0 1")) == .rookBishopOppositeColor)
        #expect(MaterialClass(signature(fen: "r1b1k2r/pppq1ppp/8/8/8/8/PPPQ1PPP/R3K1BR w - - 0 1")) == .queensOppositeBishops)
    }

    @Test("Máscaras de consultas típicas")
    func typicalMasks() throws {
        let rookEnding = try #require(MaterialQuery("T-T"))
        #expect(MaterialClass.members(of: rookEnding.classMask) == [.rookRookEqual, .rookRookUpOne, .rookRookUpTwoOrMore])

        let lucena = try #require(MaterialQuery("TP-T", ignoreColors: true))
        #expect(MaterialClass.members(of: lucena.classMask) == [.rookRookUpOne])

        let pawnEnding = MaterialQuery(
            white: PieceRanges(pawns: 0 ... 15, knights: 0 ... 0, bishops: 0 ... 0, rooks: 0 ... 0, queens: 0 ... 0, minors: 0 ... 0),
            black: PieceRanges(pawns: 0 ... 15, knights: 0 ... 0, bishops: 0 ... 0, rooks: 0 ... 0, queens: 0 ... 0, minors: 0 ... 0)
        )
        #expect(MaterialClass.members(of: pawnEnding.classMask) == [.bareKings, .pawnsEqual, .pawnsUpOne, .pawnsUpTwoOrMore])

        var opposite = try #require(MaterialQuery("A-A"))
        opposite.bishops = .opposite
        #expect(MaterialClass.members(of: opposite.classMask) == [.bishopsOppositeColor])

        #expect(MaterialQuery().classMask == MaterialClass.allMask)
    }

    @Test("Propiedad: nunca hay falsos negativos (firmas y consultas aleatorias)")
    func noFalseNegatives() {
        var rng = SplitMix64(seed: 2026_11_16)
        var positives = 0
        var masksCache: [MaterialQuery: UInt64] = [:]
        for _ in 0 ..< 250 {
            let query = MaterialQuery.random(using: &rng)
            let mask = masksCache[query] ?? MaterialClass.classesMatching(query)
            masksCache[query] = mask
            // Firmas libres.
            for _ in 0 ..< 300 {
                let s = MaterialSignature.random(using: &rng, anyBishopColors: Bool.random(using: &rng))
                if query.matches(s) {
                    positives += 1
                    if MaterialClass.classes(of: s) & mask == 0 { Issue.record("falso negativo: \(s) con \(query)") }
                }
            }
            // Firmas que cumplen a propósito.
            for _ in 0 ..< 30 {
                guard let s = query.sampleMatching(using: &rng) else { break }
                positives += 1
                if MaterialClass.classes(of: s) & mask == 0 { Issue.record("falso negativo: \(s) con \(query)") }
            }
        }
        #expect(positives > 2000)
    }

    @Test("La máscara es justa: cada clase marcada tiene alguna firma que cumple")
    func masksAreTight() throws {
        // Para consultas pequeñas, comprueba por fuerza bruta que no sobran clases.
        let queries: [MaterialQuery] = [
            try #require(MaterialQuery("T-T")),
            try #require(MaterialQuery("TA-TC", ignoreColors: true)),
            try #require(MaterialQuery("D-D")),
        ]
        for query in queries {
            var found: UInt64 = 0
            for pw in 0 ... 8 {
                for pb in 0 ... 8 {
                    for colors in 0 ... 15 {
                        var s = sig(query.white.rooks.lowerBound == 1 && query.white.bishops.lowerBound == 1 ? "TA-TC" : (query.white.queens.lowerBound == 1 ? "D-D" : "T-T"))
                        s[.pawn, .white] = pw
                        s[.pawn, .black] = pb
                        s.bishopColors = BishopSquareColors(rawValue: UInt8(colors))
                        for candidate in [s, s.colorSwapped] where query.matches(candidate) {
                            found |= MaterialClass.classes(of: candidate)
                        }
                    }
                }
            }
            #expect(found == query.classMask)
        }
    }
}
