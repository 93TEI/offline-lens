import Foundation

/// Vision coordinates: origin at the lower left, normalized to the image.
public struct OCRToken: Codable, Equatable {
    public let text: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let confidence: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double, confidence: Double = 1) {
        self.text = text; self.x = x; self.y = y; self.width = width; self.height = height; self.confidence = confidence
    }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

public struct ReconstructedReceipt {
    public let table: String
    public let evidence: String
}

public enum ReceiptLayout {
    /// Read each labelled column independently. Torn pieces need not share a
    /// baseline. Ordinal matching is accepted only when every price × quantity
    /// agrees with the corresponding total; no missing numbers are inferred.
    public static func reconstruct(lines: [OCRToken], tokens: [OCRToken]) -> ReconstructedReceipt? {
        let quantityHeaders = tokens.filter { ["개수", "수량"].contains($0.text) }
        let totalHeaders = tokens.filter { ["총합", "합계", "금액"].contains($0.text) }
        let priceHeaders = tokens.filter { ["가격", "단가"].contains($0.text) }
        guard quantityHeaders.count == 1, totalHeaders.count == 1, priceHeaders.count == 1,
              let qh = quantityHeaders.first, let th = totalHeaders.first, let ph = priceHeaders.first,
              ph.midX < qh.midX, qh.midX < th.midX else { return nil }
        let gap = min(qh.midX - ph.midX, th.midX - qh.midX)
        guard gap > 0.02 else { return nil }
        let numberPattern = #"^\d[\d,]*(?:\.\d+)?$"#
        let numeric = tokens.filter {
            $0.confidence >= 0.25 && $0.text.range(of: numberPattern, options: .regularExpression) != nil
        }
        func column(_ header: OCRToken) -> [OCRToken] {
            numeric.filter {
                abs($0.midX - header.midX) < gap * 0.48 &&
                $0.midY < header.y - header.height * 0.15
            }.sorted { $0.midY > $1.midY }
        }
        let prices = column(ph), quantities = column(qh), totals = column(th)
        guard !quantities.isEmpty, quantities.count <= 30,
              quantities.count == prices.count, quantities.count == totals.count else { return nil }
        let nameHeaders = tokens.filter { ["제품명", "품목", "상품명"].contains($0.text) && $0.midX < ph.midX }
        guard nameHeaders.count == 1, let nh = nameHeaders.first else { return nil }
        let names = lines.filter {
            $0.midY < nh.y && $0.x < nh.x + max(nh.width * 0.6, 0.03) &&
            $0.x + $0.width < (ph.midX + qh.midX) / 2 &&
            $0.text.range(of: #"[가-힣A-Za-z]"#, options: .regularExpression) != nil
        }.sorted { $0.midY > $1.midY }
        guard names.count >= quantities.count else { return nil }
        func decimal(_ token: OCRToken) -> Decimal? {
            Decimal(string: token.text.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
        }
        var rows = ["품목 가격 수량 합계"]
        var evidence: [String] = []
        for index in quantities.indices {
            guard let price = decimal(prices[index]), let quantity = decimal(quantities[index]),
                  let total = decimal(totals[index]), price >= 0, quantity > 0,
                  NSDecimalNumber(decimal: quantity).doubleValue.rounded() == NSDecimalNumber(decimal: quantity).doubleValue,
                  price * quantity == total else { return nil }
            // A corrupt column order must never be 'repaired' using arithmetic.
            let name = names[index].text
            rows.append("\(name) | \(Solver.format(price)) | \(Solver.format(quantity)) | \(Solver.format(total))")
            evidence.append("\(name): \(Solver.format(price)) × \(Solver.format(quantity)) = \(Solver.format(total))")
        }
        return ReconstructedReceipt(table: rows.joined(separator: "\n"), evidence: evidence.joined(separator: "\n"))
    }
}
