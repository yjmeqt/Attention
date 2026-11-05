// Adapted from apple/ml-mobileclip (ios_app), itself based on
// huggingface/swift-coreml-transformers. See Search/ACKNOWLEDGEMENTS.
// Copyright (C) 2024 Apple Inc. All Rights Reserved.

import Foundation

struct BytePair: Hashable {
    let a: String
    let b: String
    init(_ a: String, _ b: String) { self.a = a; self.b = b }
    init(tuple: [String]) { self.a = tuple[0]; self.b = tuple[1] }
}

/// CLIP's BPE tokenizer. Loads `clip-vocab.json` and `clip-merges.txt` from a directory.
final class CLIPTokenizer: @unchecked Sendable {
    let bpeRanks: [BytePair: Int]
    private let encoder: [String: Int]
    private let decoder: [Int: String]
    let contextLength = 77

    init(directory: URL) throws {
        let merges = try String(contentsOf: directory.appending(path: "clip-merges.txt"), encoding: .utf8)
        let lines = merges.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var ranks: [BytePair: Int] = [:]
        for i in 1..<lines.count {
            let tuple = lines[i].split(separator: " ").map(String.init)
            guard tuple.count == 2 else { continue }
            ranks[BytePair(tuple: tuple)] = i - 1
        }
        bpeRanks = ranks
        let vocabData = try Data(contentsOf: directory.appending(path: "clip-vocab.json"))
        encoder = try JSONDecoder().decode([String: Int].self, from: vocabData)
        var inverted: [Int: String] = [:]
        for (k, v) in encoder { inverted[v] = k }
        decoder = inverted
    }

    func encodeFull(_ text: String) -> [Int] {
        let tokens = encode(text)
        var full = Array(repeating: 0, count: contextLength)
        full[0] = encoder["<|startoftext|>"]!
        let limit = min(tokens.count, contextLength - 2)
        for i in 0..<limit { full[i + 1] = tokens[i] }
        full[limit + 1] = encoder["<|endoftext|>"]!
        return full
    }

    func encode(_ text: String) -> [Int] {
        tokenize(text).compactMap { encoder[$0] }
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        for token in byteEncode(text.lowercased()) {
            tokens.append(contentsOf: bpe(token: token).split(separator: " ").map(String.init))
        }
        return tokens
    }

    private func byteEncode(_ text: String) -> [String] {
        let pattern = "<\\|startoftext\\|>|<\\|endoftext\\|>|'s|'t|'re|'ve|'m|'ll|'d|[\\p{L}]+|[\\p{N}]|[^\\s\\p{L}\\p{N}]+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.map { String(text[Range($0.range, in: text)!]) }
            .map { Array($0.utf8).map { byteEncoder[$0]! }.joined() }
    }

    private func getPairs(_ word: [String]) -> Set<BytePair> {
        var s = Set<BytePair>()
        for i in 0..<word.count - 1 { s.insert(BytePair(word[i], word[i + 1])) }
        return s
    }

    private func bpe(token: String) -> String {
        if token.count <= 1 { return token + "</w>" }
        var word = Array(token).map(String.init)
        let last = (word.last ?? "") + "</w>"
        word.removeLast()
        word.append(last)
        var pairs = Array(getPairs(word))
        if pairs.isEmpty { return token + "</w>" }
        while true {
            let bigrams = pairs.filter { bpeRanks[$0] != nil }
            guard let bigram = bigrams.min(by: { bpeRanks[$0]! < bpeRanks[$1]! }) else { break }
            let first = bigram.a, second = bigram.b
            var newWord: [String] = []
            var i = 0
            while i < word.count {
                if let j = word[i..<word.count].firstIndex(of: first) {
                    newWord.append(contentsOf: word[i..<j])
                    i = j
                } else {
                    newWord.append(contentsOf: word[i..<word.count])
                    break
                }
                if word[i] == first, i < word.count - 1, word[i + 1] == second {
                    newWord.append(first + second)
                    i += 2
                } else {
                    newWord.append(word[i])
                    i += 1
                }
            }
            word = newWord
            if word.count == 1 { break }
            pairs = Array(getPairs(word))
        }
        return word.joined(separator: " ")
    }
}
