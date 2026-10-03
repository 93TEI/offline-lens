import Foundation
import Darwin
import OfflineLensCore

final class LocalModel {
    private let lock = NSLock()
    private var running: Process?
    private var cancelled = false

    static func modelURLs(_ path: String) throws -> [URL] {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let regex = try NSRegularExpression(pattern: #"^(.*)-(\d{5})-of-(\d{5})\.gguf$"#)
        guard let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { return [url] }
        guard let prefixRange = Range(match.range(at: 1), in: name),
              let indexRange = Range(match.range(at: 2), in: name),
              let countRange = Range(match.range(at: 3), in: name),
              name[indexRange] == "00001", let count = Int(name[countRange]), (1...100).contains(count) else {
            throw LensError.message("분할 모델의 첫 번째 GGUF 파일을 선택해 주세요.")
        }
        return (1...count).map {
            url.deletingLastPathComponent().appendingPathComponent(String(format: "%@-%05d-of-%05d.gguf", String(name[prefixRange]), $0, count))
        }
    }

    static func installedFiles() -> (executable: String, model: String)? {
        let defaults = UserDefaults.standard
        let configured = (defaults.string(forKey: "llamaExecutable") ?? "", defaults.string(forKey: "ggufModel") ?? "")
        if FileManager.default.isExecutableFile(atPath: configured.0), FileManager.default.fileExists(atPath: configured.1) { return configured }
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources.appendingPathComponent("local-ai")) }
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local-ai"))
        for root in roots {
            let executable = root.appendingPathComponent("runtime/llama-completion").path
            guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = manifest["model"] as? String, URL(fileURLWithPath: name).lastPathComponent == name else { continue }
            let model = root.appendingPathComponent("models").appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: executable), FileManager.default.fileExists(atPath: model) { return (executable, model) }
        }
        return nil
    }

    func prepare() {
        lock.lock(); cancelled = false; lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        // This runner owns the child. Kill promptly rather than leave model memory
        // resident if a CLI handles SIGTERM as an interactive interrupt.
        if let child = running, child.isRunning { kill(child.processIdentifier, SIGKILL) }
        lock.unlock()
    }

    func answer(text: String, question: String, executable: String, model: String) throws -> String {
        guard text.count <= 1600, question.count <= 200 else {
            throw LensError.message("가벼운 실행을 위해 지문은 1,600자, 질문은 200자 이내로 줄여 주세요.")
        }
        guard FileManager.default.isExecutableFile(atPath: executable), FileManager.default.fileExists(atPath: model) else {
            throw LensError.message("AI 파일 설정에서 llama-cli 실행 파일과 GGUF 모델을 선택해 주세요.")
        }
        var totalBytes: Int64 = 0
        for file in try Self.modelURLs(model) {
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw LensError.message("분할 모델 파일이 없습니다: \(file.lastPathComponent). 모든 파일을 같은 폴더에 두세요.")
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            totalBytes += (attributes[.size] as? NSNumber)?.int64Value ?? 6_000_000_001
            guard totalBytes <= 6_000_000_000 else {
                throw LensError.message("모델의 전체 파일 크기는 6GB 이하여야 합니다.")
            }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else { throw LensError.message("올바른 GGUF 모델 파일이 아닙니다: \(file.lastPathComponent)") }
        }
        guard ProcessInfo.processInfo.thermalState != .serious, ProcessInfo.processInfo.thermalState != .critical else {
            throw LensError.message("Mac의 온도가 높아 AI 실행을 쉬고 있습니다. 잠시 후 다시 시도해 주세요.")
        }
        // The verified table is the evidence. Duplicated raw OCR is displayed
        // for the user but must not reintroduce broken rows into inference.
        let table = text.components(separatedBy: "\n\n원본 OCR:\n").first ?? text
        let evidence: String
        var namedCountQuestion = false
        let items = Solver.receiptItems(table)
        guard !text.hasPrefix("영수증 표 확인 필요:") || items != nil else {
            throw LensError.message("영수증의 품목과 숫자를 확실하게 연결하지 못했습니다. 원본을 확인하고 ‘품목 가격 수량 합계’ 표로 수정하거나, 더 선명한 사진을 열어 주세요.")
        }
        if let items = items {
            let normalizedQuestion = question.replacingOccurrences(of: " ", with: "")
            let named = items.filter {
                let label = $0.name.replacingOccurrences(of: #"\d+(?:\.\d+)?\s*(?:kg|킬로그램)"#, with: "", options: .regularExpression).replacingOccurrences(of: " ", with: "")
                return !label.isEmpty && normalizedQuestion.contains(label)
            }
            // Select an explicitly named row, never compute or insert an answer.
            namedCountQuestion = normalizedQuestion.contains("몇개") && !normalizedQuestion.contains("총") && !normalizedQuestion.contains("전체") && named.count == 1
            let relevant = namedCountQuestion ? named : items
            evidence = relevant.map {
                "Product: \($0.name); Quantity (items): \(Solver.format($0.quantity)); Unit price (KRW): \(Solver.format($0.total / $0.quantity)); Total price (KRW): \(Solver.format($0.total))"
            }.joined(separator: "\n")
        } else { evidence = table }
        var userPrompt = items != nil ? """
        Receipt data:
        \(evidence.precomposedStringWithCanonicalMapping)
        Question: \(question.precomposedStringWithCanonicalMapping)
        Product-name weights describe ONE item. Quantity is the number of purchased items, not weight or price.
        For total item count, sum the Quantity field over ALL rows.
        Return only the final number followed by its unit: kg for weight, 개 for item count. No examples or explanation.
        """ : """
        다음 지문을 근거로 질문에 한국어로 간결하게 답하세요. 지문에 답의 근거가 없으면 확인할 수 없다고 답하세요.
        지문:
        \(evidence.precomposedStringWithCanonicalMapping)
        질문: \(question.precomposedStringWithCanonicalMapping)
        """
        if namedCountQuestion {
            userPrompt = userPrompt.replacingOccurrences(of: "Return only the final number", with: "For the purchased count of a named product, use that product's Quantity field.\nReturn only the final number")
        }
        if items != nil, question.contains("가격") || question.contains("금액") {
            userPrompt = """
            Receipt data:
            \(evidence.precomposedStringWithCanonicalMapping)
            Question: \(question.precomposedStringWithCanonicalMapping)
            Unit price is the price of ONE item. To find the most purchased product, compare the Quantity fields, not the prices.
            Return only the requested price as a number followed by 원. No examples or explanation.
            """
        }
        let completion = URL(fileURLWithPath: executable).lastPathComponent == "llama-completion"
        let modelName = URL(fileURLWithPath: model).lastPathComponent.lowercased()
        let qwen3 = modelName.contains("qwen3") && !modelName.contains("instruct-2507")
        let thinking = modelName.contains("thinking-2507")
        let suffix = thinking ? "<think>\n" : qwen3 ? "<think>\n\n</think>\n\n" : ""
        let prompt: String
        if completion, modelName.contains("exaone") {
            prompt = "[|system|]You are EXAONE model from LG AI Research, a helpful assistant.[|endofturn|]\n[|user|]\(userPrompt)\n[|assistant|]"
        } else {
            prompt = completion ? "<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n\(suffix)" : userPrompt
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        var arguments = ["--model", model, "--offline", "--threads", "2", "--threads-batch", "2",
                           "--ctx-size", "2048", "--batch-size", "128", "--ubatch-size", "128",
                           "--n-gpu-layers", "0", "--predict", thinking ? "512" : "256", "--temp", thinking ? "0.6" : "0", "--seed", "42",
                           "--top-p", thinking ? "0.95" : "0.8", "--top-k", "20", "--min-p", "0", "--repeat-penalty", "1.05",
                           "--device", "none", "--no-op-offload", "--no-kv-offload", "--fit", "off",
                           "--no-display-prompt", "--no-warmup", "--simple-io", "--no-escape",
                           "--color", "off", "--file", "/dev/stdin"]
        arguments += completion ? ["--no-conversation"] : ["--single-turn", "--no-show-timings"]
        child.arguments = arguments
        // Avoid inheriting LLAMA_ARG_* / remote model settings from the caller.
        child.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8", "LLAMA_OFFLINE": "1"]
        child.qualityOfService = .utility
        // macOS Foundation encodes Process arguments using filesystem string
        // conversion, which can decompose Hangul into Jamo. Send UTF-8 content
        // through stdin instead of placing the Korean prompt in argv.
        let input = Pipe()
        child.standardInput = input
        let pipe = Pipe()
        child.standardOutput = pipe
        // Prevent logs containing the prompt from being saved to disk.
        child.standardError = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw LensError.message("AI 실행을 취소했습니다.") }
        running = child
        do { try child.run() } catch { running = nil; lock.unlock(); throw error }
        lock.unlock()
        let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
            lock.lock(); running = nil; lock.unlock()
            try? pipe.fileHandleForReading.close()
        }
        try input.fileHandleForWriting.write(contentsOf: Data(prompt.precomposedStringWithCanonicalMapping.utf8))
        try input.fileHandleForWriting.close()
        // Drain while the child runs, keeping output memory bounded.
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if data.count + chunk.count > 64 * 1024 { cancel(); break }
            data.append(chunk)
        }
        child.waitUntilExit()
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw LensError.message("AI 실행이 중지되었습니다. 취소했거나 60초 실행 제한에 도달했습니다.") }
        guard child.terminationStatus == 0 else {
            throw LensError.message("로컬 AI 실행에 실패했습니다. 모델과 llama-cli 버전 호환성을 확인해 주세요.")
        }
        if CommandLine.arguments.contains("--trace-model") {
            try? FileHandle.standardError.write(contentsOf: data)
        }
        var result = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "[end of text]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if thinking {
            guard let closing = result.range(of: "</think>") else {
                throw LensError.message("AI가 출력 한도 안에 계산을 완료하지 못했습니다.")
            }
            result = String(result[closing.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !thinking {
            result = result.replacingOccurrences(of: #"<think>[\s\S]*?</think>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let final = result.range(of: "정답:", options: .backwards) {
            result = String(result[final.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if items == nil {
            result = result.replacingOccurrences(of: #"^[:：]\s*"#, with: "", options: .regularExpression)
        }
        // Normalize unit-first answers without changing the model's numeric value.
        let formatted = result.replacingOccurrences(of: #"^(kg|킬로그램|개|원)\s*(-?\d+(?:\.\d+)?)$"#, with: "$2$1", options: .regularExpression)
        guard !formatted.isEmpty else { throw LensError.message("AI가 답변을 반환하지 않았습니다.") }
        if items != nil, formatted.range(of: #"^-?\d+(?:\.\d+)?\s*(?:kg|킬로그램|개|원)$"#, options: .regularExpression) == nil {
            throw LensError.message("AI가 숫자와 단위를 갖춘 답변을 완료하지 못했습니다. 원본과 복원한 표를 확인한 뒤 다시 시도해 주세요.")
        }
        return "AI 답변 · 원문과 대조해 주세요\n\n" + formatted
    }
}
