// MaterialSignature.swift
// ChessMaterial
//
// Recuento de material de una posición empaquetado en un `UInt64`.

/// Tipo de pieza que cuenta como material (el rey no cuenta).
///
/// Los valores siguen el orden de tipos de Polyglot:
/// peón 0, caballo 1, alfil 2, torre 3, dama 4 (rey 5 no se guarda).
public enum MaterialPiece: Int, CaseIterable, Sendable, Codable {
    case pawn = 0
    case knight = 1
    case bishop = 2
    case rook = 3
    case queen = 4

    /// Valor clásico en peones: 1, 3, 3, 5, 9.
    @inlinable
    public var value: Int {
        switch self {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        }
    }

    /// Las cuatro piezas (sin peón), de mayor a menor: D, T, A, C.
    public static let pieces: [MaterialPiece] = [.queen, .rook, .bishop, .knight]
}

/// Color en el orden de lanes de Polyglot: negro 0, blanco 1.
public enum MaterialColor: Int, CaseIterable, Sendable, Codable {
    case black = 0
    case white = 1

    @inlinable
    public var opposite: MaterialColor { self == .white ? .black : .white }
}

/// Casillas en las que tiene alfiles cada bando.
public struct BishopSquareColors: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let blackLight = BishopSquareColors(rawValue: 1 << 0)
    public static let blackDark = BishopSquareColors(rawValue: 1 << 1)
    public static let whiteLight = BishopSquareColors(rawValue: 1 << 2)
    public static let whiteDark = BishopSquareColors(rawValue: 1 << 3)

    @inlinable
    public static func light(_ color: MaterialColor) -> BishopSquareColors {
        BishopSquareColors(rawValue: 1 << UInt8(2 * color.rawValue))
    }

    @inlinable
    public static func dark(_ color: MaterialColor) -> BishopSquareColors {
        BishopSquareColors(rawValue: 1 << UInt8(2 * color.rawValue + 1))
    }

    /// Intercambia los colores de los bandos (las casillas no cambian).
    @inlinable
    public var colorSwapped: BishopSquareColors {
        BishopSquareColors(rawValue: ((rawValue & 0b0011) << 2) | ((rawValue & 0b1100) >> 2))
    }
}

/// Recuento de piezas de un bando.
public struct PieceCounts: Hashable, Sendable, Codable {
    public var pawns: Int
    public var knights: Int
    public var bishops: Int
    public var rooks: Int
    public var queens: Int

    public init(pawns: Int = 0, knights: Int = 0, bishops: Int = 0, rooks: Int = 0, queens: Int = 0) {
        self.pawns = pawns
        self.knights = knights
        self.bishops = bishops
        self.rooks = rooks
        self.queens = queens
    }

    @inlinable
    public subscript(piece: MaterialPiece) -> Int {
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

    /// Alfiles más caballos.
    @inlinable public var minors: Int { knights + bishops }
    /// Piezas sin contar peones ni rey.
    @inlinable public var pieces: Int { knights + bishops + rooks + queens }
    /// Valor en peones (1, 3, 3, 5, 9).
    @inlinable public var value: Int { pawns + 3 * (knights + bishops) + 5 * rooks + 9 * queens }

    public static let initial = PieceCounts(pawns: 8, knights: 2, bishops: 2, rooks: 2, queens: 1)
}

/// Material de una posición: cuántas piezas de cada tipo tiene cada bando y en
/// qué color de casilla están sus alfiles.
///
/// Se empaqueta en un `UInt64`:
///
/// | Bits | Contenido |
/// |---|---|
/// | 0–39 | 10 nibbles, uno por lane `2·tipo + color` (negro 0, blanco 1; peón 0 … dama 4), igual que los bitboards de Polyglot |
/// | 40–43 | ``BishopSquareColors``: negro claro, negro oscuro, blanco claro, blanco oscuro |
/// | 44–63 | a cero |
///
/// Cada nibble satura en 15, que no se alcanza en partidas reales (máximo 10 caballos).
public struct MaterialSignature: RawRepresentable, Hashable, Sendable, Codable {
    public var rawValue: UInt64

    @inlinable
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// Casillas claras (b1, a2, …): `0x55AA55AA55AA55AA`, con a1 = bit 0.
    public static let lightSquares: UInt64 = 0x55AA_55AA_55AA_55AA

