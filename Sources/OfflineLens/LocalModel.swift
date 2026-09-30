import Foundation
import Darwin
import OfflineLensCore

final class LocalModel {
    private let lock = NSLock()
    private var running: Process?
    private var cancelled = false

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
        let attributes = try FileManager.default.attributesOfItem(atPath: model)
        guard (attributes[.size] as? NSNumber)?.int64Value ?? Int64.max <= 800_000_000 else {
            throw LensError.message("이 앱은 자원 사용을 줄이기 위해 800MB 이하 모델만 사용합니다. 0.6B급 4비트 GGUF를 선택해 주세요.")
        }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: model))
        let magic = try handle.read(upToCount: 4)
        try handle.close()
        guard magic == Data("GGUF".utf8) else { throw LensError.message("올바른 GGUF 모델 파일이 아닙니다.") }
        guard ProcessInfo.processInfo.thermalState != .serious, ProcessInfo.processInfo.thermalState != .critical else {
            throw LensError.message("Mac의 온도가 높아 AI 실행을 쉬고 있습니다. 잠시 후 다시 시도해 주세요.")
        }
        // The verified table is the evidence. Duplicated raw OCR is displayed
        // for the user but must not reintroduce broken rows into inference.
        let table = text.components(separatedBy: "\n\n원본 OCR:\n").first ?? text
        let evidence: String
        if let items = Solver.receiptItems(table) {
            evidence = items.map {
                "품목: \($0.name) / 개수: \(Solver.format($0.quantity))개 / 단가: \(Solver.format($0.total / $0.quantity))원 / 합계금액: \(Solver.format($0.total))원"
            }.joined(separator: "\n")
        } else { evidence = table }
        let userPrompt = """
        자료:
        \(evidence.precomposedStringWithCanonicalMapping)
        질문: \(question.precomposedStringWithCanonicalMapping)
        정답을 숫자와 단위로만 쓰세요.
        """
        let completion = URL(fileURLWithPath: executable).lastPathComponent == "llama-completion"
        let qwen3 = URL(fileURLWithPath: model).lastPathComponent.lowercased().contains("qwen3")
        let suffix = qwen3 ? "<think>\n\n</think>\n\n" : ""
        let prompt = completion ? "<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n\(suffix)" : userPrompt
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        var arguments = ["--model", model, "--offline", "--threads", "2", "--threads-batch", "2",
                           "--ctx-size", "2048", "--batch-size", "128", "--ubatch-size", "128",
                           "--n-gpu-layers", "0", "--predict", "256", "--temp", "0.7", "--seed", "42",
                           "--top-p", "0.8", "--top-k", "20", "--min-p", "0", "--repeat-penalty", "1.05",
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
        try input.fileHandleForWriting.write(contentsOf: Data(prompt.precomposedStringWithCanonicalMapping.utf8))
        try input.fileHandleForWriting.close()
        let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60, execute: timeout)
        defer {
            timeout.cancel()
            lock.lock(); running = nil; lock.unlock()
            try? pipe.fileHandleForReading.close()
        }
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
        let result = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #"<think>[\s\S]*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "[end of text]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LensError.message("AI가 답변을 반환하지 않았습니다.") }
        return "AI 답변 · 원문과 대조해 주세요\n\n" + result
    }
}
