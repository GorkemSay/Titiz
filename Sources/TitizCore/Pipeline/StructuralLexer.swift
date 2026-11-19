import Foundation

/// Lossless structural tokenizer that separates punctuation, whitespace, structural spans,
/// regular words, and apostrophe-inflected words (`'` / `’`).
public enum StructuralLexer {
    private static let knownFileExtensions: Set<String> = [
        "swift", "json", "md", "py", "sh", "txt", "h", "c", "cpp", "cxx", "hxx",
        "dic", "aff", "app", "dmg", "zip", "plist", "yaml", "yml", "toml", "xml",
        "html", "css", "js", "ts", "png", "svg", "pdf", "log", "csv"
    ]

    private static let trailingURLStopPunctuation: Set<Character> = [
        ".", ",", ";", ":", "!", "?", "\"", "'", "”", "’", "]", "}"
    ]

    private static let trailingGeneralStopPunctuation: Set<Character> = [
        ".", ",", ";", ":", "!", "?", "\"", "'", "”", "’", ")", "]", "}"
    ]

    private static let pathAllowedBeforeCharacters: Set<Character> = [
        "(", "[", "{", "\"", "'", "“", "‘", ":", "=", ","
    ]

    /// Tokenizes NFC-normalized text into lossless lexical tokens.
    public static func tokenize(_ normalized: NormalizedText) -> [Token] {
        let text = normalized.text
        guard !text.isEmpty else {
            return []
        }

        var tokens: [Token] = []
        var cursor = text.startIndex
        var utf16Cursor = 0

        func emit(_ end: String.Index, kind: TokenKind, protection: ProtectionInfo? = nil) {
            let slice = text[cursor..<end]
            let utf16Len = slice.utf16.count
            let token = Token(
                text: String(slice),
                range: cursor..<end,
                utf16Range: UTF16Range(location: utf16Cursor, length: utf16Len),
                kind: kind,
                protection: protection
            )
            tokens.append(token)
            cursor = end
            utf16Cursor += utf16Len
        }

        while cursor < text.endIndex {
            let current = text[cursor]

            // 1. Whitespace (newlines separated from horizontal whitespace runs)
            if current.isNewline {
                let end = text.index(after: cursor)
                emit(end, kind: .whitespace)
                continue
            }

            if current.isWhitespace {
                var end = text.index(after: cursor)
                while end < text.endIndex, text[end].isWhitespace, !text[end].isNewline {
                    end = text.index(after: end)
                }
                emit(end, kind: .whitespace)
                continue
            }

            // 2. Code spans (fenced ```...``` or same-line inline `...`)
            if current == "`", let end = matchCodeSpanEnd(in: text, from: cursor) {
                emit(
                    end,
                    kind: .protectedSpan(.inlineCode),
                    protection: ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "Inline or fenced code span",
                        structuralKind: .inlineCode
                    )
                )
                continue
            }

            // 3. URLs
            if isAtWordBoundaryBefore(cursor, in: text),
               let end = matchURLEnd(in: text, from: cursor) {
                emit(
                    end,
                    kind: .protectedSpan(.url),
                    protection: ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "URL",
                        structuralKind: .url
                    )
                )
                continue
            }

