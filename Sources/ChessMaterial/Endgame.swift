// Endgame.swift
// ChessMaterial
//
// Clasificación de finales al estilo «Endgame classification» de ChessBase.

/// Familia de un final.
public enum EndingFamily: Int, CaseIterable, Sendable, Codable, Comparable {
    /// Sin piezas: solo reyes y peones.
    case pawns = 0
    /// Solo torres.
    case rooks = 1
    /// Solo alfiles y caballos.
    case minors = 2
    /// Solo damas.
    case queens = 3
    /// Combinaciones (T+menor, D+T, D contra menor…).
    case mixed = 4

    public var name: String {
        switch self {
        case .pawns: "Peones"
        case .rooks: "Torres"
        case .minors: "Menores"
        case .queens: "Damas"
        case .mixed: "Mixto"
        }
    }

    public static func < (l: EndingFamily, r: EndingFamily) -> Bool { l.rawValue < r.rawValue }
}

/// Piezas de un bando en un final: como mucho dos de D, T, A, C, sin contar peones.
///
/// Código de 4 bits: 0 ninguna, 1 D, 2 T, 3 A, 4 C, 5 DD, 6 DT, 7 DA, 8 DC, 9 TT,
/// 10 TA, 11 TC, 12 AA, 13 AC, 14 CC (15 no se usa).
public struct EndingSide: Hashable, Sendable, Comparable {
    public let code: UInt8

    static let table: [(q: Int, r: Int, b: Int, n: Int)] = [
        (0, 0, 0, 0),
        (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1),
        (2, 0, 0, 0), (1, 1, 0, 0), (1, 0, 1, 0), (1, 0, 0, 1),
        (0, 2, 0, 0), (0, 1, 1, 0), (0, 1, 0, 1),
        (0, 0, 2, 0), (0, 0, 1, 1), (0, 0, 0, 2),
    ]

    public init?(code: UInt8) {
        guard code < 15 else { return nil }
        self.code = code
    }

    /// `nil` si el bando tiene más de dos piezas.
    @inlinable
    public init?(_ s: MaterialSignature, _ color: MaterialColor) {
        let q = s[.queen, color], r = s[.rook, color], b = s[.bishop, color], n = s[.knight, color]
        guard q + r + b + n <= 2 else { return nil }
        guard let index = Self.index(q: q, r: r, b: b, n: n) else { return nil }
        self.code = index
    }

    @usableFromInline
    static func index(q: Int, r: Int, b: Int, n: Int) -> UInt8? {
        // Índice directo sin buscar en la tabla.
        switch (q, r, b, n) {
        case (0, 0, 0, 0): 0
        case (1, 0, 0, 0): 1
        case (0, 1, 0, 0): 2
        case (0, 0, 1, 0): 3
        case (0, 0, 0, 1): 4
        case (2, 0, 0, 0): 5
        case (1, 1, 0, 0): 6
        case (1, 0, 1, 0): 7
        case (1, 0, 0, 1): 8
        case (0, 2, 0, 0): 9
        case (0, 1, 1, 0): 10
        case (0, 1, 0, 1): 11
        case (0, 0, 2, 0): 12
        case (0, 0, 1, 1): 13
        case (0, 0, 0, 2): 14
        default: nil
        }
    }

    public var counts: PieceCounts {
        let t = Self.table[Int(code)]
        return PieceCounts(knights: t.n, bishops: t.b, rooks: t.r, queens: t.q)
    }

    public func name(_ language: ChessBaseLanguage = .spanish) -> String {
        let c = counts
        let text = MaterialPiece.pieces.map { String(repeating: language.letter($0), count: c[$0]) }.joined()
        return text.isEmpty ? String(language.king) : text
    }

    public static func < (l: EndingSide, r: EndingSide) -> Bool { l.code < r.code }
}

