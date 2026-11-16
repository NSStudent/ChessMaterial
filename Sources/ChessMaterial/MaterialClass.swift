// MaterialClass.swift
// ChessMaterial
//
// Partición del material en 56 clases (de 64 posibles) para `materialVisited`.

/// Clase de material de una posición. Cada posición cae en **una sola** clase; la
/// partida guarda el OR de `1 << clase` de todas sus posiciones (`materialVisited`,
/// 8 B). Una consulta solo puede cumplirse en la partida si
/// `visited & MaterialClass.classesMatching(query) != 0`.
///
/// Reglas de la partición (en este orden):
///
/// - Las clases **no dependen del color**: `clase(s) == clase(s.colorSwapped)`.
/// - Los recuentos de piezas se **saturan en 3** antes de clasificar (tres o más damas
///   cuentan como tres). Los peones solo entran como «hay alguno» y como diferencia
///   saturada en ±2.
/// - **Final** (`isEnding`): cada bando tiene como mucho 2 piezas y, si hay alguna
///   dama, como mucho 3 piezas entre los dos bandos. El resto es **medio juego**.
/// - Medio juego: «pleno» si hay 10 o más piezas entre los dos bandos; si no, «reducido».
///
/// Los números son parte del formato del índice: **no se renumeran nunca**. Las clases
/// nuevas van en los huecos 56–63.
public enum MaterialClass: Int, CaseIterable, Sendable, Codable {
    // MARK: Finales sin piezas (0–3)
    /// R-R sin peones.
    case bareKings = 0
    /// Solo peones, mismos peones por bando.
    case pawnsEqual = 1
    /// Solo peones, un peón de diferencia (incluye R+P contra R).
    case pawnsUpOne = 2
    /// Solo peones, dos o más de diferencia.
    case pawnsUpTwoOrMore = 3

    // MARK: Finales de torres (4–9)
    /// Una o dos torres contra rey (con o sin peones).
    case rookVsBare = 4
    /// T-T, mismos peones.
    case rookRookEqual = 5
    /// T-T, un peón de diferencia (incluye T+P contra T).
    case rookRookUpOne = 6
    /// T-T, dos o más peones de diferencia.
    case rookRookUpTwoOrMore = 7
    /// TT-TT.
    case twoRooksEach = 8
    /// TT-T.
    case twoRooksVsRook = 9

    // MARK: Finales de menores (10–16)
    /// Una o dos menores contra rey.
    case minorVsBare = 10
    /// A-A del mismo color (o color desconocido).
    case bishopsSameColor = 11
    /// A-A de distinto color.
    case bishopsOppositeColor = 12
    /// A-C.
    case bishopVsKnight = 13
    /// C-C.
    case knightVsKnight = 14
    /// Dos menores contra una (AA-A, AC-C…).
    case twoMinorsVsMinor = 15
    /// Dos menores por bando.
    case twoMinorsEach = 16

    // MARK: Finales de torre y menor (17–25)
    /// T contra menor, y el bando de la menor tiene al menos un peón más (calidad por peón).
    case rookVsMinorWithPawns = 17
    /// T contra menor, sin peones de compensación.
    case rookVsMinor = 18
    /// T+menor contra T.
    case rookMinorVsRook = 19
    /// TA-TA del mismo color.
    case rookBishopSameColor = 20
    /// TA-TA de distinto color.
    case rookBishopOppositeColor = 21
    /// TC-TC.
    case rookKnightEach = 22
    /// TA-TC.
    case rookBishopVsRookKnight = 23
    /// T contra dos menores.
    case rookVsTwoMinors = 24
    /// El resto de finales sin damas con torres y menores (TT-TA, TA-A, TT-C…).
    case otherRookMinorEnding = 25

    // MARK: Finales con damas (26–31)
    /// Dama (y quizá otra pieza) contra rey.
    case queenVsBare = 26
    /// D-D, mismos peones.
    case queenQueenEqual = 27
    /// D-D, con diferencia de peones.
    case queenQueenUp = 28
    /// D-T.
    case queenVsRook = 29
    /// Dama contra piezas sin dama (D-A, D-TT, DT-C…), salvo D-T.
    case queenVsPieces = 30
    /// D+pieza contra D (DT-D, DA-D, DD-D).
    case queenPieceVsQueen = 31

