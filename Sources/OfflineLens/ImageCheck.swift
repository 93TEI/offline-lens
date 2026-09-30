import Foundation
import OfflineLensCore

enum ImageCheck {
    static func run() throws {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--check-image"), args.indices.contains(flag + 1) else {
            throw LensError.message("사용법: OfflineLens --check-image 이미지 [--model-only] [--raw-ocr] [--question 질문]")
        }
        let started = Date()
        let document = try OCR.readDocument(URL(fileURLWithPath: args[flag + 1]))
        print("원본 OCR:\n\(document.rawText)\n")
        if let receipt = document.receipt { print("복원한 표:\n\(receipt.table)\n검산:\n\(receipt.evidence)\n") }
        else { print("표 복원: 확인 가능한 표를 찾지 못했습니다.\n") }
        let explicit = args.firstIndex(of: "--question").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        guard let question = explicit ?? document.question else { throw LensError.message("질문을 찾지 못했습니다. --question으로 질문을 지정해 주세요.") }
        print("질문: \(question)")
        let text = args.contains("--raw-ocr") ? document.rawText : document.text
        if !args.contains("--model-only"), let answer = Solver.answer(text: text, question: question) {
            print("풀이 방식: 규칙 계산\n\(answer)")
        } else {
            guard let files = LocalModel.installedFiles() else { throw LensError.message("설치된 로컬 AI가 없습니다. scripts/install-local-ai.py를 실행해 주세요.") }
            let model = LocalModel()
            model.prepare()
            print("모델: \(URL(fileURLWithPath: files.model).lastPathComponent)")
            print(try model.answer(text: text, question: question, executable: files.executable, model: files.model))
        }
        print(String(format: "총 소요: %.2f초", Date().timeIntervalSince(started)))
    }
}
