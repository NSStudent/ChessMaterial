import Testing
@testable import ChessMaterial

@Suite("MaterialSignature")
struct MaterialSignatureTests {
    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    @Test("La posición inicial desde 12 bitboards")
    func initialFromBitboards() {
        let s = signature(fen: Self.startFEN)
        #expect(s.white == .initial)
        #expect(s.black == .initial)
        #expect(s.bishopColors == [.whiteLight, .whiteDark, .blackLight, .blackDark])
        #expect(s == .initial)
        #expect(s.value(.white) == 39)
        #expect(s.balance == 0)
        #expect(s.imbalance == .none)
    }

    @Test("Empaquetado: un nibble por lane 2·tipo + color")
    func packingLayout() {
        let s = MaterialSignature.initial
        // Lane 0 = peón negro, 1 = peón blanco, 2 = caballo negro … 9 = dama blanca.
        let expected: [UInt64] = [8, 8, 2, 2, 2, 2, 2, 2, 1, 1]
        for (lane, count) in expected.enumerated() {
            #expect((s.rawValue >> UInt64(4 * lane)) & 0xF == count)
        }
        #expect(s.rawValue >> 40 == 0xF)
        #expect(s.rawValue >> 44 == 0)
        #expect(MaterialSignature.lane(.queen, .white) == 9)
        #expect(MaterialSignature.lane(.pawn, .black) == 0)
    }

    @Test("Colores de los alfiles por casilla")
    func bishopSquareColors() {
        // Blancas: alfil en c1 (oscura). Negras: alfil en c8 (clara).
        let s = signature(fen: "2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1")
        #expect(s.bishopColors == [.whiteDark, .blackLight])
        #expect(s.hasOppositeColoredBishops)
        #expect(!s.hasSameColoredBishops)
        // Blancas: alfil en f1 (clara). Negras: c8 (clara).
        let same = signature(fen: "2b1k3/8/8/8/8/8/8/4KB2 w - - 0 1")
        #expect(same.hasSameColoredBishops)
        #expect(!same.hasOppositeColoredBishops)
    }

    @Test("Subíndice, saturación y cambio de colores")
    func subscriptAndSwap() {
        var s = MaterialSignature(rawValue: 0)
        s[.knight, .white] = 3
        s[.rook, .black] = 20
        #expect(s[.knight, .white] == 3)
        #expect(s[.rook, .black] == 15)
        s[.rook, .black] = 1
        s.bishopColors = [.whiteLight]
        let swapped = s.colorSwapped
        #expect(swapped[.knight, .black] == 3)
        #expect(swapped[.rook, .white] == 1)
        #expect(swapped.bishopColors == [.blackLight])

        var rng = SplitMix64(seed: 7)
        for _ in 0 ..< 2000 {
            let r = MaterialSignature.random(using: &rng, anyBishopColors: true)
            #expect(r.colorSwapped.colorSwapped == r)
            #expect(r.colorSwapped.balance == -r.balance)
        }
    }

    @Test("Valor y diferencias")
    func valueAndDifference() {
        let s = sig("DTTAPPPPP-DTCCPPPPPP")
        #expect(s.value(.white) == 9 + 10 + 3 + 5)
        #expect(s.value(.black) == 9 + 5 + 6 + 6)
        #expect(s.balance == 1)
        #expect(s.difference(.rook) == 1)
        #expect(s.difference(.knight) == -2)
    }

    @Test("Desequilibrios", arguments: [
        ("TPPP-APPPP", MaterialImbalance.exchange(up: .white, pawnDelta: -1)),
        ("APPPP-TPPP", .exchange(up: .black, pawnDelta: -1)),
        ("TAPPP-TPPP", .minorPiece(up: .white, pawnDelta: 0)),
        ("TAPP-TCPP", .bishopForKnight(bishopSide: .white, pawnDelta: 0)),
        ("DPP-TTPP", .queenForRooks(queenSide: .white, pawnDelta: 0)),
        ("TCPP-DPP", .queenForRookAndMinor(queenSide: .black, pawnDelta: 0)),
        ("TPP-TP", .pawns(up: .white, count: 1)),
        ("T-T", .none),
    ])
    func imbalances(text: String, expected: MaterialImbalance) {
        #expect(sig(text).imbalance == expected)
    }
}

@Suite("Notación")
struct MaterialNotationTests {
    @Test("Scoutfish")
    func scoutfish() throws {
        let parsed = try #require(MaterialSignature.parse("KRBKRN", notation: .scoutfish))
        #expect(parsed.signature.white == PieceCounts(bishops: 1, rooks: 1))
        #expect(parsed.signature.black == PieceCounts(knights: 1, rooks: 1))
        #expect(!parsed.includesPawns)
        #expect(parsed.signature.formatted(.scoutfish) == "KRBKRN")

        let pawns = try #require(MaterialSignature("KRPPKR", notation: .scoutfish))
        #expect(pawns[.pawn, .white] == 2)
        #expect(MaterialSignature.initial.formatted(.scoutfish) == "KQRRBBNNPPPPPPPPKQRRBBNNPPPPPPPP")
        #expect(MaterialSignature("krbkrn", notation: .scoutfish) != nil)
    }

    @Test("ChessBase en español", arguments: ["TA-TC", "T-T", "R-R", "T-R", "DT-D", "AA-CC", "TTAC-TTAA"])
    func chessBaseRoundTrip(text: String) throws {
        let s = try #require(MaterialSignature(text, notation: .chessBaseSpanish))
        #expect(s.formatted(.chessBaseSpanish) == text)
    }

    @Test("ChessBase: peones, inglés y variantes de escritura")
    func chessBaseVariants() throws {
        let parsed = try #require(MaterialSignature.parse("T+P – T", notation: .chessBaseSpanish))
        #expect(parsed.includesPawns)
        #expect(parsed.signature.white == PieceCounts(pawns: 1, rooks: 1))
        #expect(parsed.signature.black == PieceCounts(rooks: 1))
        #expect(parsed.signature.formatted(.chessBaseSpanish, includePawns: true) == "TP-T")

        let english = try #require(MaterialSignature("RB-RN", notation: .chessBaseEnglish))
        #expect(english == sig("TA-TC"))
        #expect(english.formatted(.chessBaseEnglish) == "RB-RN")
        #expect(sig("R-R").formatted(.chessBaseEnglish) == "K-K")
        #expect(MaterialSignature.initial.description == "DTTAACCPPPPPPPP-DTTAACCPPPPPPPP")
    }

    @Test("Textos no válidos", arguments: [
        ("TA", MaterialNotation.chessBaseSpanish), ("TX-T", .chessBaseSpanish), ("T-T-T", .chessBaseSpanish),
        ("-T", .chessBaseSpanish), ("RBKRN", .scoutfish), ("KRKRKR", .scoutfish), ("KRXKR", .scoutfish),
    ])
    func invalid(text: String, notation: MaterialNotation) {
        #expect(MaterialSignature(text, notation: notation) == nil)
    }
}