    // MARK: Medio juego con damas en los dos bandos (32–41)
    case queensFullEqual = 32
    /// Calidad de menos con al menos un peón de compensación.
    case queensFullExchangeForPawns = 33
    case queensFullExchange = 34
    case queensFullMinorPiece = 35
    case queensFullOther = 36
    case queensReducedEqual = 37
    case queensReducedExchangeForPawns = 38
    case queensReducedExchange = 39
    case queensReducedMinorPiece = 40
    case queensReducedOther = 41

    // MARK: Medio juego sin damas (42–51)
    case noQueensFullEqual = 42
    case noQueensFullExchangeForPawns = 43
    case noQueensFullExchange = 44
    case noQueensFullMinorPiece = 45
    case noQueensFullOther = 46
    case noQueensReducedEqual = 47
    case noQueensReducedExchangeForPawns = 48
    case noQueensReducedExchange = 49
    case noQueensReducedMinorPiece = 50
    case noQueensReducedOther = 51

    // MARK: Otros medios juegos (52–55)
    /// Distinto número de damas (D contra TT, D contra piezas…), pleno.
    case queenImbalanceFull = 52
    /// Distinto número de damas, reducido.
    case queenImbalanceReduced = 53
    /// Damas en los dos bandos, resto igual y alfiles de distinto color (uno por bando).
    case queensOppositeBishops = 54
    /// Sin damas, resto igual y alfiles de distinto color (uno por bando).
    case noQueensOppositeBishops = 55

    /// Máscara con todas las clases.
    public static let allMask: UInt64 = (1 << UInt64(allCases.count)) - 1

    /// Nombre corto en español.
    public var name: String { Self.names[rawValue] }

    /// Clase de una firma.
    @inlinable
    public init(_ s: MaterialSignature) {
        self = Self.classify(Features(s))
    }

    /// Máscara de un bit con la clase de la firma.
    @inlinable
    public static func classes(of s: MaterialSignature) -> UInt64 {
        1 << UInt64(classify(Features(s)).rawValue)
    }

    /// OR de las clases de una secuencia de firmas (`materialVisited` de una partida).
    public static func visited<S: Sequence>(_ signatures: S) -> UInt64 where S.Element == MaterialSignature {
        signatures.reduce(0) { $0 | classes(of: $1) }
    }

    /// Máscara de las clases (bits `1 << rawValue`) de una lista de clases.
    public static func mask(_ classes: some Sequence<MaterialClass>) -> UInt64 {
        classes.reduce(0) { $0 | (1 << UInt64($1.rawValue)) }
    }

    /// Clases de una máscara.
    public static func members(of mask: UInt64) -> [MaterialClass] {
        allCases.filter { mask & (1 << UInt64($0.rawValue)) != 0 }
    }
}

// MARK: - Rasgos

extension MaterialClass {
    /// Lo único que mira la clasificación. Con esto `classesMatching` puede enumerar
    /// todos los valores posibles de forma exacta.
    @usableFromInline
    struct Features: Hashable, Sendable {
        // Recuentos saturados en 3: [negro, blanco].
        @usableFromInline var q: (UInt8, UInt8)
        @usableFromInline var r: (UInt8, UInt8)
        @usableFromInline var b: (UInt8, UInt8)
        @usableFromInline var n: (UInt8, UInt8)
        /// Alfiles de distinto color; solo puede ser `true` con un alfil por bando.
        @usableFromInline var oppositeBishops: Bool
        /// Peones blancos − negros, saturado en ±2.
        @usableFromInline var pawnDelta: Int8
        /// Ningún peón en el tablero.
        @usableFromInline var noPawns: Bool

        @inlinable
        init(q: (UInt8, UInt8), r: (UInt8, UInt8), b: (UInt8, UInt8), n: (UInt8, UInt8), oppositeBishops: Bool, pawnDelta: Int8, noPawns: Bool) {
            self.q = q
            self.r = r
            self.b = b
            self.n = n
            self.oppositeBishops = oppositeBishops
            self.pawnDelta = pawnDelta
            self.noPawns = noPawns
        }

