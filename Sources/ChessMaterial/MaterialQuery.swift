// MaterialQuery.swift
// ChessMaterial
//
// Consulta de material al estilo de la pestaña Material de ChessBase.

/// Rangos por tipo de pieza. Sirve para un bando (recuentos) o para la diferencia
/// blancas − negras.
public struct PieceRanges: Hashable, Sendable {
    public var pawns: ClosedRange<Int>
    public var knights: ClosedRange<Int>
    public var bishops: ClosedRange<Int>
    public var rooks: ClosedRange<Int>
    public var queens: ClosedRange<Int>
    /// Alfiles más caballos (la fila «Menores» de ChessBase).
    public var minors: ClosedRange<Int>

    public init(
        pawns: ClosedRange<Int>,
        knights: ClosedRange<Int>,
        bishops: ClosedRange<Int>,
        rooks: ClosedRange<Int>,
        queens: ClosedRange<Int>,
        minors: ClosedRange<Int>
    ) {
        self.pawns = pawns
        self.knights = knights
        self.bishops = bishops
        self.rooks = rooks
        self.queens = queens
        self.minors = minors
    }

    /// Cualquier recuento (0…15 por tipo).
    public static let anyCount = PieceRanges(pawns: 0 ... 15, knights: 0 ... 15, bishops: 0 ... 15, rooks: 0 ... 15, queens: 0 ... 15, minors: 0 ... 30)
    /// Cualquier diferencia.
    public static let anyDifference = PieceRanges(pawns: -15 ... 15, knights: -15 ... 15, bishops: -15 ... 15, rooks: -15 ... 15, queens: -15 ... 15, minors: -30 ... 30)

    /// Recuentos exactos.
    public static func exactly(_ counts: PieceCounts, pawns exactPawns: Bool = true) -> PieceRanges {
        PieceRanges(
            pawns: exactPawns ? counts.pawns ... counts.pawns : 0 ... 15,
            knights: counts.knights ... counts.knights,
            bishops: counts.bishops ... counts.bishops,
            rooks: counts.rooks ... counts.rooks,
            queens: counts.queens ... counts.queens,
            minors: counts.minors ... counts.minors
        )
    }

    @inlinable
    public subscript(piece: MaterialPiece) -> ClosedRange<Int> {
        get {
            switch piece {
            case .pawn: pawns
            case .knight: knights
            case .bishop: bishops
            case .rook: rooks
            case .queen: queens
            }
        }
        set {
            switch piece {
            case .pawn: pawns = newValue
            case .knight: knights = newValue
            case .bishop: bishops = newValue
            case .rook: rooks = newValue
            case .queen: queens = newValue
            }
        }
    }

    @inlinable
    func contains(_ c: PieceCounts) -> Bool {
        pawns.contains(c.pawns) && knights.contains(c.knights) && bishops.contains(c.bishops)
            && rooks.contains(c.rooks) && queens.contains(c.queens) && minors.contains(c.knights + c.bishops)
    }
}

/// Condición sobre los alfiles (solo tiene sentido con un alfil por bando).
public enum BishopCondition: Hashable, Sendable {
    case any
    /// Un alfil por bando, de distinto color.
    case opposite
    /// Un alfil por bando, del mismo color.
    case same

    @inlinable
    func accepts(_ s: MaterialSignature) -> Bool {
        switch self {
        case .any: true
        case .opposite: s.hasOppositeColoredBishops
        case .same: s.hasSameColoredBishops
        }
    }
}

/// Consulta de material.
///
/// Una posición cumple si cumple **a la vez** `white`, `black` y `difference`
/// (blancas − negras) y la condición de alfiles. Con `ignoreColors` también vale
/// la posición con los colores cambiados. Una partida cumple si alguna racha de
/// posiciones consecutivas que cumplen dura al menos `minimumPlies`.
public struct MaterialQuery: Hashable, Sendable {
    public var white: PieceRanges
    public var black: PieceRanges
    /// Modo diferencia: rangos de blancas − negras.
    public var difference: PieceRanges
    public var bishops: BishopCondition
    public var ignoreColors: Bool
    /// Duración mínima (estabilidad) en plies, contando posiciones consecutivas.
    public var minimumPlies: Int