/// Un final: una racha de posiciones consecutivas con las mismas piezas (sin contar peones).
public struct Ending: Hashable, Sendable {
    public var white: EndingSide
    public var black: EndingSide
    /// Un alfil por bando, de distinto color.
    public var oppositeBishops: Bool
    /// Ply de la primera posición de la racha (0 = posición inicial).
    public var startPly: Int
    /// Posiciones consecutivas que dura.
    public var plies: Int
    /// Material (con peones) al empezar la racha.
    public var signature: MaterialSignature

    public init(white: EndingSide, black: EndingSide, oppositeBishops: Bool, startPly: Int, plies: Int, signature: MaterialSignature) {
        self.white = white
        self.black = black
        self.oppositeBishops = oppositeBishops
        self.startPly = startPly
        self.plies = plies
        self.signature = signature
    }

    /// «TA-TC», «R-R», «T-T».
    public func name(_ language: ChessBaseLanguage = .spanish) -> String {
        white.name(language) + "-" + black.name(language)
    }

    /// El nombre sin importar quién tiene qué: el bando «más fuerte» primero.
    public func colorlessName(_ language: ChessBaseLanguage = .spanish) -> String {
        // Más piezas primero; a igualdad, la pieza más fuerte (D antes que T…).
        let sides = [white, black].sorted { ($0.counts.pieces, -Int($0.code)) > ($1.counts.pieces, -Int($1.code)) }
        let first = sides[0], second = sides[1]
        return first.name(language) + "-" + second.name(language)
    }

    public var family: EndingFamily {
        let w = white.counts, b = black.counts
        let q = w.queens + b.queens, r = w.rooks + b.rooks, m = w.minors + b.minors
        switch (q > 0, r > 0, m > 0) {
        case (false, false, false): return .pawns
        case (false, true, false): return .rooks
        case (false, false, true): return .minors
        case (true, false, false): return .queens
        default: return .mixed
        }
    }

    /// Código de 2 B para `longestEnding`: byte alto = `blancas << 4 | negras`
    /// (``EndingSide``), byte bajo = bit 7 alfiles de distinto color + plies saturados en 127.
    public var code: EndingCode {
        let high = UInt16(white.code) << 4 | UInt16(black.code)
        let low = (oppositeBishops ? 0x80 : 0) | UInt16(min(plies, 127))
        return EndingCode(rawValue: high << 8 | low)
    }
}

/// `longestEnding` empaquetado en 2 B. `0xFFFF` = la partida no llega a un final.
/// Ordenar por el valor agrupa por piezas y, dentro, por duración.
public struct EndingCode: RawRepresentable, Hashable, Sendable, Codable, Comparable {
    public var rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let none = EndingCode(rawValue: 0xFFFF)

    public var white: EndingSide? { EndingSide(code: UInt8(rawValue >> 12)) }
    public var black: EndingSide? { EndingSide(code: UInt8((rawValue >> 8) & 0xF)) }
    public var oppositeBishops: Bool { rawValue & 0x80 != 0 }
    /// Plies, saturado en 127.
    public var plies: Int { Int(rawValue & 0x7F) }
    /// Clave de piezas (byte alto) para filtrar por final sin mirar la duración.
    public var pieceKey: UInt8 { UInt8(rawValue >> 8) }

    public static func < (l: EndingCode, r: EndingCode) -> Bool { l.rawValue < r.rawValue }
}

/// Criterio de final y búsqueda del final más largo.
public enum Endgame {
    /// Una posición es **final** si cada bando tiene como mucho 2 piezas (sin contar
    /// rey ni peones) y, si hay alguna dama, como mucho 3 piezas entre los dos.
    ///
    /// Sin damas es el criterio clásico de «≤ 2 piezas por bando». Con damas admite D-D, D-T, DT-D, D-TT, DA-D…
    /// pero no DT-DT, que se juega como un medio juego.
    @inlinable
    public static func isEnding(_ s: MaterialSignature) -> Bool {
        let w = s.pieceCount(.white), b = s.pieceCount(.black)
        guard w <= 2, b <= 2 else { return false }
        let queens = s[.queen, .white] + s[.queen, .black]
        return queens == 0 || w + b <= 3
    }

