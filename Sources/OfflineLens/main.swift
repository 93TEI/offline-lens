import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import OfflineLensCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let source = NSTextView()
    private let result = NSTextView()
    private let question = NSTextField(string: "")
    private let status = NSTextField(labelWithString: "대기 중 · 모델 미사용")
    private let ai = NSButton(checkboxWithTitle: "로컬 AI로 풀이", target: nil, action: nil)
    private var actionButtons: [NSButton] = []
    private var stopButton: NSButton!
    private let worker = DispatchQueue(label: "local.offlinelens.worker", qos: .utility)
    private let model = LocalModel()
    private var captureProcess: Process?
    private var captureURL: URL?
    private var captureStatusItem: NSStatusItem?
    private var busy = false
    private var primarySolveButton: NSButton!

    private var checkingUI: Bool { CommandLine.arguments.contains("--check-ui") || CommandLine.arguments.contains("--check-ui-capture") }

    private func finishUICheck(_ passed: Bool, _ message: String) {
        model.cancel()
        print("\(passed ? "PASS" : "FAIL"): UI \(message)")
        fflush(stdout)
        exit(passed ? 0 : 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ai.state = LocalModel.installedFiles() != nil ? .on : .off
        buildMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "지금 보이는 화면 캡처")
        item.button?.toolTip = "Offline Lens · 지금 보이는 화면 캡처"
        item.button?.target = self
        item.button?.action = #selector(capture)
        captureStatusItem = item
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Offline Lens · 오프라인 문제 읽기"
        window.minSize = NSSize(width: 620, height: 620)
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor)
        ])
        let title = NSTextField(labelWithString: "필요할 때만 읽고, 기기 안에서 풀어요.")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        root.addArrangedSubview(title)
        root.addArrangedSubview(NSTextField(labelWithString: "화면 캡처 → 이미지에서 글자 추출 → 질문 풀이"))
        let actions = NSStackView(views: [button("지금 보이는 화면 캡처", #selector(capture)), button("사진 열기", #selector(openImage)), button("예시", #selector(example)), button("비우기", #selector(clear))])
        actions.spacing = 8
        root.addArrangedSubview(actions)
        root.addArrangedSubview(NSTextField(labelWithString: "읽은 내용 · 틀린 글자와 숫자는 수정할 수 있어요"))
        let inputScroll = editor(source, editable: true)
        root.addArrangedSubview(inputScroll)
        inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let hint = NSTextField(wrappingLabelWithString: "영수증의 가격·개수·합계 열을 복원하고 검산합니다. 원본 OCR과 복원한 표를 확인해 주세요.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(hint)
        root.addArrangedSubview(NSTextField(labelWithString: "질문 또는 계산식"))
        question.placeholderString = "예: 4500 ÷ 3 또는 이 지문의 중심 내용은?"
        question.font = .systemFont(ofSize: 14)
        root.addArrangedSubview(question)
        let solveButton = button("풀이하기", #selector(solve))
        primarySolveButton = solveButton
        solveButton.keyEquivalent = "\r"
        stopButton = NSButton(title: "AI 중지", target: self, action: #selector(stop))
        stopButton.isEnabled = false
        let settings = button("다른 AI 연결", #selector(configure))
        let modelButton = button("AI로 풀이", #selector(solveWithAI))
        let controls = NSStackView(views: [solveButton, modelButton, stopButton, ai, settings])
        controls.spacing = 10
        root.addArrangedSubview(controls)
        let outputScroll = editor(result, editable: false)
        root.addArrangedSubview(outputScroll)
        outputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        inputScroll.heightAnchor.constraint(equalTo: outputScroll.heightAnchor, multiplier: 1.2).isActive = true
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        root.addArrangedSubview(status)
        for view in [inputScroll, outputScroll, question, hint] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        }
        let installed = LocalModel.installedFiles() != nil
        status.stringValue = installed ? "로컬 AI 준비됨 · 필요할 때만 실행" : "로컬 AI 설치 필요"
        result.string = "메뉴 막대의 카메라 아이콘으로 현재 화면을 읽거나 ‘사진 열기’로 문제 이미지를 선택하세요. 이미지 안의 질문도 자동으로 읽습니다.\n\n읽은 내용을 확인한 뒤 ‘풀이하기’를 누르세요. 로컬 AI가 켜져 있으면 모델이 직접 풉니다. AI를 끄면 지원하는 계산을 규칙으로 풉니다."
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments
        if checkingUI {
            DispatchQueue.main.asyncAfter(deadline: .now() + 100) { [weak self] in self?.finishUICheck(false, "시간 초과") }
        }
        if let index = args.firstIndex(of: "--open-image"), args.indices.contains(index + 1) {
            recognize(URL(fileURLWithPath: args[index + 1]), temporary: false)
        } else if args.contains("--check-ui-capture") {
            captureStatusItem?.button?.performClick(nil)
        }
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        actionButtons.append(button)
        return button
    }

    private func editor(_ text: NSTextView, editable: Bool) -> NSScrollView {
        text.isEditable = editable
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.font = .systemFont(ofSize: 14)
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = text
        return scroll
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Offline Lens 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let edit = NSMenu(title: "편집")
        for (title, action, key) in [("실행 취소", Selector(("undo:")), "z"), ("잘라내기", #selector(NSText.cut(_:)), "x"), ("복사", #selector(NSText.copy(_:)), "c"), ("붙여넣기", #selector(NSText.paste(_:)), "v"), ("모두 선택", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = edit
        let readItem = NSMenuItem()
        menu.addItem(readItem)
        let read = NSMenu(title: "캡처")
        let capture = read.addItem(withTitle: "지금 보이는 화면 캡처", action: #selector(self.capture), keyEquivalent: "s")
        capture.keyEquivalentModifierMask = [.command, .shift]
        capture.target = self
        readItem.submenu = read
        NSApp.mainMenu = menu
    }

    private func setBusy(_ value: Bool, _ message: String) {
        busy = value
        captureStatusItem?.button?.isEnabled = !value
        actionButtons.forEach { $0.isEnabled = !value }
        ai.isEnabled = !value
        source.isEditable = !value
        question.isEnabled = !value
        stopButton.isEnabled = false
        status.stringValue = message
    }

    @objc private func example() {
        guard !busy else { return }
        source.string = "품목 수량 합계\n우유 2 4,800\n빵 3 4,500"
        question.stringValue = "가장 많이 구매한 물건의 1개 가격은?"
        result.string = ai.state == .on ? "‘풀이하기’를 누르면 로컬 AI로 풉니다. AI를 끄면 규칙으로 계산합니다." : "‘풀이하기’를 누르면 규칙으로 계산합니다."
    }

    @objc private func clear() {
        guard !busy else { return }
        source.string = ""; result.string = ""; question.stringValue = ""
        status.stringValue = "비웠습니다 · 모델 미사용"
    }

    @objc private func openImage() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp, UTType(filenameExtension: "webp") ?? .image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { recognize(url, temporary: false) }
    }

    @objc private func capture() {
        guard !busy else { return }
        // Permission must be granted before capture. Otherwise macOS can return
        // a valid-looking wallpaper-only PNG instead of the visible windows.
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            result.string = "화면 캡처 권한이 필요합니다. 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 Offline Lens를 허용한 뒤 앱을 다시 실행해 주세요."
            status.stringValue = "화면 캡처 권한 필요 · 아직 캡처하지 않았습니다"
            if checkingUI { finishUICheck(false, "화면 녹음 권한이 필요합니다. 캡처하지 않았습니다.") }
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            result.string = "캡처할 모니터를 찾지 못했습니다."
            return
        }
        // Quartz display bounds use the same global coordinate system as -R,
        // including negative origins on secondary monitors.
        let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        let rectangle = "\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("offlinelens-\(UUID().uuidString).png")
        captureURL = url
        setBusy(true, "지금 보이는 화면을 한 번 캡처하는 중…")
        window.orderOut(nil)
        // One short delay lets this window/menu disappear. No polling or stream.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.captureVisibleScreen(rectangle: rectangle, url: url)
        }
    }

    private func captureVisibleScreen(rectangle: String, url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", rectangle, url.path]
        process.standardError = FileHandle.nullDevice
        captureProcess = process
        process.terminationHandler = { [weak self] child in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.captureProcess = nil
                self.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                if child.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) { self.recognize(url, temporary: true) }
                else {
                    try? FileManager.default.removeItem(at: url)
                    self.captureURL = nil
                    self.setBusy(false, "캡처 실패 · 화면 캡처 권한을 확인해 주세요")
                    self.result.string = "캡처가 되지 않았다면 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 Offline Lens를 허용해 주세요."
                }
            }
        }
        do { try process.run() }
        catch { captureProcess = nil; captureURL = nil; window.makeKeyAndOrderFront(nil); setBusy(false, error.localizedDescription) }
    }

    private func recognize(_ url: URL, temporary: Bool) {
        setBusy(true, "이미지에서 글자를 추출하는 중…")
        worker.async { [weak self] in
            let outcome: Result<OCRDocument, Error> = autoreleasepool { Result { try OCR.readDocument(url) } }
            if temporary { try? FileManager.default.removeItem(at: url) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.captureURL = nil
                switch outcome {
                case .success(let document):
                    self.source.string = document.text
                    self.question.stringValue = document.question ?? ""
                    self.result.string = document.receipt.map { "표 복원 · 가격 × 개수 검산 완료\n\n" + $0.evidence } ?? (document.text.hasPrefix("영수증 표 확인 필요:") ? "영수증 표를 확실하게 복원하지 못했습니다. 품목·가격·수량·합계를 원본과 대조하여 표로 수정하거나 더 선명한 사진을 열어 주세요." : "읽은 내용과 질문을 확인하고 ‘풀이하기’를 누르세요.")
                case .failure(let error): self.result.string = error.localizedDescription
                }
                self.setBusy(false, "OCR 종료 · 모델 미사용")
                if self.checkingUI {
                    switch outcome {
                    case .failure(let error): self.finishUICheck(false, error.localizedDescription)
                    case .success(let document):
                        if temporary {
                            self.finishUICheck(!FileManager.default.fileExists(atPath: url.path) && !self.source.string.isEmpty, "화면 캡처 → OCR → 임시 파일 삭제")
                        } else {
                            guard document.receipt != nil, !self.question.stringValue.isEmpty,
                                  self.ai.state == .on, self.primarySolveButton.isEnabled else {
                                self.finishUICheck(false, "표·자동 질문·AI 기본 설정 확인 실패"); return
                            }
                            self.primarySolveButton.performClick(nil)
                        }
                    }
                }
            }
        }
    }

    @objc private func solve() {
        performSolve(forceAI: false)
    }

    @objc private func solveWithAI() {
        performSolve(forceAI: true)
    }

    private func performSolve(forceAI: Bool) {
        guard !busy else { return }
        let text = source.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = question.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { result.string = "질문 또는 계산식을 입력해 주세요."; return }
        guard text.count <= 20_000, q.count <= 500 else { result.string = "한 번에 문제 하나만 입력해 주세요. 지문 20,000자, 질문 500자 이내로 제한합니다."; return }
        if !forceAI, ai.state == .off, let answer = Solver.answer(text: text, question: q) {
            result.string = answer
            status.stringValue = "계산 완료 · AI 모델 미사용"
            return
        }
        guard forceAI || ai.state == .on else {
            result.string = "현재 입력은 자동 계산으로 확실하게 풀 수 없습니다.\n\n영수증은 원본을 확인한 뒤 아래처럼 정리해 주세요.\n품목 수량 합계\n우유 2 4800\n빵 3 4500\n\n국어 지문이나 다른 질문은 ‘다른 AI 연결’ 후 ‘로컬 AI로 풀이’를 켜 주세요."
            return
        }
        guard let files = LocalModel.installedFiles() else {
            result.string = "로컬 AI가 설치되지 않았습니다. 프로젝트의 scripts/install-local-ai.py를 실행한 뒤 다시 빌드하거나, ‘다른 AI 연결’에서 모델과 실행 파일을 선택해 주세요."
            return
        }
        setBusy(true, "로컬 AI 실행 중 · 최대 60초 · 완료 후 모델 종료")
        stopButton.isEnabled = true
        model.prepare()
        worker.async { [weak self] in
            guard let self = self else { return }
            let outcome = Result { try self.model.answer(text: text, question: q, executable: files.executable, model: files.model) }
            DispatchQueue.main.async {
                switch outcome {
                case .success(let answer): self.result.string = answer
                case .failure(let error): self.result.string = error.localizedDescription
                }
                self.setBusy(false, "대기 중 · 모델 프로세스 없음")
                if self.checkingUI {
                    let args = CommandLine.arguments
                    let expected = args.firstIndex(of: "--ui-expected").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
                    switch outcome {
                    case .success(let answer):
                        let final = answer.components(separatedBy: "\n\n").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.finishUICheck(expected != nil && final == expected && self.primarySolveButton.isEnabled && !self.stopButton.isEnabled,
                                           "사진 열기 → 표 복원 → 자동 질문 → 풀이 버튼 → \(final ?? "") → 대기 상태 복귀")
                    case .failure(let error): self.finishUICheck(false, error.localizedDescription)
                    }
                }
            }
        }
    }

    @objc private func stop() { model.cancel(); stopButton.isEnabled = false }

    @objc private func configure() {
        guard !busy else { return }
        let executable = NSOpenPanel()
        executable.title = "로컬 llama-completion 또는 llama-cli 선택"
        executable.message = "미리 준비한 llama.cpp의 llama-cli를 선택하세요. 앱은 파일을 다운로드하지 않습니다."
        executable.allowsMultipleSelection = false
        guard executable.runModal() == .OK, let binary = executable.url else { return }
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { result.string = "실행 가능한 llama-cli 파일을 선택해 주세요."; return }
        let model = NSOpenPanel()
        model.title = "6GB 이하의 GGUF 모델 선택"
        model.message = "검증된 3B~7B급 4비트 모델을 선택하세요. 두 파일의 경로만 저장합니다."
        model.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        model.allowsMultipleSelection = false
        guard model.runModal() == .OK, let file = model.url else { return }
        UserDefaults.standard.set(binary.path, forKey: "llamaExecutable")
        UserDefaults.standard.set(file.path, forKey: "ggufModel")
        status.stringValue = "AI 파일 연결됨 · 아직 모델을 불러오지 않았습니다"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // orderOut temporarily removes our only window during screen capture.
        // Keep the app alive through the delay, capture process, and OCR.
        captureURL == nil
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.cancel()
        if let captureProcess = captureProcess, captureProcess.isRunning { captureProcess.terminate(); captureProcess.waitUntilExit() }
        if let captureURL = captureURL { try? FileManager.default.removeItem(at: captureURL) }
    }
}

if CommandLine.arguments.contains("--check-text") {
    do { try ImageCheck.runText(); exit(0) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

if CommandLine.arguments.contains("--check-image") {
    do { try ImageCheck.run(); exit(0) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

if CommandLine.arguments.contains("--check-ocr") {
    do { try SmokeCheck.run(); exit(0) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
