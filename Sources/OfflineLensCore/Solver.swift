import Foundation

public struct ReceiptItem: Equatable {
    public let name: String
    public let quantity: Decimal
    public let total: Decimal
}

public enum Solver {
    // Deliberately accepts only explicitly labelled columns; guessing receipt column
    // meanings can silently confuse unit price and total price.
    public static func receiptItems(_ text: String) -> [ReceiptItem]? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let labels = ["제품명": "품목", "상품명": "품목", "개수": "수량", "총합": "합계", "단가": "가격"]
        func normalized(_ line: String) -> String {
            labels.reduce(line.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "|", with: "")) {
                $0.replacingOccurrences(of: $1.key, with: $1.value)
            }
        }
        guard let header = lines.firstIndex(where: { ["품목수량합계", "품목가격수량합계"].contains(normalized($0)) }) else { return nil }
        let hasPrice = normalized(lines[header]) == "품목가격수량합계"
        var items: [ReceiptItem] = []
        let pattern = hasPrice ? #"^(.+?)\s+([\d,]+)\s+(\d+)\s*개?\s+([\d,]+)\s*원?$"# : #"^(.+?)\s+(\d+)\s*개?\s+([\d,]+)\s*원?$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        for raw in lines.dropFirst(header + 1) {
            if raw == "원본 OCR:" { break }
            let line = raw.replacingOccurrences(of: "|", with: " ").trimmingCharacters(in: .whitespaces)
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let nr = Range(match.range(at: 1), in: line),
                  let qr = Range(match.range(at: hasPrice ? 3 : 2), in: line),
                  let tr = Range(match.range(at: hasPrice ? 4 : 3), in: line),
                  let quantity = Decimal(string: String(line[qr])), quantity > 0,
                  let total = Decimal(string: line[tr].replacingOccurrences(of: ",", with: "")), total >= 0
            else { return nil }
            if hasPrice {
                guard let pr = Range(match.range(at: 2), in: line),
                      let price = Decimal(string: line[pr].replacingOccurrences(of: ",", with: "")),
                      price * quantity == total else { return nil }
            }
            let name = String(line[nr]).trimmingCharacters(in: .whitespaces)
            guard !["총합계", "합계", "할인", "거스름돈", "결제"].contains(where: { name.contains($0) }) else { return nil }
            items.append(.init(name: name, quantity: quantity, total: total))
        }
        return items.isEmpty ? nil : items
    }

    public static func answer(text: String, question: String) -> String? {
        let q = question.replacingOccurrences(of: " ", with: "")
        if q.contains("총"), (q.contains("몇개") || q.contains("개수") || q.contains("수량")),
           let items = receiptItems(text) {
            return "정답: \(format(items.reduce(0) { $0 + $1.quantity }))개\n근거: " + items.map { format($0.quantity) }.joined(separator: " + ")
        }
        if (q.lowercased().contains("kg") || q.contains("킬로그램")),
           let items = receiptItems(text) {
            let unitPattern = #"(\d+(?:\.\d+)?)\s*(kg|킬로그램)"#
            let regex = try! NSRegularExpression(pattern: unitPattern, options: .caseInsensitive)
            let matches = items.compactMap { item -> (ReceiptItem, Decimal)? in
                guard let match = regex.firstMatch(in: item.name, range: NSRange(item.name.startIndex..., in: item.name)),
                      let range = Range(match.range(at: 1), in: item.name),
                      let weight = Decimal(string: String(item.name[range])) else { return nil }
                let label = regex.stringByReplacingMatches(in: item.name, range: NSRange(item.name.startIndex..., in: item.name), withTemplate: "").replacingOccurrences(of: " ", with: "")
                guard !label.isEmpty, q.contains(label) else { return nil }
                return (item, weight)
            }
            if matches.count == 1, let (item, weight) = matches.first {
                if q.contains("하나") || q.contains("한개") || q.contains("1개") || q.contains("개당") {
                    return "정답: \(format(weight))kg\n근거: 품목명 ‘\(item.name)’에 표시된 한 개의 무게입니다."
                }
                if q.contains("총") || q.contains("전체") {
                    return "정답: \(format(weight * item.quantity))kg\n근거: 한 개 \(format(weight))kg × \(format(item.quantity))개"
                }
            }
        }
        if q.contains("가장많") && (q.contains("1개") || q.contains("한개") || q.contains("개당")),
           let items = receiptItems(text) {
            // Combine repeated rows only when the per-unit price agrees.
            let groups = Dictionary(grouping: items, by: \.name)
            var combined: [ReceiptItem] = []
            for (name, rows) in groups {
                guard let first = rows.first,
                      rows.allSatisfy({ $0.total / $0.quantity == first.total / first.quantity }) else { return nil }
                combined.append(.init(name: name, quantity: rows.reduce(0) { $0 + $1.quantity }, total: rows.reduce(0) { $0 + $1.total }))
            }
            guard let largest = combined.map(\.quantity).max() else { return nil }
            let winners = combined.filter { $0.quantity == largest }.sorted { $0.name < $1.name }
            let result = winners.map { "\($0.name): 1개 가격 \(format($0.total / $0.quantity))원\n근거: 수량 \(format($0.quantity))개, 합계 \(format($0.total))원 ÷ \(format($0.quantity))" }.joined(separator: "\n\n")
            return (winners.count > 1 ? "최다 구매 수량이 같은 품목이 있습니다.\n\n" : "") + result
        }
        // Only evaluate a complete arithmetic expression, never numbers extracted
        // opportunistically from prose or a receipt.
        if let value = Arithmetic.evaluate(question) { return "\(question) = \(format(value))" }
        return nil
    }

    public static func format(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}

public enum Arithmetic {
    public static func evaluate(_ expression: String) -> Decimal? {
        let chars = Array(expression.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-"))
        guard !chars.isEmpty, chars.count <= 200, chars.allSatisfy({ "0123456789.+-*/()".contains($0) }) else { return nil }
        var parser = Parser(chars: chars)
        guard let result = parser.sum(), parser.index == chars.count, !result.isNaN else { return nil }
        return result
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        mutating func take(_ c: Character) -> Bool {
            guard index < chars.count, chars[index] == c else { return false }
            index += 1
            return true
        }
        mutating func sum() -> Decimal? {
            guard var result = product() else { return nil }
            while index < chars.count {
                if take("+") { guard let r = product() else { return nil }; result += r }
                else if take("-") { guard let r = product() else { return nil }; result -= r }
                else { break }
            }
            return result
        }
        mutating func product() -> Decimal? {
            guard var result = atom() else { return nil }
            while index < chars.count {
                if take("*") { guard let r = atom() else { return nil }; result *= r }
                else if take("/") { guard let r = atom(), r != 0 else { return nil }; result /= r }
                else { break }
            }
            return result
        }
        mutating func atom() -> Decimal? {
            if take("-") { return atom().map { -$0 } }
            if take("+") { return atom() }
            if take("(") { guard let r = sum(), take(")") else { return nil }; return r }
            let start = index
            while index < chars.count, "0123456789.".contains(chars[index]) { index += 1 }
            let token = String(chars[start..<index])
            guard token.contains(where: { $0.isNumber }), token.filter({ $0 == "." }).count <= 1 else { return nil }
            return Decimal(string: token, locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}
