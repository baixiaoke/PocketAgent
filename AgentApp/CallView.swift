import SwiftUI
import AVFoundation

// MARK: - 相机

final class CameraController: ObservableObject {
    let session = AVCaptureSession()
    @Published var denied = false
    private let queue = DispatchQueue(label: "pocketagent.camera")
    private var configured = false

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                DispatchQueue.main.async { self.denied = true }
                return
            }
            self.queue.async {
                if !self.configured {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                            for: .video, position: .front),
                       let input = try? AVCaptureDeviceInput(device: device),
                       self.session.canAddInput(input) {
                        self.session.addInput(input)
                    }
                    self.session.commitConfiguration()
                    self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

// MARK: - 通话界面

struct CallView: View {
    @EnvironmentObject private var rt: AgentRuntime
    @Environment(\.dismiss) private var dismiss

    @StateObject private var speech = SpeechEngine()
    @StateObject private var voice = VoiceOut()
    @StateObject private var camera = CameraController()

    @State private var videoMode = true
    @State private var thinking = false
    @State private var localLines: [String] = []

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                centerStatus
                Spacer(minLength: 0)
                subtitle
                controls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .preferredColorScheme(.dark)
        .onAppear { begin() }
        .onDisappear { end() }
        .onChange(of: rt.isRunning) { running in
            if !running, thinking {
                thinking = false
                speakLast()
            }
        }
    }

    // MARK: 背景
    private var background: some View {
        ZStack {
            if videoMode {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.15), .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.12),
                                        Color(red: 0.02, green: 0.02, blue: 0.05)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                end()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Spacer()
            Text(rt.settings.agentName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                videoMode.toggle()
                if videoMode { camera.start() } else { camera.stop() }
            } label: {
                Image(systemName: videoMode ? "video.fill" : "video.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }
        }
    }

    private var centerStatus: some View {
        VStack(spacing: 14) {
            if !videoMode {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.85), .purple.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 132, height: 132)
                    .overlay(
                        Text(String(rt.settings.agentName.prefix(1)))
                            .font(.system(size: 54, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .scaleEffect(1 + CGFloat(speech.level) * 0.06)
                    .animation(.easeOut(duration: 0.15), value: speech.level)
            }

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))

            if speech.isListening {
                HStack(spacing: 4) {
                    ForEach(0..<9) { i in
                        Capsule()
                            .fill(.white.opacity(0.7))
                            .frame(width: 3,
                                   height: 8 + CGFloat(speech.level) * CGFloat(28 - abs(i - 4) * 4))
                    }
                }
                .frame(height: 34)
                .animation(.easeOut(duration: 0.12), value: speech.level)
            }
        }
    }

    private var statusText: String {
        if rt.pendingApproval != nil { return "等你确认" }
        if thinking { return "正在想…" }
        if voice.isSpeaking { return "正在说…" }
        if speech.isListening { return "在听" }
        return "点一下开始说"
    }

    private var subtitle: some View {
        VStack(spacing: 8) {
            if let pending = rt.pendingApproval {
                VStack(alignment: .leading, spacing: 10) {
                    Text(pending.summary)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    HStack(spacing: 10) {
                        Button("确认") {
                            rt.resolveApproval(true)
                            restartListening()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("不要") {
                            rt.resolveApproval(false)
                            restartListening()
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.footnote)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            }

            if !speech.transcript.isEmpty {
                Text(speech.transcript)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            } else if let last = localLines.last {
                Text(last)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }

            if let err = speech.errorText {
                Text(err).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.bottom, 18)
    }

    private var controls: some View {
        HStack(spacing: 26) {
            Button {
                if speech.isListening { speech.stop() } else { speech.start() }
            } label: {
                Image(systemName: speech.isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(speech.isListening ? Color.blue : Color.white.opacity(0.18), in: Circle())
            }

            Button {
                end()
                dismiss()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.red, in: Circle())
            }

            Button {
                voice.stop()
                restartListening()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: 流程
    private func begin() {
        speech.onFinal = { text in
            send(text)
        }
        Task {
            let ok = await speech.requestAuthorization()
            guard ok else { return }
            if videoMode { camera.start() }
            speech.start()
        }
    }

    private func end() {
        speech.stop()
        voice.stop()
        camera.stop()
        if rt.isRunning { rt.stop() }
    }

    private func send(_ text: String) {
        speech.stop()
        localLines.append(text)
        thinking = true
        rt.start(text)
    }

    private func speakLast() {
        let reply = rt.lastAssistantText
        guard !reply.isEmpty else {
            restartListening()
            return
        }
        localLines.append(reply)
        if rt.settings.companionMode || rt.settings.autoSpeak {
            voice.rate = Float(rt.settings.speechRate)
            voice.speak(reply)
            // 念完再继续听
            Task {
                var waited = 0.0
                while voice.isSpeaking && waited < 40 {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    waited += 0.3
                }
                restartListening()
            }
        } else {
            restartListening()
        }
    }

    private func restartListening() {
        guard !rt.isRunning else { return }
        speech.errorText = nil
        speech.start()
    }
}
