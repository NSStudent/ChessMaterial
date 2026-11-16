import ChessMaterial

/// Los 12 bitboards (lanes de Polyglot: `2·tipo + color`, negro 0, blanco 1) de la
/// colocación de un FEN.
func bitboards(fen: String) -> [UInt64] {
    var lanes = [UInt64](repeating: 0, count: 12)
    let placement = fen.split(separator: " ").first ?? ""
    var rank = 7
    var file = 0
    for ch in placement {
        if ch == "/" {
            rank -= 1
            file = 0
        } else if let skip = ch.wholeNumberValue {
            file += skip
        } else {
            let type: Int = switch ch.lowercased() {
            case "p": 0
            case "n": 1
            case "b": 2
            case "r": 3
            case "q": 4
            default: 5
            }
            let color = ch.isUppercase ? 1 : 0
            lanes[2 * type + color] |= 1 << UInt64(8 * rank + file)
            file += 1
        }
    }
    return lanes
}

func signature(fen: String) -> MaterialSignature {
    MaterialSignature(bitboards: bitboards(fen: fen))
}

func sig(_ text: String) -> MaterialSignature {
    MaterialSignature(text, notation: .chessBaseSpanish)!
}

/// SplitMix64: generador reproducible para las pruebas de propiedades.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension MaterialSignature {
    /// Firma aleatoria: recuentos con sesgo hacia valores reales y colores de alfil
    /// coherentes con el número de alfiles (o del todo libres si `anyBishopColors`).
    static func random(using rng: inout SplitMix64, anyBishopColors: Bool = false) -> MaterialSignature {
        var s = MaterialSignature(rawValue: 0)
        for color in MaterialColor.allCases {
            for piece in MaterialPiece.allCases {
                let typical: ClosedRange<Int> = switch piece {
                case .pawn: 0 ... 8
                case .queen: 0 ... 2
                default: 0 ... 3
                }
                // Uno de cada 20 valores en todo el rango del nibble.
                s[piece, color] = Int.random(in: 0 ... 19, using: &rng) == 0
                    ? Int.random(in: 0 ... 15, using: &rng)
                    : Int.random(in: typical, using: &rng)
            }
        }
        if anyBishopColors {
            s.bishopColors = BishopSquareColors(rawValue: UInt8.random(in: 0 ... 15, using: &rng))
        } else {
            var colors: BishopSquareColors = []
            for color in MaterialColor.allCases {
                switch s[.bishop, color] {
                case 0: break
                case 1: colors.insert(Bool.random(using: &rng) ? .light(color) : .dark(color))
                default:
                    switch Int.random(in: 0 ... 2, using: &rng) {
                    case 0: colors.insert(.light(color))
                    case 1: colors.insert(.dark(color))
                    default: colors.formUnion([.light(color), .dark(color)])
                    }
                }
            }
            s.bishopColors = colors
        }
        return s
    }
}

extension ClosedRange<Int> {
    static func random(in bounds: ClosedRange<Int>, using rng: inout SplitMix64) -> ClosedRange<Int> {
        let a = Int.random(in: bounds, using: &rng)
        let b = Int.random(in: bounds, using: &rng)
        return Swift.min(a, b) ... Swift.max(a, b)
    }
}

extension MaterialQuery {
    /// Consulta aleatoria: cada rango se deja libre la mitad de las veces.
    static func random(using rng: inout SplitMix64) -> MaterialQuery {
        func ranges(_ any: PieceRanges, _ bounds: ClosedRange<Int>, _ minorBounds: ClosedRange<Int>) -> PieceRanges {
            var r = any
            for piece in MaterialPiece.allCases where Bool.random(using: &rng) {
                r[piece] = .random(in: bounds, using: &rng)
            }
            if Int.random(in: 0 ... 3, using: &rng) == 0 { r.minors = .random(in: minorBounds, using: &rng) }
            return r
        }
        var q = MaterialQuery()
        if Bool.random(using: &rng) { q.white = ranges(.anyCount, 0 ... 4, 0 ... 5) }
        if Bool.random(using: &rng) { q.black = ranges(.anyCount, 0 ... 4, 0 ... 5) }
        if Int.random(in: 0 ... 2, using: &rng) == 0 { q.difference = ranges(.anyDifference, -3 ... 3, -3 ... 3) }
        q.bishops = [BishopCondition.any, .any, .opposite, .same].randomElement(using: &rng)!
        q.ignoreColors = Bool.random(using: &rng)
        return q
    }

    /// Una firma que cumple la consulta (si encuentra alguna en `tries` intentos).
    func sampleMatching(using rng: inout SplitMix64, tries: Int = 400) -> MaterialSignature? {
        for _ in 0 ..< tries {
            var s = MaterialSignature(rawValue: 0)
            for piece in MaterialPiece.allCases {
                let w = white[piece].clamped(to: 0 ... 15)
                let b = black[piece].clamped(to: 0 ... 15)
                s[piece, .white] = Int.random(in: w, using: &rng)
                s[piece, .black] = Int.random(in: b, using: &rng)
            }
            s.bishopColors = BishopSquareColors(rawValue: UInt8.random(in: 0 ... 15, using: &rng))
            if matches(s) { return s }
            if ignoreColors, matches(s.colorSwapped) { return s.colorSwapped }
        }
        return nil
    }
}
