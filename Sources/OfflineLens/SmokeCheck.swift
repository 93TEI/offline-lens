import AppKit
import OfflineLensCore

enum SmokeCheck {
    static func run() throws {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw LensError.message("테스트 이미지 생성 실패") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1000, height: 400)).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
        for (index, row) in [["품목", "수량", "합계"], ["우유", "2", "4,800"], ["빵", "3", "4,500"]].enumerated() {
            for (column, value) in row.enumerated() {
                (value as NSString).draw(at: NSPoint(x: 60 + column * 280, y: 280 - index * 90), withAttributes: attributes)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("offlinelens-check-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw LensError.message("PNG 변환 실패") }
        try data.write(to: file)
        let text = try OCR.read(file)
        print("OCR:\n\(text)")
        guard let answer = Solver.answer(text: text, question: "가장 많이 구매한 물건의 1개 가격은?"), answer.contains("1500원") else {
            throw LensError.message("OCR → 영수증 계산 확인 실패")
        }
        print("PASS: \(answer)")
    }
}