        @inlinable
        init(_ s: MaterialSignature) {
            @inline(__always) func c(_ p: MaterialPiece) -> (UInt8, UInt8) {
                (UInt8(min(s[p, .black], 3)), UInt8(min(s[p, .white], 3)))
            }
            let pw = s[.pawn, .white]
            let pb = s[.pawn, .black]
            self.init(
                q: c(.queen),
                r: c(.rook),
                b: c(.bishop),
                n: c(.knight),
                oppositeBishops: s.hasOppositeColoredBishops,
                pawnDelta: Int8(max(-2, min(2, pw - pb))),
                noPawns: pw + pb == 0
            )
        }

        @usableFromInline
        static func == (l: Features, r: Features) -> Bool {
            l.q == r.q && l.r == r.r && l.b == r.b && l.n == r.n && l.oppositeBishops == r.oppositeBishops
                && l.pawnDelta == r.pawnDelta && l.noPawns == r.noPawns
        }

        @usableFromInline
        func hash(into h: inout Hasher) {
            h.combine(q.0); h.combine(q.1); h.combine(r.0); h.combine(r.1)
            h.combine(b.0); h.combine(b.1); h.combine(n.0); h.combine(n.1)
            h.combine(oppositeBishops); h.combine(pawnDelta); h.combine(noPawns)
        }
    }