            // 4. Emails
            if isAtWordBoundaryBefore(cursor, in: text),
               let end = matchEmailEnd(in: text, from: cursor) {
                emit(
                    end,
                    kind: .protectedSpan(.email),
                    protection: ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "Email address",
                        structuralKind: .email
                    )
                )
                continue
            }

            // 5. File paths (must not consume ordinary Turkish slash pairs like "ve/veya")
            if isAtPathBoundaryBefore(cursor, in: text),
               let end = matchFilePathEnd(in: text, from: cursor) {
                emit(
                    end,
                    kind: .protectedSpan(.filePath),
                    protection: ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "File path",
                        structuralKind: .filePath
                    )
                )
                continue
            }

            // 6. @handles and #hashtags
            if current == "@",
               isAtWordBoundaryBefore(cursor, in: text),
               let end = matchHandleEnd(in: text, from: cursor) {
                emit(
                    end,
                    kind: .protectedSpan(.handle),
                    protection: ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "Mention handle",
                        structuralKind: .handle
                    )
                )
                continue
            }

            if current == "#",
               isAtWordBoundaryBefore(cursor, in: text),
               let end = matchHashtagEnd(in: text, from: cursor) {
                emit(
                    end,
                    kind: .protectedSpan(.hashtag),
                    protection: ProtectionInfo(
                        tier: .tier0Structural,
                        reason: "Hashtag",
                        structuralKind: .hashtag
                    )
                )
                continue
            }

            // 7. Numeric / Version / Time tokens (with optional apostrophe suffix)
            if let numericMatch = matchNumericOrVersion(in: text, from: cursor) {
                if let apostropheMatch = matchApostropheSuffix(in: text, from: numericMatch.stemEnd) {
                    let stem = String(text[cursor..<numericMatch.stemEnd])
                    emit(
                        apostropheMatch.end,
                        kind: .apostropheWord(
                            stem: stem,
                            apostrophe: apostropheMatch.apostrophe,
                            suffix: apostropheMatch.suffix
                        ),
                        protection: ProtectionInfo(
                            tier: .tier0Structural,
                            reason: "Numeric or version stem with suffix",
                            structuralKind: .numericOrVersion
                        )
                    )
                } else {
                    emit(
                        numericMatch.stemEnd,
                        kind: .protectedSpan(.numericOrVersion),
                        protection: ProtectionInfo(
                            tier: .tier0Structural,
                            reason: "Numeric or version token",
                            structuralKind: .numericOrVersion
                        )
                    )
                }
                continue
            }

            // 8. Words and apostrophe-inflected words
            if current.isLetter || current.isNumber {
                let stemEnd = scanWordStemEnd(in: text, from: cursor)
                if let apostropheMatch = matchApostropheSuffix(in: text, from: stemEnd) {
                    let stem = String(text[cursor..<stemEnd])
                    emit(
                        apostropheMatch.end,
                        kind: .apostropheWord(
                            stem: stem,
                            apostrophe: apostropheMatch.apostrophe,
                            suffix: apostropheMatch.suffix
                        )
                    )
                } else {
                    emit(stemEnd, kind: .word)
                }
                continue
            }

            // 9. Punctuation (never glued onto surrounding words)
            let end = text.index(after: cursor)
            emit(end, kind: .punctuation)
        }

        return tokens
    }

    private static func isAtWordBoundaryBefore(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return true
        }
        let prev = text[text.index(before: index)]
        return !(prev.isLetter || prev.isNumber)
    }

    private static func isAtPathBoundaryBefore(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else {
            return true
        }
        let prev = text[text.index(before: index)]
        return prev.isWhitespace || pathAllowedBeforeCharacters.contains(prev)
    }

    private static func matchCodeSpanEnd(in text: String, from start: String.Index) -> String.Index? {
        if text[start...].hasPrefix("```") {
            let searchStart = text.index(start, offsetBy: 3)
            if let closingRange = text[searchStart...].range(of: "```") {
                return closingRange.upperBound
            }
            return nil
        }

        var idx = text.index(after: start)
        while idx < text.endIndex {
            let ch = text[idx]
            if ch.isNewline {
                return nil
            }
            if ch == "`" {
                let afterOpen = text.index(after: start)
                guard idx > afterOpen else {
                    return nil
                }
                return text.index(after: idx)
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private static func matchURLEnd(in text: String, from start: String.Index) -> String.Index? {
        let lowerPrefix = String(text[start...].prefix(10)).lowercased()
        let explicitSchemes = ["https://", "http://", "ftp://", "file://", "mailto:"]
        var matchedPrefixLen: Int?

        for scheme in explicitSchemes where lowerPrefix.hasPrefix(scheme) {
            matchedPrefixLen = scheme.count
            break
        }

        let isWWW = matchedPrefixLen == nil && lowerPrefix.hasPrefix("www.")
        if isWWW {
            matchedPrefixLen = 4
        }

        guard let prefixLen = matchedPrefixLen else {
            return nil
        }

        var end = start
        while end < text.endIndex, !text[end].isWhitespace {
            end = text.index(after: end)
        }

        end = trimTrailingURLPunctuation(in: text, start: start, end: end)

        let charCount = text.distance(from: start, to: end)
        guard charCount > prefixLen else {
            return nil
        }

        if isWWW {
            let remainder = text[text.index(start, offsetBy: 4)..<end]
            guard let dotIndex = remainder.firstIndex(of: "."),
                  dotIndex > remainder.startIndex,
                  text.index(after: dotIndex) < end else {
                return nil
            }
        }

        return end
    }

    private static func trimTrailingURLPunctuation(
        in text: String,
        start: String.Index,
        end initialEnd: String.Index
    ) -> String.Index {
        var end = initialEnd
        while end > start {
            let prevIndex = text.index(before: end)
            let last = text[prevIndex]
            if trailingURLStopPunctuation.contains(last) {
                end = prevIndex
                continue
            }
            if last == ")" {
                let slice = text[start..<end]
                let openCount = slice.filter { $0 == "(" }.count
                let closeCount = slice.filter { $0 == ")" }.count
                if closeCount > openCount {
                    end = prevIndex
                    continue
                }
            }
            break
        }
        return end
    }

    private static func matchEmailEnd(in text: String, from start: String.Index) -> String.Index? {
        var idx = start
        var localCount = 0

        while idx < text.endIndex, isEmailLocalChar(text[idx]) {
            localCount += 1
            idx = text.index(after: idx)
        }

        guard localCount > 0, idx < text.endIndex, text[idx] == "@" else {
            return nil
        }

        idx = text.index(after: idx) // consume '@'
        let domainStart = idx

        while idx < text.endIndex, isEmailDomainChar(text[idx]) {
            idx = text.index(after: idx)
        }

        // Trim trailing dots/hyphens from domain (e.g. sentence-ending period)
        while idx > domainStart {
            let prev = text.index(before: idx)
            if text[prev] == "." || text[prev] == "-" {
                idx = prev
            } else {
                break
            }
        }

        let domain = text[domainStart..<idx]
        guard let lastDot = domain.lastIndex(of: "."),
              lastDot > domain.startIndex else {
            return nil
        }

        let tld = domain[domain.index(after: lastDot)...]
        guard tld.count >= 2, tld.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return nil
        }

        return idx
    }

    private static func matchFilePathEnd(in text: String, from start: String.Index) -> String.Index? {
        let remainder = text[start...]

        // Explicit Unix or relative prefix: ~/, ./, ../, /<pathChar>, or Windows drive path C:\...
        let hasExplicitUnixPrefix =
            remainder.hasPrefix("~/") ||
            remainder.hasPrefix("./") ||
            remainder.hasPrefix("../") ||
            (remainder.hasPrefix("/") &&
                remainder.dropFirst().first.map { isPathChar($0) && $0 != "/" } == true)

        let hasWindowsDrivePrefix =
            remainder.count >= 3 &&
            remainder.first?.isASCII == true &&
            remainder.first?.isLetter == true &&
            remainder.dropFirst().hasPrefix(":\\")

        if hasExplicitUnixPrefix || hasWindowsDrivePrefix {
            var end = start
            while end < text.endIndex, isPathChar(text[end]) || (hasWindowsDrivePrefix && text[end] == "\\") {
                end = text.index(after: end)
            }
            end = trimTrailingGeneralPunctuation(in: text, start: start, end: end)
            let candidate = text[start..<end]
            guard candidate.count >= 2, candidate.contains("/") || candidate.contains("\\") else {
                return nil
            }
            return end
        }

        // Relative ASCII path: Sources/TitizCore/TitizEngine.swift or dir/file.ext
        guard let first = remainder.first, isASCIIAlphaNumOrDotDash(first) else {
            return nil
        }

        var end = start
        while end < text.endIndex, isASCIIPathChar(text[end]) {
            end = text.index(after: end)
        }
        end = trimTrailingGeneralPunctuation(in: text, start: start, end: end)

        let candidate = text[start..<end]
        guard candidate.contains("/") else {
            return nil
        }

        // Must stop on a clean boundary (next char cannot be a non-ASCII letter like Turkish characters)
        if end < text.endIndex {
            let next = text[end]
            if next.isLetter || next.isNumber {
                return nil
            }
        }

        let rawSegments = candidate.split(separator: "/", omittingEmptySubsequences: false)
        guard rawSegments.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isASCIIPathSegmentChar) }) else {
            return nil
        }

        let slashCount = rawSegments.count - 1
        if slashCount >= 2 {
            return end
        }

        // Single-slash relative paths require a recognized file extension to avoid matching "and/or".
        if slashCount == 1,
           let lastSegment = rawSegments.last,
           let dotIdx = lastSegment.lastIndex(of: "."),
           dotIdx > lastSegment.startIndex {
            let ext = lastSegment[lastSegment.index(after: dotIdx)...].lowercased()
            if knownFileExtensions.contains(ext) {
                return end
            }
        }

        return nil
    }

    private static func matchHandleEnd(in text: String, from start: String.Index) -> String.Index? {
        let afterAt = text.index(after: start)
        guard afterAt < text.endIndex, isASCIILetterDigitOrUnderscore(text[afterAt]) else {
            return nil
        }

        var end = text.index(after: afterAt)
        while end < text.endIndex {
            let ch = text[end]
            if isASCIILetterDigitOrUnderscore(ch) || ch == "." || ch == "-" {
                end = text.index(after: end)
            } else {
                break
            }
        }

        while end > afterAt {
            let prev = text.index(before: end)
            if text[prev] == "." || text[prev] == "-" {
                end = prev
            } else {
                break
            }
        }

        return end > afterAt ? end : nil
    }

    private static func matchHashtagEnd(in text: String, from start: String.Index) -> String.Index? {
        let afterHash = text.index(after: start)
        guard afterHash < text.endIndex else {
            return nil
        }

        var end = afterHash
        var hasWordChar = false
        while end < text.endIndex {
            let ch = text[end]
            if ch.isLetter || ch.isNumber || ch == "_" {
                if ch.isLetter || ch.isNumber {
                    hasWordChar = true
                }
                end = text.index(after: end)
            } else {
                break
            }
        }

        return hasWordChar ? end : nil
    }

    private static func matchNumericOrVersion(
        in text: String,
        from start: String.Index
    ) -> (stemEnd: String.Index, Void)? {
        let first = text[start]

        // Version strings starting with v/V followed by digit + dot + digit (e.g. v1.7.6)
        if first == "v" || first == "V" {
            let afterV = text.index(after: start)
            guard afterV < text.endIndex, text[afterV].isASCII, text[afterV].isNumber else {
                return nil
            }
            var idx = afterV
            var hasDotSegment = false
            while idx < text.endIndex {
                let ch = text[idx]
                if ch.isASCII && ch.isNumber {
                    idx = text.index(after: idx)
                } else if ch == "." {
                    let next = text.index(after: idx)
                    if next < text.endIndex, text[next].isASCII, text[next].isNumber {
                        hasDotSegment = true
                        idx = text.index(after: idx)
                    } else {
                        break
                    }
                } else {
                    break
                }
            }

            if hasDotSegment {
                // If glued immediately to letters without apostrophe, let word scanner handle as mixed identifier.
                if idx < text.endIndex, text[idx].isLetter {
                    return nil
                }
                return (idx, ())
            }
            return nil
        }

        guard first.isNumber else {
            return nil
        }

        var idx = text.index(after: start)
        while idx < text.endIndex {
            let ch = text[idx]
            if ch.isNumber {
                idx = text.index(after: idx)
            } else if ch == "." || ch == "," || ch == ":" {
                let next = text.index(after: idx)
                if next < text.endIndex, text[next].isNumber {
                    idx = text.index(after: idx)
                } else {
                    break
                }
            } else {
                break
            }
        }

        // If followed directly by letters (e.g., 3D, 64bit), defer to word scanner so Tier 0 classifies as mixed ID.
        if idx < text.endIndex, text[idx].isLetter {
            return nil
        }

        return (idx, ())
    }

    private static func scanWordStemEnd(in text: String, from start: String.Index) -> String.Index {
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if ch.isLetter || ch.isNumber {
                idx = text.index(after: idx)
                continue
            }

            if ch == "_" {
                let next = text.index(after: idx)
                if next < text.endIndex, text[next].isLetter || text[next].isNumber {
                    idx = text.index(after: idx)
                    continue
                }
            }

            // Hyphen stays inside token only when adjacent to a digit (e.g. GPT-4, UTF-8, macOS-15).
            if ch == "-", idx > start {
                let prev = text[text.index(before: idx)]
                let next = text.index(after: idx)
                if next < text.endIndex,
                   (text[next].isLetter || text[next].isNumber),
                   (prev.isNumber || text[next].isNumber) {
                    idx = text.index(after: idx)
                    continue
                }
            }

            break
        }
        return idx
    }

    private static func matchApostropheSuffix(
        in text: String,
        from stemEnd: String.Index
    ) -> (apostrophe: Character, suffix: String, end: String.Index)? {
        guard stemEnd < text.endIndex else {
            return nil
        }

        let apostrophe = text[stemEnd]
        guard apostrophe == "'" || apostrophe == "’" else {
            return nil
        }

        let suffixStart = text.index(after: stemEnd)
        guard suffixStart < text.endIndex else {
            return nil
        }

        let firstSuffix = text[suffixStart]
        guard firstSuffix.isLetter || firstSuffix.isNumber else {
            return nil
        }

        var end = text.index(after: suffixStart)
        while end < text.endIndex, text[end].isLetter || text[end].isNumber {
            end = text.index(after: end)
        }

        return (apostrophe, String(text[suffixStart..<end]), end)
    }

    private static func trimTrailingGeneralPunctuation(
        in text: String,
        start: String.Index,
        end initialEnd: String.Index
    ) -> String.Index {
        var end = initialEnd
        while end > start {
            let prev = text.index(before: end)
            if trailingGeneralStopPunctuation.contains(text[prev]) {
                end = prev
            } else {
                break
            }
        }
        return end
    }

    private static func isEmailLocalChar(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || "._%+-".contains(ch))
    }

    private static func isEmailDomainChar(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || ".-".contains(ch))
    }

    private static func isPathChar(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || "._/@~+-:".contains(ch))
    }

    private static func isASCIIPathChar(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || "._/-".contains(ch))
    }

    private static func isASCIIPathSegmentChar(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || "._-".contains(ch))
    }

    private static func isASCIIAlphaNumOrDotDash(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || ch == "." || ch == "_")
    }

    private static func isASCIILetterDigitOrUnderscore(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || ch == "_")
    }
}
