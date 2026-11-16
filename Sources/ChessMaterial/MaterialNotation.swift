// MaterialNotation.swift
// ChessMaterial
//
// Lectura y escritura de material en texto: Scoutfish («KRBKRN») y ChessBase («TA-TC»).

/// Idioma de las letras de ChessBase.
public enum ChessBaseLanguage: Sendable, Hashable {
    /// D T A C P, rey R: «TA-TC».
    case spanish
    /// Q R B N P, rey K: «RB-RN».
    case english

    @inlinable
    public func letter(_ piece: MaterialPiece) -> Character {
        switch (self, piece) {
        case (.spanish, .queen): "D"
        case (.spanish, .rook): "T"
        case (.spanish, .bishop): "A"
        case (.spanish, .knight): "C"
        case (.english, .queen): "Q"
        case (.english, .rook): "R"
        case (.english, .bishop): "B"
        case (.english, .knight): "N"
        case (_, .pawn): "P"
        }
    }

    @inlinable
    public var king: Character { self == .spanish ? "R" : "K" }

    func piece(for letter: Character) -> MaterialPiece? {
        MaterialPiece.allCases.first { self.letter($0) == letter }
    }
}

/// Notaciones de texto para el material.
public enum MaterialNotation: Sendable, Hashable {
    /// Scoutfish: rey blanco, piezas blancas, rey negro, piezas negras, en inglés y
    /// con los peones como `P`: «KRBKRN», «KRPKR».
    case scoutfish
    /// ChessBase: piezas blancas, guion, piezas negras: «TA-TC». Un bando sin piezas
    /// se escribe con la letra del rey («T-R», «R-R»). Los peones (`P`) son opcionales.
    case chessBase(ChessBaseLanguage)

    public static let chessBaseSpanish = MaterialNotation.chessBase(.spanish)
    public static let chessBaseEnglish = MaterialNotation.chessBase(.english)
}

/// Resultado de leer un texto de material.
public struct ParsedMaterial: Hashable, Sendable {
    /// Recuentos leídos (peones a 0 si el texto no los nombra).
    public var signature: MaterialSignature
    /// `true` si el texto nombra algún peón; si no, los peones quedan sin especificar.
    public var includesPawns: Bool
}

extension MaterialSignature {
    /// Lee un texto de material. Devuelve `nil` si no es válido.
    ///
    /// - Scoutfish: exactamente dos `K`; la primera abre el bando blanco.
    /// - ChessBase: dos bandos separados por `-` (también `–`, `—` o `/`); se ignoran
    ///   espacios, `+` y la letra del rey.
    public static func parse(_ text: String, notation: MaterialNotation) -> ParsedMaterial? {
        switch notation {
        case .scoutfish: parseScoutfish(text)
        case let .chessBase(language): parseChessBase(text, language: language)
        }
    }

    /// Lee un texto de material (los peones que no se nombran quedan a 0).
    public init?(_ text: String, notation: MaterialNotation) {
        guard let parsed = Self.parse(text, notation: notation) else { return nil }
        self = parsed.signature
    }

    /// Escribe la firma en la notación pedida.
    ///
    /// - Parameter includePawns: en ChessBase, añade una `P` por peón (Scoutfish siempre los escribe).
    public func formatted(_ notation: MaterialNotation, includePawns: Bool = false) -> String {
        switch notation {
        case .scoutfish:
            let order: [MaterialPiece] = [.queen, .rook, .bishop, .knight, .pawn]
            func side(_ color: MaterialColor) -> String {
                "K" + order.map { String(repeating: ChessBaseLanguage.english.letter($0), count: self[$0, color]) }.joined()
            }
            return side(.white) + side(.black)
        case let .chessBase(language):
            var order = MaterialPiece.pieces
            if includePawns { order.append(.pawn) }
            func side(_ color: MaterialColor) -> String {
                let text = order.map { String(repeating: language.letter($0), count: self[$0, color]) }.joined()
                return text.isEmpty ? String(language.king) : text
            }
            return side(.white) + "-" + side(.black)
        }
    }

    private static func parseScoutfish(_ text: String) -> ParsedMaterial? {
        let letters = text.uppercased().filter { !$0.isWhitespace }
        let sides = letters.split(separator: "K", omittingEmptySubsequences: false)
        // "KRBKRN" → ["", "RB", "RN"]
        guard sides.count == 3, sides[0].isEmpty else { return nil }
        var signature = MaterialSignature(rawValue: 0)
        var pawns = false
        for (side, color) in [(sides[1], MaterialColor.white), (sides[2], .black)] {
            for letter in side {
                guard let piece = ChessBaseLanguage.english.piece(for: letter) else { return nil }
                if piece == .pawn { pawns = true }
                signature[piece, color] += 1
            }
        }
        signature.bishopColors = Self.defaultBishopColors(signature)
        return ParsedMaterial(signature: signature, includesPawns: pawns)
    }

    private static func parseChessBase(_ text: String, language: ChessBaseLanguage) -> ParsedMaterial? {
        let normalized = text.uppercased().map { "–—/".contains($0) ? "-" : $0 }
        let sides = String(normalized).split(separator: "-", omittingEmptySubsequences: false)
        guard sides.count == 2 else { return nil }
        var signature = MaterialSignature(rawValue: 0)
        var pawns = false
        for (side, color) in [(sides[0], MaterialColor.white), (sides[1], .black)] {
            var sawSomething = false
            for letter in side where !letter.isWhitespace && letter != "+" {
                sawSomething = true
                if letter == language.king { continue }
                guard let piece = language.piece(for: letter) else { return nil }
                if piece == .pawn { pawns = true }
                signature[piece, color] += 1
            }
            guard sawSomething else { return nil }
        }
        signature.bishopColors = Self.defaultBishopColors(signature)
        return ParsedMaterial(signature: signature, includesPawns: pawns)
    }

    /// Con dos o más alfiles, uno de cada color; con uno, desconocido (vacío).
    static func defaultBishopColors(_ s: MaterialSignature) -> BishopSquareColors {
        var colors: BishopSquareColors = []
        if s[.bishop, .white] >= 2 { colors.formUnion([.whiteLight, .whiteDark]) }
        if s[.bishop, .black] >= 2 { colors.formUnion([.blackLight, .blackDark]) }
        return colors
    }
}

extension MaterialSignature: CustomStringConvertible {
    /// «TAPPP-TCPP» (ChessBase en español con peones).
    public var description: String { formatted(.chessBaseSpanish, includePawns: true) }
}
