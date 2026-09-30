import Testing
import Foundation
@testable import OfflineLensCore

struct ReceiptLayoutTests {
    func token(_ text: String, _ x: Double, _ y: Double, _ width: Double = 0.06) -> OCRToken {
        OCRToken(text: text, x: x, y: y, width: width, height: 0.04)
    }

    func receipt() -> (lines: [OCRToken], tokens: [OCRToken]) {
        let lines = [token("한식 구이", 0.15, 0.53, 0.18), token("성인남녀 히", 0.15, 0.48, 0.18), token("무농약 부격", 0.15, 0.43, 0.18),
                     token("알루론산 300", 0.4, 0.46, 0.25), token("광고 3+1", 0.15, 0.36, 0.18)]
        let tokens = [token("제품명", 0.15, 0.64), token("가격", 0.56, 0.61), token("개수", 0.70, 0.65), token("총합", 0.81, 0.65),
                      token("400", 0.56, 0.51), token("300", 0.56, 0.46), token("800", 0.56, 0.41),
                      token("2", 0.71, 0.55, 0.02), token("1", 0.71, 0.50, 0.02), token("1", 0.71, 0.45, 0.02),
                      token("800", 0.81, 0.55), token("300", 0.81, 0.50), token("800", 0.81, 0.45), token("425", 0.56, 0.74)]
        return (lines, tokens)
    }

    @Test func tornColumnsAndAddressAreHandled() {
        let fixture = receipt()
        let restored = ReceiptLayout.reconstruct(lines: fixture.lines, tokens: fixture.tokens)
        #expect(restored?.table.contains("무농약 부격 | 800 | 1 | 800") == true)
        #expect(restored?.table.contains("알루론산") == false)
        #expect(Solver.answer(text: restored?.table ?? "", question: "영수증에서 구매한 물건은 총 몇 개 입니까?")?.contains("정답: 4개") == true)
    }

    @Test func mismatchedOrMissingNumbersAreNotGuessed() {
        let fixture = receipt()
        var tokens = fixture.tokens
        tokens.removeAll { $0.text == "2" }
        #expect(ReceiptLayout.reconstruct(lines: fixture.lines, tokens: tokens) == nil)
        tokens = fixture.tokens.map { $0.text == "400" ? token("401", $0.x, $0.y) : $0 }
        #expect(ReceiptLayout.reconstruct(lines: fixture.lines, tokens: tokens) == nil)
    }

    @Test func translationOfWholeReceiptPreservesResult() {
        let fixture = receipt()
        func moved(_ token: OCRToken) -> OCRToken {
            OCRToken(text: token.text, x: token.x - 0.08, y: token.y + 0.04, width: token.width, height: token.height)
        }
        #expect(ReceiptLayout.reconstruct(lines: fixture.lines.map(moved), tokens: fixture.tokens.map(moved))?.table ==
                ReceiptLayout.reconstruct(lines: fixture.lines, tokens: fixture.tokens)?.table)
    }

    @Test func weightPerItemDiffersFromTotalWeight() {
        let table = "품목 가격 수량 합계\n묵은지 3kg | 900 | 7 | 6300\n건강에좋은 블루베리즙 | 700 | 9 | 6300\n건식 빵가루 | 300 | 8 | 2400"
        #expect(Solver.answer(text: table, question: "구매한 묵은지 하나는 몇 kg 입니까?")?.contains("정답: 3kg") == true)
        #expect(Solver.answer(text: table, question: "구매한 묵은지의 총 무게는 몇 kg?")?.contains("정답: 21kg") == true)
        #expect(Solver.answer(text: table, question: "구매한 물건은 총 몇 개?")?.contains("정답: 24개") == true)
    }

    @Test func originalOCRIsNotParsedAsExtraReceiptRows() {
        let text = "제품명 가격 개수 총합\n사과 | 400 | 2 | 800\n배 | 300 | 1 | 300\n\n원본 OCR:\n주소 425\n가격\n400 300"
        #expect(Solver.answer(text: text, question: "총 구매 개수는?")?.contains("정답: 3개") == true)
        #expect(Solver.answer(text: "제품명 가격 개수 총합\n사과 | 400 | 2 | 900", question: "총 몇 개?") == nil)
    }
}