    /// Crea la firma a partir de los 12 bitboards en orden de lanes de Polyglot:
    /// `2·tipo + color` con negro 0 y blanco 1 (peón negro, peón blanco, caballo negro…,
    /// rey blanco). Los dos bitboards de rey se ignoran.
    @inlinable
    public init<C: RandomAccessCollection>(bitboards: C) where C.Element == UInt64, C.Index == Int {
        precondition(bitboards.count >= 10, "Hacen falta los bitboards de peón a dama (10 lanes)")
        let base = bitboards.startIndex
        var raw: UInt64 = 0
        for lane in 0 ..< 10 {
            let count = UInt64(min(bitboards[base + lane].nonzeroBitCount, 15))
            raw |= count << UInt64(4 * lane)
        }
        let blackBishops = bitboards[base + 4]
        let whiteBishops = bitboards[base + 5]
        let light = Self.lightSquares
        if blackBishops & light != 0 { raw |= 1 << 40 }
        if blackBishops & ~light != 0 { raw |= 1 << 41 }
        if whiteBishops & light != 0 { raw |= 1 << 42 }
        if whiteBishops & ~light != 0 { raw |= 1 << 43 }
        self.rawValue = raw
    }

    /// Crea la firma desde recuentos. Si no se indican los colores de los alfiles,
    /// se ponen como en la posición inicial cuando hay dos o más y se dejan vacíos si hay uno.
    public init(white: PieceCounts, black: PieceCounts, bishopColors: BishopSquareColors? = nil) {
        self.rawValue = 0
        for piece in MaterialPiece.allCases {
            self[piece, .white] = white[piece]
            self[piece, .black] = black[piece]
        }
        if let bishopColors {
            self.bishopColors = bishopColors
        } else {
            var colors: BishopSquareColors = []
            if white.bishops >= 2 { colors.formUnion([.whiteLight, .whiteDark]) }
            if black.bishops >= 2 { colors.formUnion([.blackLight, .blackDark]) }
            self.bishopColors = colors
        }
    }

    /// Lane de Polyglot: `2·tipo + color`.
    @inlinable
    public static func lane(_ piece: MaterialPiece, _ color: MaterialColor) -> Int {
        2 * piece.rawValue + color.rawValue
    }

    @inlinable
    public subscript(piece: MaterialPiece, color: MaterialColor) -> Int {
        get { Int((rawValue >> UInt64(4 * Self.lane(piece, color))) & 0xF) }
        set {
            let shift = UInt64(4 * Self.lane(piece, color))
            let value = UInt64(max(0, min(newValue, 15)))
            rawValue = (rawValue & ~(0xF << shift)) | (value << shift)
        }
    }

    @inlinable
    public var bishopColors: BishopSquareColors {
        get { BishopSquareColors(rawValue: UInt8((rawValue >> 40) & 0xF)) }
        set { rawValue = (rawValue & ~(0xF << 40)) | (UInt64(newValue.rawValue & 0xF) << 40) }
    }

    @inlinable
    public func counts(_ color: MaterialColor) -> PieceCounts {
        PieceCounts(
            pawns: self[.pawn, color],
            knights: self[.knight, color],
            bishops: self[.bishop, color],
            rooks: self[.rook, color],
            queens: self[.queen, color]
        )
    }

    @inlinable public var white: PieceCounts { counts(.white) }
    @inlinable public var black: PieceCounts { counts(.black) }

    /// Piezas (sin peones ni rey) de un bando.
    @inlinable
    public func pieceCount(_ color: MaterialColor) -> Int {
        self[.knight, color] + self[.bishop, color] + self[.rook, color] + self[.queen, color]
    }

    /// Valor en peones de un bando.
    @inlinable
    public func value(_ color: MaterialColor) -> Int { counts(color).value }

    /// Valor de blancas menos valor de negras.
    @inlinable
    public var balance: Int { value(.white) - value(.black) }

    /// Diferencia por tipo: blancas menos negras.
    @inlinable
    public func difference(_ piece: MaterialPiece) -> Int { self[piece, .white] - self[piece, .black] }