    /// Clave de piezas del final (byte alto de ``EndingCode``) o `nil` si no es final.
    @inlinable
    public static func pieceKey(_ s: MaterialSignature) -> UInt8? {
        guard isEnding(s), let w = EndingSide(s, .white), let b = EndingSide(s, .black) else { return nil }
        return w.code << 4 | b.code
    }

    /// Todas las rachas de final de la partida, en orden.
    public static func endings<S: Sequence>(in signatures: S) -> [Ending] where S.Element == MaterialSignature {
        var tracker = EndgameTracker()
        var result: [Ending] = []
        for s in signatures {
            if let closed = tracker.append(s) { result.append(closed) }
        }
        if let last = tracker.finishCurrent() { result.append(last) }
        return result
    }

    /// El final más largo (en plies) con al menos `minimumPlies`. Si hay empate gana
    /// el **último**, el más cercano al resultado.
    public static func longestEnding<S: Sequence>(in signatures: S, minimumPlies: Int = 1) -> Ending? where S.Element == MaterialSignature {
        var tracker = EndgameTracker(minimumPlies: minimumPlies)
        for s in signatures { tracker.append(s) }
        return tracker.longestSoFar
    }
}

/// Recorre las posiciones de una partida una a una y guarda el final más largo.
/// Pensado para la pasada de indexación: no guarda la secuencia.
public struct EndgameTracker: Sendable {
    public let minimumPlies: Int
    public private(set) var ply = 0
    public private(set) var longest: Ending?
    private var current: Ending?
    private var currentKey: UInt16?

    public init(minimumPlies: Int = 1) { self.minimumPlies = max(1, minimumPlies) }

    /// Añade la posición siguiente. Devuelve la racha que se cierra, si se cierra alguna.
    @discardableResult
    public mutating func append(_ s: MaterialSignature) -> Ending? {
        defer { ply += 1 }
        let key: UInt16? = Endgame.pieceKey(s).map { UInt16($0) << 1 | (s.hasOppositeColoredBishops ? 1 : 0) }
        if key != nil, key == currentKey {
            current?.plies += 1
            return nil
        }
        let closed = finishCurrent()
        if let key, let w = EndingSide(s, .white), let b = EndingSide(s, .black) {
            currentKey = key
            current = Ending(white: w, black: b, oppositeBishops: s.hasOppositeColoredBishops, startPly: ply, plies: 1, signature: s)
        }
        return closed
    }

    /// Cierra la racha abierta (al final de la partida) y la devuelve.
    @discardableResult
    public mutating func finishCurrent() -> Ending? {
        guard let open = current else { return nil }
        current = nil
        currentKey = nil
        if open.plies >= minimumPlies, open.plies >= (longest?.plies ?? 0) { longest = open }
        return open
    }

    /// El final más largo, contando la racha abierta.
    public var longestSoFar: Ending? {
        guard let open = current, open.plies >= minimumPlies, open.plies >= (longest?.plies ?? 0) else { return longest }
        return open
    }
}

/// Resumen de material de una partida en una sola pasada: `materialVisited` y `longestEnding`.
public struct GameMaterialSummary: Sendable {
    public private(set) var visited: UInt64 = 0
    public private(set) var last: MaterialSignature?
    private var endings: EndgameTracker

    public init(minimumEndingPlies: Int = 1) {
        endings = EndgameTracker(minimumPlies: minimumEndingPlies)
    }

    public mutating func append(_ s: MaterialSignature) {
        // El material solo cambia con capturas y coronaciones: evita reclasificar.
        if s != last { visited |= MaterialClass.classes(of: s) }
        endings.append(s)
        last = s
    }

    public var longestEnding: Ending? { endings.longestSoFar }
    public var longestEndingCode: EndingCode { longestEnding?.code ?? .none }
}
