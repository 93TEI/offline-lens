import AppKit
import Vision
import ImageIO

enum LensError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum OCR {
    static func read(_ url: URL) throws -> String {
        // Decode a bounded thumbnail directly; do not retain the original full-size bitmap.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1800,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw LensError.message("이미지를 열 수 없습니다.") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["ko-KR", "en-US"].filter { supported.contains($0) }
        guard request.recognitionLanguages.contains("ko-KR") else {
            throw LensError.message("현재 macOS에서 한국어 OCR을 지원하지 않습니다. 텍스트를 직접 붙여 넣어 주세요.")
        }
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        // Group observations into visual rows before ordering left to right.
        let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in observations {
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.boundingBox.midY - observation.boundingBox.midY) < min(first.boundingBox.height, observation.boundingBox.height) * 0.5
            }) { rows[index].append(observation) }
            else { rows.append([observation]) }
        }
        let text = rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "  ")
        }.joined(separator: "\n")
        guard !text.isEmpty else { throw LensError.message("글자를 찾지 못했습니다. 글자가 크게 보이도록 영역을 다시 선택해 주세요.") }
        return text
    }
}