    /// La misma firma con los colores cambiados.
    @inlinable
    public var colorSwapped: MaterialSignature {
        var raw: UInt64 = 0
        for lane in stride(from: 0, to: 10, by: 2) {
            let blackNibble = (rawValue >> UInt64(4 * lane)) & 0xF
            let whiteNibble = (rawValue >> UInt64(4 * (lane + 1))) & 0xF
            raw |= whiteNibble << UInt64(4 * lane)
            raw |= blackNibble << UInt64(4 * (lane + 1))
        }
        var swapped = MaterialSignature(rawValue: raw)
        swapped.bishopColors = bishopColors.colorSwapped
        return swapped
    }

    /// Un alfil por bando, en casillas de distinto color.
    @inlinable
    public var hasOppositeColoredBishops: Bool {
        guard self[.bishop, .white] == 1, self[.bishop, .black] == 1 else { return false }
        let c = bishopColors
        return c == [.whiteLight, .blackDark] || c == [.whiteDark, .blackLight]
    }

    /// Un alfil por bando, en casillas del mismo color.
    @inlinable
    public var hasSameColoredBishops: Bool {
        guard self[.bishop, .white] == 1, self[.bishop, .black] == 1 else { return false }
        let c = bishopColors
        return c == [.whiteLight, .blackLight] || c == [.whiteDark, .blackDark]
    }

    /// Solo recuentos (sin colores de alfiles): sirve para agrupar.
    @inlinable
    public var countsOnly: MaterialSignature {
        MaterialSignature(rawValue: rawValue & 0xFF_FFFF_FFFF)
    }

    /// Desequilibrio de material (ver ``MaterialImbalance``).
    public var imbalance: MaterialImbalance { MaterialImbalance(self) }

    public static let initial = MaterialSignature(white: .initial, black: .initial)
}

/// Desequilibrio entre los bandos, al estilo de la pestaña Material de ChessBase.
///
/// `pawnDelta` es siempre peones del bando que tiene la ventaja de piezas menos
/// los del otro (negativo = compensación en peones para el otro bando).
public enum MaterialImbalance: Hashable, Sendable {
    /// Mismo material exacto.
    case none
    /// Mismas piezas; un bando tiene `count` peones más.
    case pawns(up: MaterialColor, count: Int)
    /// Torre contra pieza menor (calidad), con el resto de piezas igual.
    case exchange(up: MaterialColor, pawnDelta: Int)
    /// Una pieza menor de más, con el resto de piezas igual.
    case minorPiece(up: MaterialColor, pawnDelta: Int)
    /// Alfil contra caballo, con el resto de piezas igual (`bishopSide` tiene el alfil).
    case bishopForKnight(bishopSide: MaterialColor, pawnDelta: Int)
    /// Dama contra dos torres, con el resto de piezas igual.
    case queenForRooks(queenSide: MaterialColor, pawnDelta: Int)
    /// Dama contra torre y menor, con el resto igual.
    case queenForRookAndMinor(queenSide: MaterialColor, pawnDelta: Int)
    /// Cualquier otra combinación.
    case other(balance: Int)

    public init(_ s: MaterialSignature) {
        let dp = s.difference(.pawn)
        let dn = s.difference(.knight)
        let db = s.difference(.bishop)
        let dr = s.difference(.rook)
        let dq = s.difference(.queen)
        let dm = dn + db
        func side(_ positive: Bool) -> MaterialColor { positive ? .white : .black }
        switch (dq, dr, dm) {
        case (0, 0, 0) where dn == 0:
            self = dp == 0 ? .none : .pawns(up: side(dp > 0), count: abs(dp))
        case (0, 0, 0):
            let bishopSide = side(db > 0)
            self = .bishopForKnight(bishopSide: bishopSide, pawnDelta: bishopSide == .white ? dp : -dp)
        case (0, 1, -1), (0, -1, 1):
            let up = side(dr > 0)
            self = .exchange(up: up, pawnDelta: up == .white ? dp : -dp)
        case (0, 0, 1), (0, 0, -1):
            let up = side(dm > 0)
            self = .minorPiece(up: up, pawnDelta: up == .white ? dp : -dp)
        case (1, -2, 0), (-1, 2, 0):
            let q = side(dq > 0)
            self = .queenForRooks(queenSide: q, pawnDelta: q == .white ? dp : -dp)
        case (1, -1, -1), (-1, 1, 1):
            let q = side(dq > 0)
            self = .queenForRookAndMinor(queenSide: q, pawnDelta: q == .white ? dp : -dp)
        default:
            self = .other(balance: s.balance)
        }
    }
}