    public init(
        white: PieceRanges = .anyCount,
        black: PieceRanges = .anyCount,
        difference: PieceRanges = .anyDifference,
        bishops: BishopCondition = .any,
        ignoreColors: Bool = false,
        minimumPlies: Int = 1
    ) {
        self.white = white
        self.black = black
        self.difference = difference
        self.bishops = bishops
        self.ignoreColors = ignoreColors
        self.minimumPlies = max(1, minimumPlies)
    }

    /// Material exacto de un texto («TA-TC», «KRPKR»…). Si el texto no nombra
    /// peones, los peones quedan libres.
    public init?(
        _ text: String,
        notation: MaterialNotation = .chessBaseSpanish,
        ignoreColors: Bool = false,
        minimumPlies: Int = 1
    ) {
        guard let parsed = MaterialSignature.parse(text, notation: notation) else { return nil }
        self.init(
            white: .exactly(parsed.signature.white, pawns: parsed.includesPawns),
            black: .exactly(parsed.signature.black, pawns: parsed.includesPawns),
            ignoreColors: ignoreColors,
            minimumPlies: minimumPlies
        )
    }

    /// Sin colores invertidos.
    @inlinable
    func matchesOriented(_ s: MaterialSignature) -> Bool {
        let w = s.white
        let b = s.black
        guard white.contains(w), black.contains(b) else { return false }
        let d = PieceCounts(
            pawns: w.pawns - b.pawns,
            knights: w.knights - b.knights,
            bishops: w.bishops - b.bishops,
            rooks: w.rooks - b.rooks,
            queens: w.queens - b.queens
        )
        return difference.contains(d) && bishops.accepts(s)
    }

    /// ¿Cumple esta posición?
    @inlinable
    public func matches(_ s: MaterialSignature) -> Bool {
        matchesOriented(s) || (ignoreColors && matchesOriented(s.colorSwapped))
    }

    /// Rachas de posiciones consecutivas que cumplen y duran al menos `minimumPlies`.
    /// Los índices son plies (0 = posición inicial).
    public func runs<S: Sequence>(in signatures: S) -> [Range<Int>] where S.Element == MaterialSignature {
        var result: [Range<Int>] = []
        var start: Int?
        var index = 0
        for s in signatures {
            if matches(s) {
                if start == nil { start = index }
            } else if let open = start {
                if index - open >= minimumPlies { result.append(open ..< index) }
                start = nil
            }
            index += 1
        }
        if let open = start, index - open >= minimumPlies { result.append(open ..< index) }
        return result
    }

    /// Primera racha que cumple, o `nil`.
    public func firstMatch<S: Sequence>(in signatures: S) -> Range<Int>? where S.Element == MaterialSignature {
        var start: Int?
        var index = 0
        for s in signatures {
            if matches(s) {
                if start == nil { start = index }
            } else if let open = start {
                if index - open >= minimumPlies { return open ..< index }
                start = nil
            }
            index += 1
        }
        if let open = start, index - open >= minimumPlies { return open ..< index }
        return nil
    }

    /// ¿Hay en la partida una racha que cumpla?
    public func matchesGame<S: Sequence>(_ signatures: S) -> Bool where S.Element == MaterialSignature {
        var run = 0
        for s in signatures {
            if matches(s) {
                run += 1
                if run >= minimumPlies { return true }
            } else {
                run = 0
            }
        }
        return false
    }

    /// Clases de material que pueden contener posiciones que cumplen (ver ``MaterialClass``).
    public var classMask: UInt64 { MaterialClass.classesMatching(self) }
}

/// Seguimiento incremental de una consulta durante la reproducción de una partida.
public struct MaterialQueryTracker: Sendable {
    public let query: MaterialQuery
    public private(set) var ply = 0
    public private(set) var currentRunStart: Int?
    public private(set) var firstMatch: Range<Int>?

    public init(_ query: MaterialQuery) { self.query = query }

    /// Añade la posición siguiente. Devuelve `true` en cuanto la partida cumple.
    @discardableResult
    public mutating func append(_ s: MaterialSignature) -> Bool {
        defer { ply += 1 }
        if query.matches(s) {
            if currentRunStart == nil { currentRunStart = ply }
            if firstMatch == nil, let start = currentRunStart, ply + 1 - start >= query.minimumPlies {
                firstMatch = start ..< ply + 1
            }
        } else {
            currentRunStart = nil
        }
        return firstMatch != nil
    }
}