    /// Un bando visto por la clasificación.
    @usableFromInline
    struct Side {
        @usableFromInline var q: Int, r: Int, b: Int, n: Int
        /// Peones de este bando menos los del otro (saturado).
        @usableFromInline var pawnEdge: Int
        @inlinable var minors: Int { b + n }
        @inlinable var pieces: Int { q + r + b + n }
        @inlinable init(q: Int, r: Int, b: Int, n: Int, pawnEdge: Int) {
            self.q = q; self.r = r; self.b = b; self.n = n; self.pawnEdge = pawnEdge
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    @usableFromInline
    static func classify(_ f: Features) -> MaterialClass {
        let delta = Int(f.pawnDelta)
        var w = Side(q: Int(f.q.1), r: Int(f.r.1), b: Int(f.b.1), n: Int(f.n.1), pawnEdge: delta)
        var k = Side(q: Int(f.q.0), r: Int(f.r.0), b: Int(f.b.0), n: Int(f.n.0), pawnEdge: -delta)
        // Orden canónico: «a» es el bando con más piezas (luego más valor, luego más peones),
        // para que la clase no dependa del color.
        func key(_ s: Side) -> (Int, Int, Int, Int, Int, Int) { (s.pieces, s.q, s.r, s.b, s.n, s.pawnEdge) }
        if key(k) > key(w) { swap(&w, &k) }
        let a = w
        let o = k
        let absDelta = abs(delta)
        let total = a.pieces + o.pieces
        let anyQueen = a.q + o.q > 0
        let isEnding = a.pieces <= 2 && o.pieces <= 2 && (!anyQueen || total <= 3)

        if isEnding {
            if !anyQueen {
                // Sin piezas.
                if total == 0 {
                    if f.noPawns { return .bareKings }
                    return absDelta == 0 ? .pawnsEqual : (absDelta == 1 ? .pawnsUpOne : .pawnsUpTwoOrMore)
                }
                let rooksOnly = a.minors + o.minors == 0
                let minorsOnly = a.r + o.r == 0
                if rooksOnly {
                    if o.pieces == 0 { return .rookVsBare }
                    if a.r == 1, o.r == 1 {
                        return absDelta == 0 ? .rookRookEqual : (absDelta == 1 ? .rookRookUpOne : .rookRookUpTwoOrMore)
                    }
                    return a.r == 2 && o.r == 2 ? .twoRooksEach : .twoRooksVsRook
                }
                if minorsOnly {
                    if o.pieces == 0 { return .minorVsBare }
                    if a.pieces == 1, o.pieces == 1 {
                        if a.b == 1, o.b == 1 { return f.oppositeBishops ? .bishopsOppositeColor : .bishopsSameColor }
                        if a.n == 1, o.n == 1 { return .knightVsKnight }
                        return .bishopVsKnight
                    }
                    return a.pieces == 2 && o.pieces == 2 ? .twoMinorsEach : .twoMinorsVsMinor
                }
                // Torres y menores.
                if a.pieces == 1, o.pieces == 1 {
                    // T contra menor: el bando de la menor compensa con peones.
                    let minorSide = a.r == 1 ? o : a
                    return minorSide.pawnEdge >= 1 ? .rookVsMinorWithPawns : .rookVsMinor
                }
                if a.pieces == 2, o.pieces == 1, a.r == 1, a.minors == 1, o.r == 1 { return .rookMinorVsRook }
                if a.pieces == 2, o.pieces == 2, a.r == 1, o.r == 1, a.minors == 1, o.minors == 1 {
                    if a.b == 1, o.b == 1 { return f.oppositeBishops ? .rookBishopOppositeColor : .rookBishopSameColor }
                    if a.n == 1, o.n == 1 { return .rookKnightEach }
                    return .rookBishopVsRookKnight
                }
                if a.pieces == 2, a.minors == 2, o.pieces == 1, o.r == 1 { return .rookVsTwoMinors }
                return .otherRookMinorEnding
            }
            // Finales con damas.
            if o.pieces == 0 { return .queenVsBare }
            if a.q >= 1, o.q >= 1 {
                if a.pieces == 1, o.pieces == 1 { return absDelta == 0 ? .queenQueenEqual : .queenQueenUp }
                return .queenPieceVsQueen
            }
            let queenSide = a.q >= 1 ? a : o
            let other = a.q >= 1 ? o : a
            if queenSide.pieces == 1, other.pieces == 1, other.r == 1 { return .queenVsRook }
            return .queenVsPieces
        }

        // Medio juego.
        let full = total >= 10
        if a.q != o.q { return full ? .queenImbalanceFull : .queenImbalanceReduced }
        let queens = a.q > 0
        let dr = a.r - o.r
        let dm = a.minors - o.minors
        enum Kind { case equal, exchangeForPawns, exchange, minor, other }
        let kind: Kind
        if dr == 0, dm == 0 {
            if f.oppositeBishops { return queens ? .queensOppositeBishops : .noQueensOppositeBishops }
            kind = .equal
        } else if abs(dr) == 1, dm == -dr {
            let minorSide = dr > 0 ? o : a
            kind = minorSide.pawnEdge >= 1 ? .exchangeForPawns : .exchange
        } else if dr == 0, abs(dm) == 1 {
            kind = .minor
        } else {
            kind = .other
        }
        let offset: Int = switch kind {
        case .equal: 0
        case .exchangeForPawns: 1
        case .exchange: 2
        case .minor: 3
        case .other: 4
        }
        let base = queens ? (full ? 32 : 37) : (full ? 42 : 47)
        return MaterialClass(rawValue: base + offset)!
    }
}

// MARK: - Consultas

extension MaterialClass {
    /// Clases que contienen al menos una firma que cumple la consulta (sin mirar la duración).
    ///
    /// Es **exacta respecto a la partición**: enumera, por tipo de pieza, todos los
    /// recuentos 0…15 de cada bando que cumplen la consulta, los lleva a los rasgos que
    /// mira la clasificación y clasifica cada combinación. Como la consulta se descompone
    /// por tipo (dama, torre, alfil+caballo juntos por la fila «menores» y la condición de
    /// alfiles, peones), ninguna clase con una firma que cumple puede quedar fuera.
    /// `ignoreColors` no cambia la máscara porque las clases no dependen del color.
    public static func classesMatching(_ query: MaterialQuery) -> UInt64 {
        // Damas y torres: pares (negro, blanco) saturados.
        func pairs(_ piece: MaterialPiece) -> [(UInt8, UInt8)] {
            var seen = Set<Int>()
            var out: [(UInt8, UInt8)] = []
            for wc in 0 ... 15 where query.white[piece].contains(wc) {
                for bc in 0 ... 15 where query.black[piece].contains(bc) && query.difference[piece].contains(wc - bc) {
                    let pair = (UInt8(min(bc, 3)), UInt8(min(wc, 3)))
                    if seen.insert(Int(pair.0) * 4 + Int(pair.1)).inserted { out.append(pair) }
                }
            }
            return out
        }
        let queens = pairs(.queen)
        let rooks = pairs(.rook)

        // Alfiles y caballos juntos (fila «menores» y condición de alfiles).
        struct Minor: Hashable { var b0, b1, n0, n1: UInt8; var opposite: Bool }
        var minors = Set<Minor>()
        let q = query
        for wb in 0 ... 15 where q.white.bishops.contains(wb) {
            for bb in 0 ... 15 where q.black.bishops.contains(bb) && q.difference.bishops.contains(wb - bb) {
                // Valores posibles de «alfiles de distinto color».
                let oneEach = wb == 1 && bb == 1
                let oppositeOptions: [Bool] = switch q.bishops {
                case .any: oneEach ? [false, true] : [false]
                case .opposite: oneEach ? [true] : []
                case .same: oneEach ? [false] : []
                }
                if oppositeOptions.isEmpty { continue }
                for wn in 0 ... 15 where q.white.knights.contains(wn) && q.white.minors.contains(wb + wn) {
                    for bn in 0 ... 15 where q.black.knights.contains(bn) && q.black.minors.contains(bb + bn)
                        && q.difference.knights.contains(wn - bn) && q.difference.minors.contains(wb + wn - bb - bn) {
                        for opposite in oppositeOptions {
                            minors.insert(Minor(
                                b0: UInt8(min(bb, 3)), b1: UInt8(min(wb, 3)),
                                n0: UInt8(min(bn, 3)), n1: UInt8(min(wn, 3)),
                                opposite: opposite
                            ))
                        }
                    }
                }
            }
        }

        // Peones: (diferencia saturada, sin peones).
        struct Pawns: Hashable { var delta: Int8; var none: Bool }
        var pawns = Set<Pawns>()
        for wp in 0 ... 15 where q.white.pawns.contains(wp) {
            for bp in 0 ... 15 where q.black.pawns.contains(bp) && q.difference.pawns.contains(wp - bp) {
                pawns.insert(Pawns(delta: Int8(max(-2, min(2, wp - bp))), none: wp + bp == 0))
            }
        }

        var mask: UInt64 = 0
        for qq in queens {
            for rr in rooks {
                for m in minors {
                    for p in pawns {
                        let f = Features(
                            q: qq, r: rr, b: (m.b0, m.b1), n: (m.n0, m.n1),
                            oppositeBishops: m.opposite, pawnDelta: p.delta, noPawns: p.none
                        )
                        mask |= 1 << UInt64(classify(f).rawValue)
                        if mask == allMask { return mask }
                    }
                }
            }
        }
        return mask
    }
}

// MARK: - Nombres

extension MaterialClass {
    static let names: [String] = [
        "R-R sin peones", "Peones iguales", "Peones +1", "Peones +2 o más",
        "T contra R", "T-T peones iguales", "T-T +1 peón", "T-T +2 peones o más", "TT-TT", "TT-T",
        "Menor contra R", "A-A mismo color", "A-A distinto color", "A-C", "C-C", "Dos menores contra una", "Dos menores por bando",
        "T contra menor con peones", "T contra menor", "T+menor contra T", "TA-TA mismo color", "TA-TA distinto color", "TC-TC", "TA-TC", "T contra dos menores", "Otros finales de torre y menor",
        "D contra R", "D-D peones iguales", "D-D con peones de más", "D-T", "D contra piezas", "D+pieza contra D",
        "Con damas, pleno, igual", "Con damas, pleno, calidad por peón", "Con damas, pleno, calidad", "Con damas, pleno, pieza", "Con damas, pleno, otro",
        "Con damas, reducido, igual", "Con damas, reducido, calidad por peón", "Con damas, reducido, calidad", "Con damas, reducido, pieza", "Con damas, reducido, otro",
        "Sin damas, pleno, igual", "Sin damas, pleno, calidad por peón", "Sin damas, pleno, calidad", "Sin damas, pleno, pieza", "Sin damas, pleno, otro",
        "Sin damas, reducido, igual", "Sin damas, reducido, calidad por peón", "Sin damas, reducido, calidad", "Sin damas, reducido, pieza", "Sin damas, reducido, otro",
        "Damas desiguales, pleno", "Damas desiguales, reducido",
        "Con damas, alfiles de distinto color", "Sin damas, alfiles de distinto color",
    ]
}
