import Testing
import Foundation
@testable import OfflineLensCore

struct SolverTests {
    let question = "가장 많이 구매한 물건의 1개 가격은?"
    @Test func testReceipt() {
        let answer = Solver.answer(text: "품목 수량 합계\n우유 2 4,800\n빵 3 4,500", question: question)
        #expect(answer?.contains("빵: 1개 가격 1500원") == true)
    }
    @Test func testAmbiguousColumnsAndUnreadableRowsAreRejected() {
        #expect(Solver.answer(text: "우유 2400 2 4800", question: question) == nil)
        #expect(Solver.answer(text: "품목 수량 합계\n우유 2 4800\n빵 ? 4500", question: question) == nil)
        #expect(Solver.answer(text: "품목 수량 합계\n우유 0 4800", question: question) == nil)
    }
    @Test func testRepeatedRowsAndTies() {
        let answer = Solver.answer(text: "품목 수량 합계\n우유 2 4800\n우유 1 2400\n빵 3 4500", question: question)
        #expect(answer?.contains("같은 품목") == true)
        #expect(answer?.contains("우유: 1개 가격 2400원") == true)
    }
    @Test func testDifferentUnitPricesAreRejected() {
        #expect(Solver.answer(text: "품목 수량 합계\n우유 2 4800\n우유 1 2000", question: question) == nil)
    }
    @Test func testArithmetic() {
        #expect(Arithmetic.evaluate("(4500 ÷ 3) + 2 × 4") == 1508)
        #expect(Arithmetic.evaluate("0.1 + 0.2") == Decimal(string: "0.3"))
        #expect(Arithmetic.evaluate("-2 * (3 + 4)") == -14)
        for expression in ["1/0", "1.2.3", "1+", "(2+3", "물건 2개 3000원", ""] {
            #expect(Arithmetic.evaluate(expression) == nil)
        }
    }
}
