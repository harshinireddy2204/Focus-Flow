import SwiftUI
import Charts
import AVFoundation
import AudioToolbox
import Speech
#if canImport(RealityKit)
import RealityKit
#endif

@main
struct FocusFlowApp: App {
    @StateObject private var kingdom = KingdomState()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(kingdom)
        }
    }
}

// MARK: - Haptic Feedback Engine

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Audio Accessibility Engine (Text-to-Speech + Sound Cues)

class AccessibilityAudio: ObservableObject {
    static let shared = AccessibilityAudio()

    @Published var speechEnabled: Bool = false
    @Published var soundCuesEnabled: Bool = true
    @Published var isListening: Bool = false
    @Published var voiceTranscript: String = ""
    @Published var micPermissionGranted: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        if UIAccessibility.isVoiceOverRunning { speechEnabled = true }
    }

    // MARK: - Text-to-Speech

    func speak(_ text: String, priority: Bool = false) {
        guard speechEnabled else { return }
        if priority { synthesizer.stopSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }

    func stopSpeaking() { synthesizer.stopSpeaking(at: .immediate) }

    func playSound(_ soundID: SystemSoundID) {
        guard soundCuesEnabled else { return }
        AudioServicesPlaySystemSound(soundID)
    }

    func coinSound() { playSound(1057) }
    func successSound() { playSound(1025) }
    func buildSound() { playSound(1104) }
    func levelUpSound() { playSound(1335) }
    func timerDoneSound() { playSound(1005) }
    func tapSound() { playSound(1104) }

    // MARK: - Voice Input (Speech Recognition)

    func requestMicPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.micPermissionGranted = status == .authorized
            }
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { if granted { self.micPermissionGranted = true } }
        }
    }

    func startListening(onResult: @escaping (String) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            speak("Voice input is not available on this device.", priority: true)
            return
        }

        if audioEngine.isRunning { stopListening(); return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        if #available(iOS 13, *) { request.requiresOnDeviceRecognition = true }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }

        let inputNode = audioEngine.inputNode
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.voiceTranscript = result.bestTranscription.formattedString
                    onResult(self.voiceTranscript)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self.stopListening()
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async { self.isListening = true }
            speak("Listening. Say your task now.", priority: true)
        } catch { }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        DispatchQueue.main.async { self.isListening = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Contextual Announcements

    func announceTaskCompletion(task: String, coins: Int, bonus: Int) {
        var msg = "Task complete! \(task). You earned \(coins) coins."
        if bonus > 0 { msg += " Bonus! All tasks done. Plus \(bonus) extra coins!" }
        speak(msg, priority: true); successSound()
    }

    func announceTimerUpdate(seconds: Int) {
        if seconds == 30 { speak("30 seconds remaining. Almost there!") }
        else if seconds == 10 { speak("10 seconds. Final push!") }
        else if seconds == 0 { speak("Time is up! Session complete.", priority: true); timerDoneSound() }
    }

    func announceBreakdown(topic: String, count: Int, steps: [String]) {
        var msg = "Analysis complete. \(count) personalized tasks created for \(topic). "
        for (i, step) in steps.prefix(5).enumerated() {
            msg += "Step \(i + 1): \(step). "
        }
        if steps.count > 5 { msg += "And \(steps.count - 5) more steps." }
        speak(msg, priority: true)
    }

    func announceBuildingPurchase(name: String) {
        speak("Built a \(name) in your kingdom!", priority: true); buildSound()
    }

    func announceLevelUp(level: Int, title: String) {
        speak("Level up! You are now level \(level), a \(title)!", priority: true); levelUpSound()
    }

    func announceBuilding(building: String, category: String, benefit: String) {
        speak("\(building) in the \(category) zone. \(benefit).")
    }

    func announceQuizResult(score: Int, coins: Int) {
        speak("Quiz complete! You scored \(score) out of 10 and earned \(coins) coins.", priority: true)
    }

    func announceScreen(_ name: String, detail: String = "") {
        let msg = detail.isEmpty ? "Opened \(name)." : "Opened \(name). \(detail)"
        speak(msg, priority: true)
    }

    func announceOnboarding() {
        speak("Welcome to Kingdom Builder! This app turns any learning task into focused sessions that build your own kingdom. You can speak your tasks using the microphone button, or type them. The AI will break them down into steps. Each completed session earns coins you can spend to build houses, shops, libraries, and more. Tap Start Building to begin.", priority: true)
    }
}

// MARK: - Accessibility Settings View

struct AccessibilitySettingsView: View {
    @ObservedObject var audio = AccessibilityAudio.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "ear.badge.waveform")
                            .font(.system(size: 48))
                            .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                        Text("Audio Accessibility")
                            .font(.system(.title2, design: .rounded)).bold()
                        Text("For blind and visually impaired users. Speech turns on automatically when VoiceOver is detected.")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }

                Section("Voice Input") {
                    HStack(spacing: 14) {
                        Image(systemName: "mic.circle.fill").font(.system(size: 36))
                            .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speak Your Tasks").font(.system(.body, design: .rounded)).bold()
                            Text("Tap the microphone button on the task input screen to speak instead of type. Uses on-device speech recognition — no internet needed.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    HStack(spacing: 8) {
                        Circle().fill(audio.micPermissionGranted ? Color.green : Color.orange).frame(width: 10, height: 10)
                        Text(audio.micPermissionGranted ? "Microphone permission granted" : "Microphone permission needed — tap mic button to allow")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("Voice") {
                    Toggle(isOn: $audio.speechEnabled) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Text-to-Speech").font(.system(.body, design: .rounded)).bold()
                                Text("Reads task breakdowns, timer updates, building info, and rewards aloud")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        } icon: { Image(systemName: "speaker.wave.3.fill").foregroundColor(.blue) }
                    }
                    .accessibilityLabel("Text to speech")
                    .accessibilityHint("When enabled, the app reads important information aloud")

                    if audio.speechEnabled {
                        Button {
                            audio.speak("Hello! I'm your Kingdom Builder assistant. I'll announce task completions, timer updates, and building information to help you stay focused.", priority: true)
                        } label: {
                            Label("Test Voice", systemImage: "play.circle.fill")
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.purple)
                        }
                        .accessibilityLabel("Test text to speech voice")
                    }
                }

                Section("Sound Effects") {
                    Toggle(isOn: $audio.soundCuesEnabled) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sound Cues").font(.system(.body, design: .rounded)).bold()
                                Text("Plays distinct sounds for coins, completions, building, and level-ups")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        } icon: { Image(systemName: "bell.badge.waveform.fill").foregroundColor(.orange) }
                    }
                    .accessibilityLabel("Sound cues")
                    .accessibilityHint("When enabled, the app plays sounds for key interactions")

                    if audio.soundCuesEnabled {
                        HStack(spacing: 12) {
                            SoundTestButton(label: "Coin", icon: "dollarsign.circle") { audio.coinSound() }
                            SoundTestButton(label: "Done", icon: "checkmark.circle") { audio.successSound() }
                            SoundTestButton(label: "Build", icon: "building.2") { audio.buildSound() }
                            SoundTestButton(label: "Level", icon: "arrow.up.circle") { audio.levelUpSound() }
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                }

                Section("What Gets Announced") {
                    AudioFeatureRow(icon: "hand.wave.fill", color: .pink, title: "Onboarding",
                                    detail: "Speaks full app introduction on first launch")
                    AudioFeatureRow(icon: "mic.fill", color: .purple, title: "Voice Input",
                                    detail: "Speak your task — on-device recognition, no internet")
                    AudioFeatureRow(icon: "brain.head.profile", color: .purple, title: "AI Task Breakdown",
                                    detail: "Reads topic, step count, and each step aloud")
                    AudioFeatureRow(icon: "timer", color: .cyan, title: "Focus Timer",
                                    detail: "Announces start, 30s, 10s remaining, and session complete")
                    AudioFeatureRow(icon: "dollarsign.circle.fill", color: .orange, title: "Rewards",
                                    detail: "Announces coins earned and group bonuses")
                    AudioFeatureRow(icon: "building.2.fill", color: .green, title: "Buildings",
                                    detail: "Reads building name, zone, and benefits on tap")
                    AudioFeatureRow(icon: "rectangle.stack.fill", color: .indigo, title: "Screen Navigation",
                                    detail: "Announces shop, activity hub, and settings on open")
                    AudioFeatureRow(icon: "graduationcap.fill", color: .yellow, title: "Quizzes",
                                    detail: "Announces quiz scores and coin rewards")
                    AudioFeatureRow(icon: "arrow.up.circle.fill", color: .blue, title: "Level Ups",
                                    detail: "Announces new level and kingdom title")
                }
            }
            .navigationTitle("Accessibility").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct SoundTestButton: View {
    let label: String; let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundColor(.blue)
                Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Test \(label) sound")
    }
}

struct AudioFeatureRow: View {
    let icon: String; let color: Color; let title: String; let detail: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.subheadline, design: .rounded)).bold()
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Data Models

struct TaskPiece: Identifiable, Codable {
    let id: UUID
    var title: String
    var minutes: Int
    var completed: Bool = false
    var groupID: UUID
    init(id: UUID = UUID(), title: String, minutes: Int, completed: Bool = false, groupID: UUID) {
        self.id = id; self.title = title; self.minutes = minutes; self.completed = completed; self.groupID = groupID
    }
}

enum ShopCategory: String, CaseIterable, Identifiable {
    case housing, economy, culture, defense, nature
    var id: String { rawValue }
    var name: String {
        switch self {
        case .housing: return "Housing"; case .economy: return "Economy"
        case .culture: return "Culture"; case .defense: return "Defense"; case .nature: return "Nature"
        }
    }
    var icon: String {
        switch self {
        case .housing: return "house.fill"; case .economy: return "dollarsign.circle.fill"
        case .culture: return "book.fill"; case .defense: return "shield.fill"; case .nature: return "leaf.fill"
        }
    }
    var color: Color {
        switch self {
        case .housing: return .blue; case .economy: return .orange
        case .culture: return .purple; case .defense: return .red; case .nature: return .green
        }
    }
    var description: String {
        switch self {
        case .housing: return "Grow your population"; case .economy: return "One-time coin bonus per building"
        case .culture: return "Boost XP earned"; case .defense: return "Protect your streak"; case .nature: return "Beautify your kingdom"
        }
    }
}

enum BuildingType: String, CaseIterable, Codable {
    case cottage, house, manor, palace
    case marketStall, shop, tradingPost, bank
    case library, school, university, academy
    case watchtower, wall, fortress, castle
    case garden, park, fountain, lake

    var emoji: String {
        switch self {
        case .cottage: return "🛖"; case .house: return "🏠"; case .manor: return "🏡"; case .palace: return "👑"
        case .marketStall: return "🏪"; case .shop: return "🛒"; case .tradingPost: return "🏛️"; case .bank: return "🏦"
        case .library: return "📚"; case .school: return "🏫"; case .university: return "🎓"; case .academy: return "🔬"
        case .watchtower: return "🗼"; case .wall: return "🧱"; case .fortress: return "🏯"; case .castle: return "🏰"
        case .garden: return "🌳"; case .park: return "🌷"; case .fountain: return "⛲"; case .lake: return "🌊"
        }
    }
    var name: String {
        switch self {
        case .cottage: return "Cottage"; case .house: return "House"; case .manor: return "Manor"; case .palace: return "Palace"
        case .marketStall: return "Market Stall"; case .shop: return "Shop"; case .tradingPost: return "Trading Post"; case .bank: return "Bank"
        case .library: return "Library"; case .school: return "School"; case .university: return "University"; case .academy: return "Academy"
        case .watchtower: return "Watchtower"; case .wall: return "Wall"; case .fortress: return "Fortress"; case .castle: return "Castle"
        case .garden: return "Garden"; case .park: return "Park"; case .fountain: return "Fountain"; case .lake: return "Lake"
        }
    }
    var category: ShopCategory {
        switch self {
        case .cottage, .house, .manor, .palace: return .housing
        case .marketStall, .shop, .tradingPost, .bank: return .economy
        case .library, .school, .university, .academy: return .culture
        case .watchtower, .wall, .fortress, .castle: return .defense
        case .garden, .park, .fountain, .lake: return .nature
        }
    }
    var cost: Int {
        switch self {
        case .cottage: return 15; case .house: return 40; case .manor: return 80; case .palace: return 200
        case .marketStall: return 20; case .shop: return 50; case .tradingPost: return 100; case .bank: return 250
        case .library: return 25; case .school: return 55; case .university: return 120; case .academy: return 280
        case .watchtower: return 20; case .wall: return 45; case .fortress: return 100; case .castle: return 300
        case .garden: return 10; case .park: return 25; case .fountain: return 50; case .lake: return 100
        }
    }
    var benefit: String {
        switch self {
        case .cottage: return "+2 population"; case .house: return "+5 population"; case .manor: return "+10 population"; case .palace: return "+25 population"
        case .marketStall: return "+3 coins (one-time)"; case .shop: return "+8 coins (one-time)"; case .tradingPost: return "+15 coins (one-time)"; case .bank: return "+30 coins (one-time)"
        case .library: return "+5% XP boost"; case .school: return "+10% XP boost"; case .university: return "+20% XP boost"; case .academy: return "+35% XP boost"
        case .watchtower: return "Streak shield (1)"; case .wall: return "Streak shield (2)"; case .fortress: return "Streak shield (3)"; case .castle: return "Streak shield (5)"
        case .garden: return "+5 beauty"; case .park: return "+10 beauty"; case .fountain: return "+20 beauty"; case .lake: return "+40 beauty"
        }
    }
    var benefitValue: Int {
        switch self {
        case .cottage: return 2; case .house: return 5; case .manor: return 10; case .palace: return 25
        case .marketStall: return 3; case .shop: return 8; case .tradingPost: return 15; case .bank: return 30
        case .library: return 5; case .school: return 10; case .university: return 20; case .academy: return 35
        case .watchtower: return 1; case .wall: return 2; case .fortress: return 3; case .castle: return 5
        case .garden: return 5; case .park: return 10; case .fountain: return 20; case .lake: return 40
        }
    }
    static func forCategory(_ cat: ShopCategory) -> [BuildingType] {
        allCases.filter { $0.category == cat }
    }
}

struct KingdomBuilding: Identifiable, Codable {
    let id: UUID
    var type: BuildingType
    var col: Int
    var row: Int
    var jitterX: CGFloat
    var jitterY: CGFloat
    var scale: CGFloat = 0.0
    var builtAt: Date = Date()
    var hasCollected: Bool = false  // Economy buildings: one-time collection only
    init(id: UUID = UUID(), type: BuildingType, col: Int, row: Int, jitterX: CGFloat = 0, jitterY: CGFloat = 0) {
        self.id = id; self.type = type; self.col = col; self.row = row; self.jitterX = jitterX; self.jitterY = jitterY
    }
}

struct TaskHistoryEntry: Identifiable, Codable {
    let id: UUID
    let title: String
    let topic: String
    let completedAt: Date
    let coinsEarned: Int
    let wasGroupComplete: Bool
    init(id: UUID = UUID(), title: String, topic: String, completedAt: Date = Date(), coinsEarned: Int, wasGroupComplete: Bool = false) {
        self.id = id; self.title = title; self.topic = topic; self.completedAt = completedAt; self.coinsEarned = coinsEarned; self.wasGroupComplete = wasGroupComplete
    }
}

struct KnowledgeEntry: Identifiable, Codable {
    let id: UUID
    var topic: String
    var tasksCompleted: Int
    var quizScore: Int
    var lastStudied: Date
    var masteryLevel: Int
    init(id: UUID = UUID(), topic: String, tasksCompleted: Int = 0, quizScore: Int = 0, lastStudied: Date = Date(), masteryLevel: Int = 0) {
        self.id = id; self.topic = topic; self.tasksCompleted = tasksCompleted; self.quizScore = quizScore; self.lastStudied = lastStudied; self.masteryLevel = masteryLevel
    }
    var masteryLabel: String {
        switch masteryLevel { case 0: return "Beginner"; case 1: return "Familiar"; case 2: return "Competent"; case 3: return "Proficient"; default: return "Expert" }
    }
    var masteryColor: Color {
        switch masteryLevel { case 0: return .gray; case 1: return .blue; case 2: return .green; case 3: return .purple; default: return .orange }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID(); let color: Color; let xOffset: CGFloat; let yOffset: CGFloat
    let size: CGFloat; let delay: Double; let duration: Double; let rotation: Double
}

// MARK: - State Management

class KingdomState: ObservableObject {
    @Published var tasks: [TaskPiece] = []
    @Published var buildings: [KingdomBuilding] = []
    @Published var coins: Int = 0
    @Published var totalFocusMinutes: Int = 0
    @Published var completedGroups: Set<UUID> = []
    @Published var buildingCount: Int = 0
    @Published var hasSeenOnboarding: Bool = false
    @Published var focusStreak: Int = 0
    @Published var showCelebration: Bool = false
    @Published var showLevelUp: Bool = false
    @Published var previousLevel: Int = 1
    @Published var lastCoinsEarned: Int = 0
    @Published var lastGroupBonus: Int = 0
    @Published var showShopHint: Bool = false
    @Published var selectedBuilding: KingdomBuilding? = nil
    @Published var taskHistory: [TaskHistoryEntry] = []
    @Published var knowledgeMap: [KnowledgeEntry] = []
    @Published var groupTopics: [UUID: String] = [:]

    let focusDuration: Int = 15
    let coinsPerTask: Int = 10
    let groupBonusCoins: Int = 50

    // MARK: Kingdom Stats

    var population: Int { buildings.filter { $0.type.category == .housing }.reduce(0) { $0 + $1.type.benefitValue } }
    var economyIncome: Int { buildings.filter { $0.type.category == .economy && !$0.hasCollected }.reduce(0) { $0 + $1.type.benefitValue } }
    var xpBoostPercent: Int { buildings.filter { $0.type.category == .culture }.reduce(0) { $0 + $1.type.benefitValue } }
    var streakShield: Int { buildings.filter { $0.type.category == .defense }.reduce(0) { $0 + $1.type.benefitValue } }
    var beautyScore: Int { buildings.filter { $0.type.category == .nature }.reduce(0) { $0 + $1.type.benefitValue } }
    var allTasksComplete: Bool { !tasks.isEmpty && tasks.allSatisfy { $0.completed } }

    func buildingsInZone(_ cat: ShopCategory) -> [KingdomBuilding] { buildings.filter { $0.type.category == cat } }

    var level: Int {
        let xp = totalXP
        if xp < 100 { return 1 }; if xp < 300 { return 2 }; if xp < 600 { return 3 }
        if xp < 1000 { return 4 }; if xp < 1500 { return 5 }; if xp < 2200 { return 6 }
        if xp < 3000 { return 7 }; if xp < 4000 { return 8 }; if xp < 5500 { return 9 }
        return 10
    }
    var baseXP: Int { totalFocusMinutes * 10 + buildingCount * 50 + coins }
    var totalXP: Int { Int(Double(baseXP) * (1.0 + Double(xpBoostPercent) / 100.0)) }
    var xpForCurrentLevel: Int { [0,100,300,600,1000,1500,2200,3000,4000,5500,99999][min(level,10)-1] }
    var xpForNextLevel: Int { [0,100,300,600,1000,1500,2200,3000,4000,5500,99999][min(level,10)] }
    var xpProgress: Double {
        let c = totalXP - xpForCurrentLevel; let n = xpForNextLevel - xpForCurrentLevel
        guard n > 0 else { return 1.0 }; return min(1.0, Double(c) / Double(n))
    }
    var kingdomTitle: String {
        switch level {
        case 1: return "Settlement"; case 2: return "Hamlet"; case 3: return "Village"
        case 4: return "Town"; case 5: return "Borough"; case 6: return "City"
        case 7: return "Metropolis"; case 8: return "Capital"; case 9: return "Empire"
        default: return "Legendary Realm"
        }
    }
    var todayTaskCount: Int {
        let cal = Calendar.current
        return taskHistory.filter { cal.isDateInToday($0.completedAt) }.count
    }
    var totalCoinsEarned: Int { taskHistory.reduce(0) { $0 + $1.coinsEarned } }

    // MARK: AI City Advisor

    var aiAdvisorTip: String {
        if buildings.isEmpty { return "Start by building a Cottage to settle your first citizens!" }
        let cats = Dictionary(grouping: buildings, by: { $0.type.category })
        let h = cats[.housing]?.count ?? 0; let e = cats[.economy]?.count ?? 0
        let c = cats[.culture]?.count ?? 0; let d = cats[.defense]?.count ?? 0
        let n = cats[.nature]?.count ?? 0; let t = buildings.count
        if e == 0 && t >= 1 { return "Build a Market Stall — collect a one-time coin bonus!" }
        if d == 0 && focusStreak >= 3 { return "Protect your streak! Build a Watchtower on the border." }
        if c == 0 && t >= 3 { return "A Library in the Cultural Quarter will boost XP!" }
        if n == 0 && t >= 4 { return "Citizens want parks! Beautify with a Garden." }
        if Double(e)/Double(max(t,1)) < 0.15 { return "Economy is weak — invest in more shops!" }
        if Double(h)/Double(max(t,1)) < 0.15 { return "Build more housing to grow population!" }
        if focusStreak >= 5 && streakShield < 2 { return "Great streak! Upgrade your border defenses." }
        return ["Great balance! Keep growing.", "Try upgrading to bigger buildings!", "Diversify for best bonuses!",
                "Tap any building to see inside!", "Your kingdom is thriving!"][t % 5]
    }

    // MARK: Actions

    func addTasks(_ newTasks: [TaskPiece], groupID: UUID, topic: String = "") {
        tasks.append(contentsOf: newTasks.map { var t = $0; t.groupID = groupID; return t })
        if !topic.isEmpty { groupTopics[groupID] = topic }
    }

    func renameTask(id: UUID, newTitle: String) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].title = newTitle }
    }

    func completeTask(_ task: TaskPiece) {
        let oldLevel = level
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].completed = true }
        totalFocusMinutes += task.minutes
        focusStreak += 1

        lastCoinsEarned = coinsPerTask; lastGroupBonus = 0
        coins += coinsPerTask

        let groupComplete = checkGroupCompletion(groupID: task.groupID)
        if groupComplete { lastGroupBonus = groupBonusCoins; coins += groupBonusCoins }

        let topic = groupTopics[task.groupID] ?? TaskAI.extractTopic(from: task.title)
        taskHistory.append(TaskHistoryEntry(title: task.title, topic: topic, coinsEarned: coinsPerTask + (groupComplete ? groupBonusCoins : 0), wasGroupComplete: groupComplete))
        updateKnowledge(topic: topic, wasGroupComplete: groupComplete)

        showCelebration = true; showShopHint = true
        Haptics.notify(.success)
        AccessibilityAudio.shared.announceTaskCompletion(task: task.title, coins: lastCoinsEarned, bonus: lastGroupBonus)
        if level > oldLevel {
            previousLevel = oldLevel; showLevelUp = true; Haptics.notify(.warning)
            AccessibilityAudio.shared.announceLevelUp(level: level, title: kingdomTitle)
        }
    }

    func updateKnowledge(topic: String, wasGroupComplete: Bool) {
        let normalized = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = knowledgeMap.firstIndex(where: { $0.topic.lowercased() == normalized }) {
            knowledgeMap[i].tasksCompleted += 1
            knowledgeMap[i].lastStudied = Date()
            if wasGroupComplete && knowledgeMap[i].masteryLevel < 4 { knowledgeMap[i].masteryLevel += 1 }
        } else {
            knowledgeMap.append(KnowledgeEntry(topic: topic.capitalized, tasksCompleted: 1, masteryLevel: wasGroupComplete ? 1 : 0))
        }
    }

    @discardableResult
    func checkGroupCompletion(groupID: UUID) -> Bool {
        let g = tasks.filter { $0.groupID == groupID }
        if g.allSatisfy({ $0.completed }) && !g.isEmpty && !completedGroups.contains(groupID) {
            completedGroups.insert(groupID); return true
        }
        return false
    }

    func purchaseBuilding(type: BuildingType) {
        guard coins >= type.cost else { return }
        Haptics.impact(.heavy)
        AccessibilityAudio.shared.announceBuildingPurchase(name: type.name)
        coins -= type.cost; buildingCount += 1
        let zoneBuildings = buildingsInZone(type.category)
        let idx = zoneBuildings.count
        let col = idx % 4; let row = idx / 4
        let building = KingdomBuilding(type: type, col: col, row: row,
            jitterX: CGFloat.random(in: -0.015...0.015), jitterY: CGFloat.random(in: -0.008...0.008))
        buildings.append(building)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            if let i = buildings.firstIndex(where: { $0.id == building.id }) { buildings[i].scale = 1.0 }
        }
    }

    func collectEconomyIncome() {
        let amount = economyIncome
        guard amount > 0 else { return }
        Haptics.impact(.light)
        AccessibilityAudio.shared.coinSound()
        AccessibilityAudio.shared.speak("Collected \(amount) coins from your shops. One-time collection — each building pays once.")
        coins += amount
        for i in buildings.indices where buildings[i].type.category == .economy && !buildings[i].hasCollected {
            buildings[i].hasCollected = true
        }
    }
    func canAfford(_ type: BuildingType) -> Bool { coins >= type.cost }
    func buildingsOfType(_ type: BuildingType) -> Int { buildings.filter { $0.type == type }.count }

    func historyForCategory(_ cat: ShopCategory) -> [TaskHistoryEntry] {
        let catTopics = knowledgeMap.map { $0.topic.lowercased() }
        switch cat {
        case .culture: return taskHistory
        case .economy: return taskHistory.filter { $0.coinsEarned > 10 }
        default: return Array(taskHistory.suffix(5))
        }
    }

    func loadDemoTask() {
        coins = 20
        let g = UUID()
        groupTopics[g] = "Getting Started"
        addTasks([
            TaskPiece(title: "Complete your first focus session", minutes: 25, groupID: g),
            TaskPiece(title: "Earn coins to build your kingdom", minutes: 25, groupID: g),
            TaskPiece(title: "Unlock the full experience", minutes: 25, groupID: g)
        ], groupID: g, topic: "Getting Started")
    }
}

// MARK: - AI Task Breakdown Engine
//
// On-device NLP: extracts ACTION + TOPIC from any input, then generates
// context-aware steps. Runs fully offline (no network needed).

class TaskAI {

    enum TaskAction: String {
        case learn, build, write, practice, prepare, research, organize, read, fix, memorize, generic
    }

    static func breakdownTask(_ input: String) -> [String] {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = raw.lowercased()

        if let specific = specificDomainBreakdown(l) { return specific }

        let action = detectAction(l)
        let topic = extractTopic(from: l)
        return generateBreakdown(action: action, topic: topic)
    }

    // MARK: Specific domains with expert-level steps

    private static func specificDomainBreakdown(_ l: String) -> [String]? {
        if l.contains("machine learning") || (l.contains("ml") && l.contains("learn")) {
            if l.contains("math") {
                return ["Review Linear Algebra basics (vectors, matrices)", "Study Calculus fundamentals (derivatives, gradients)",
                        "Learn Probability theory (distributions, Bayes theorem)", "Practice Statistics (mean, variance, regression)",
                        "Apply concepts to simple ML examples", "Solve practice problems from textbook"]
            }
            return ["Setup Python environment and libraries", "Learn supervised learning concepts",
                    "Code a linear regression model", "Understand neural network basics",
                    "Build a simple classifier", "Test model on real dataset"]
        }
        if (l.contains("biology") || l.contains("bio")) && (l.contains("exam") || l.contains("test")) {
            return ["Review all biology lecture notes and diagrams", "Create flashcards for key terms and processes",
                    "Draw and label diagrams from memory", "Summarize each chapter in your own words",
                    "Practice with past biology exam questions", "Explain difficult concepts out loud",
                    "Take a timed practice test under exam conditions"]
        }
        if l.contains("chemistry") || l.contains("chem") {
            return ["Review the periodic table and element properties", "Study chemical bonding and molecular structures",
                    "Balance practice chemical equations", "Learn reaction types and mechanisms",
                    "Work through stoichiometry problems", "Practice lab-related questions",
                    "Do a full timed practice set"]
        }
        if l.contains("physics") {
            return ["Review fundamental laws and formulas", "Understand free-body diagrams and vector analysis",
                    "Work through kinematics problems step by step", "Practice energy and momentum problems",
                    "Solve circuit or wave problems (if applicable)", "Attempt multi-concept challenge problems",
                    "Review all mistakes and redo them"]
        }
        if l.contains("history") {
            return ["Create a timeline of major events and dates", "Identify key figures and their contributions",
                    "Study cause-and-effect relationships between events", "Read primary source excerpts for context",
                    "Practice writing short-answer responses", "Connect themes across different time periods",
                    "Quiz yourself on dates, names, and significance"]
        }
        if l.contains("spanish") || l.contains("french") || l.contains("german") || l.contains("japanese")
            || l.contains("chinese") || l.contains("language") || l.contains("vocab") {
            let lang = extractTopic(from: l)
            return ["Learn essential vocabulary for \(lang)", "Study grammar rules and sentence structure",
                    "Practice pronunciation with example phrases", "Write simple sentences and short paragraphs",
                    "Listen to native audio or conversations", "Have a practice conversation (real or simulated)",
                    "Review mistakes and drill weak areas"]
        }
        if l.contains("guitar") || l.contains("piano") || l.contains("music") || l.contains("instrument") {
            let subj = extractTopic(from: l)
            return ["Learn proper posture and hand positioning for \(subj)", "Practice basic scales and finger exercises",
                    "Study music theory fundamentals (notes, rhythm, chords)", "Learn a simple song from start to finish",
                    "Practice chord transitions at slow tempo", "Play along with a backing track",
                    "Record yourself and review for improvement"]
        }
        if l.contains("draw") || l.contains("sketch") || l.contains("paint") || l.contains("art") {
            return ["Gather your materials and set up workspace", "Practice basic shapes and line control",
                    "Study proportions and perspective fundamentals", "Copy a reference image step by step",
                    "Experiment with shading and light sources", "Create an original piece from imagination",
                    "Review your work and note areas to improve"]
        }
        if l.contains("essay") || l.contains("paper") {
            return ["Brainstorm ideas and choose your angle", "Research credible sources and take notes",
                    "Create detailed outline with main points", "Write strong thesis statement",
                    "Draft introduction paragraph", "Write body paragraphs with evidence",
                    "Draft compelling conclusion", "Revise for clarity and flow", "Proofread and fix grammar errors"]
        }
        if l.contains("presentation") || l.contains("slides") || l.contains("talk") || l.contains("speech") {
            return ["Research topic thoroughly", "Outline key points and flow", "Create slide structure",
                    "Design visuals and diagrams", "Write speaker notes", "Practice delivery and timing", "Get feedback and revise"]
        }
        if l.contains("cook") || l.contains("recipe") || l.contains("bake") {
            let dish = extractTopic(from: l)
            return ["Find and read through the full recipe for \(dish)", "Gather all ingredients and tools needed",
                    "Do all prep work (washing, chopping, measuring)", "Follow the cooking steps carefully",
                    "Taste and adjust seasoning", "Plate and present your dish", "Clean up and note what to improve"]
        }
        if l.contains("workout") || l.contains("exercise") || l.contains("fitness") || l.contains("run") || l.contains("training") {
            return ["Define your fitness goal and target areas", "Plan your workout routine and schedule",
                    "Start with a proper warm-up (5-10 min)", "Complete the main exercise session",
                    "Include a cool-down and stretching period", "Track your performance and progress",
                    "Rest, recover, and plan the next session"]
        }
        if l.contains("photo") || l.contains("camera") || l.contains("film") || l.contains("video") {
            let subj = extractTopic(from: l)
            return ["Study composition rules (rule of thirds, leading lines)", "Learn your camera settings (ISO, aperture, shutter)",
                    "Practice shooting in different lighting conditions", "Experiment with angles and perspectives for \(subj)",
                    "Review and select your best shots", "Edit using basic adjustments (crop, exposure, color)",
                    "Share your work and gather feedback"]
        }
        if l.contains("code") || l.contains("program") || l.contains("app") || l.contains("swift") || l.contains("python")
            || l.contains("javascript") || l.contains("web") || l.contains("develop") {
            let subj = extractTopic(from: l)
            return ["Define project requirements and goals for \(subj)", "Design the architecture and data flow",
                    "Set up development environment and tools", "Implement core functionality step by step",
                    "Write tests for your code", "Debug and fix any issues",
                    "Refactor for clean code and performance", "Document how it works"]
        }
        return nil
    }

    // MARK: Action detection from natural language

    private static func detectAction(_ input: String) -> TaskAction {
        let learnWords = ["learn", "understand", "study", "figure out", "explore", "master", "grasp", "comprehend"]
        let buildWords = ["build", "create", "make", "develop", "design", "construct", "setup", "set up", "implement"]
        let writeWords = ["write", "draft", "compose", "author", "blog", "essay", "paper", "report", "email"]
        let practiceWords = ["practice", "drill", "rehearse", "train", "exercise", "improve", "work on", "get better"]
        let prepareWords = ["prepare", "prep", "get ready", "study for", "review for", "cram"]
        let researchWords = ["research", "investigate", "analyze", "compare", "evaluate", "assess"]
        let organizeWords = ["organize", "plan", "sort", "clean", "arrange", "schedule", "manage", "declutter"]
        let readWords = ["read", "book", "chapter", "article", "textbook"]
        let fixWords = ["fix", "repair", "debug", "troubleshoot", "solve", "resolve"]
        let memorizeWords = ["memorize", "remember", "flashcard", "vocab", "vocabulary", "definitions"]

        if learnWords.contains(where: { input.contains($0) }) { return .learn }
        if buildWords.contains(where: { input.contains($0) }) { return .build }
        if writeWords.contains(where: { input.contains($0) }) { return .write }
        if practiceWords.contains(where: { input.contains($0) }) { return .practice }
        if prepareWords.contains(where: { input.contains($0) }) { return .prepare }
        if researchWords.contains(where: { input.contains($0) }) { return .research }
        if organizeWords.contains(where: { input.contains($0) }) { return .organize }
        if readWords.contains(where: { input.contains($0) }) { return .read }
        if fixWords.contains(where: { input.contains($0) }) { return .fix }
        if memorizeWords.contains(where: { input.contains($0) }) { return .memorize }
        return .generic
    }

    // MARK: Topic extraction - strips verbs/filler to get the core subject

    static func extractTopic(from input: String) -> String {
        let stopWords: Set<String> = [
            "learn", "study", "understand", "practice", "build", "create", "make", "write", "draft",
            "prepare", "research", "organize", "plan", "read", "fix", "memorize", "master", "improve",
            "get", "better", "at", "how", "to", "the", "a", "an", "my", "for", "about", "of",
            "in", "on", "with", "and", "or", "i", "want", "need", "should", "start", "begin",
            "do", "work", "help", "me", "some", "new", "this", "that", "it", "up", "set"
        ]
        let words = input.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 1 }
        let topic = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return topic.isEmpty ? input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : topic
    }

    static func displayTopic(from input: String) -> String {
        let extracted = extractTopic(from: input)
        let clean = extracted
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "Your Topic" }
        return clean.capitalized
    }

    struct InsightPack {
        let summary: String
        let whyItMatters: String
        let milestones: [String]
    }

    static func insightPack(for input: String, breakdown: [String]) -> InsightPack {
        let lower = input.lowercased()
        let action = detectAction(lower)
        let topic = displayTopic(from: input)
        let actionLine: String
        switch action {
        case .learn: actionLine = "build understanding"
        case .build: actionLine = "ship something real"
        case .write: actionLine = "communicate clearly"
        case .practice: actionLine = "improve through repetition"
        case .prepare: actionLine = "perform with confidence"
        case .research: actionLine = "think critically"
        case .organize: actionLine = "create a reliable system"
        case .read: actionLine = "retain what matters"
        case .fix: actionLine = "solve issues systematically"
        case .memorize: actionLine = "lock in long-term recall"
        case .generic: actionLine = "make steady progress"
        }
        let summary = "Here is your AI learning path for \(topic). Follow these focused tasks to \(actionLine)."
        let why = "Each completed focus session earns coins so you can unlock more houses, shops, libraries, and defenses in your kingdom."
        let milestones = Array(breakdown.prefix(3)).enumerated().map { idx, step in
            "Milestone \(idx + 1): \(step)"
        }
        return InsightPack(summary: summary, whyItMatters: why, milestones: milestones)
    }

    // MARK: Dynamic step generation based on action + topic

    private static func generateBreakdown(action: TaskAction, topic: String) -> [String] {
        let t = topic

        switch action {
        case .learn:
            return [
                "Research what \(t) covers and its key areas",
                "Study the fundamental concepts of \(t)",
                "Take structured notes on core principles",
                "Work through beginner-level examples in \(t)",
                "Practice applying \(t) concepts to problems",
                "Review mistakes and strengthen weak areas",
                "Test yourself on \(t) without notes"
            ]
        case .build:
            return [
                "Define the requirements and goals for \(t)",
                "Research examples and best practices for \(t)",
                "Plan the structure and design of \(t)",
                "Set up your tools and workspace",
                "Build the core components of \(t) step by step",
                "Test everything and fix any issues",
                "Polish the details and finalize \(t)",
                "Get feedback and make improvements"
            ]
        case .write:
            return [
                "Brainstorm ideas and define your angle on \(t)",
                "Research and gather supporting material",
                "Create a detailed outline for \(t)",
                "Write a strong opening and thesis",
                "Draft the main body with clear arguments",
                "Write a compelling conclusion",
                "Revise for clarity, flow, and grammar",
                "Proofread and finalize \(t)"
            ]
        case .practice:
            return [
                "Assess your current skill level in \(t)",
                "Review the fundamentals before practicing",
                "Start with easy \(t) exercises to warm up",
                "Increase difficulty progressively",
                "Focus on areas where you make the most mistakes",
                "Do a timed practice session for \(t)",
                "Review all errors and redo them correctly"
            ]
        case .prepare:
            return [
                "Gather all study materials for \(t)",
                "Review class notes and key concepts",
                "Create a summary sheet for \(t)",
                "Make flashcards for important terms and ideas",
                "Practice with sample questions about \(t)",
                "Take a timed mock test under real conditions",
                "Review weak areas and do a final pass"
            ]
        case .research:
            return [
                "Define the scope and key questions about \(t)",
                "Find credible sources and references for \(t)",
                "Read and take notes on each source",
                "Identify patterns and key findings in \(t)",
                "Organize your notes into categories",
                "Write a synthesis of what you found about \(t)",
                "Review for gaps and find additional sources if needed"
            ]
        case .organize:
            return [
                "Assess the current state of \(t)",
                "Define your desired outcome for \(t)",
                "Sort and categorize everything related to \(t)",
                "Create a clear system or structure",
                "Execute the organization plan step by step",
                "Review and adjust as needed"
            ]
        case .read:
            return [
                "Skim the table of contents and structure of \(t)",
                "Read the introduction and conclusion first",
                "Deep-read each section of \(t) with notes",
                "Highlight key arguments and evidence",
                "Summarize each section in your own words",
                "Connect the main themes across \(t)",
                "Review your notes for retention"
            ]
        case .fix:
            return [
                "Clearly define the problem with \(t)",
                "Research common causes and solutions",
                "Isolate the specific issue step by step",
                "Attempt the most likely fix for \(t)",
                "Test whether the fix resolved the issue",
                "If not resolved, try alternative solutions",
                "Document what worked for future reference"
            ]
        case .memorize:
            return [
                "List everything you need to memorize about \(t)",
                "Group items into logical categories",
                "Create flashcards or mnemonics for \(t)",
                "Practice with spaced repetition (short intervals)",
                "Test yourself without looking at notes",
                "Review items you got wrong and repeat",
                "Do a final complete recall test on \(t)"
            ]
        case .generic:
            return [
                "Define exactly what you want to achieve with \(t)",
                "Break \(t) into smaller, manageable parts",
                "Research the best approach for each part",
                "Start with the most important piece of \(t)",
                "Complete each section, building momentum",
                "Review your progress and adjust your plan",
                "Finalize and reflect on what you accomplished"
            ]
        }
    }
}

// MARK: - Custom Shapes

struct MountainRange: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let w = rect.width; let h = rect.height
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: w*0.05, y: h*0.6)); p.addLine(to: CGPoint(x: w*0.12, y: h*0.35))
        p.addLine(to: CGPoint(x: w*0.2, y: h*0.55)); p.addLine(to: CGPoint(x: w*0.28, y: h*0.25))
        p.addLine(to: CGPoint(x: w*0.38, y: h*0.5)); p.addLine(to: CGPoint(x: w*0.45, y: h*0.15))
        p.addLine(to: CGPoint(x: w*0.55, y: h*0.45)); p.addLine(to: CGPoint(x: w*0.62, y: h*0.3))
        p.addLine(to: CGPoint(x: w*0.72, y: h*0.5)); p.addLine(to: CGPoint(x: w*0.8, y: h*0.2))
        p.addLine(to: CGPoint(x: w*0.88, y: h*0.45)); p.addLine(to: CGPoint(x: w*0.95, y: h*0.35))
        p.addLine(to: CGPoint(x: w, y: h*0.55)); p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath(); return p
    }
}

struct RollingHills: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let w = rect.width; let h = rect.height
        p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h*0.55))
        p.addQuadCurve(to: CGPoint(x: w*0.2, y: h*0.4), control: CGPoint(x: w*0.1, y: h*0.3))
        p.addQuadCurve(to: CGPoint(x: w*0.4, y: h*0.5), control: CGPoint(x: w*0.3, y: h*0.6))
        p.addQuadCurve(to: CGPoint(x: w*0.6, y: h*0.35), control: CGPoint(x: w*0.5, y: h*0.25))
        p.addQuadCurve(to: CGPoint(x: w*0.8, y: h*0.45), control: CGPoint(x: w*0.7, y: h*0.55))
        p.addQuadCurve(to: CGPoint(x: w, y: h*0.38), control: CGPoint(x: w*0.9, y: h*0.3))
        p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath(); return p
    }
}

struct GrassTextureLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let w = rect.width; let h = rect.height
        for x in stride(from: CGFloat(0), through: w, by: 18) {
            let baseY = h * 0.5
            p.move(to: CGPoint(x: x, y: baseY))
            p.addLine(to: CGPoint(x: x - 3, y: baseY - 8))
            p.move(to: CGPoint(x: x + 6, y: baseY))
            p.addLine(to: CGPoint(x: x + 9, y: baseY - 6))
        }
        return p
    }
}

// MARK: - Visual Effects

struct ConfettiView: View {
    let particles: [ConfettiParticle]; @State private var animate = false
    init(count: Int = 50) {
        let c: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint, .cyan]
        var p: [ConfettiParticle] = []
        for _ in 0..<count {
            p.append(ConfettiParticle(color: c.randomElement()!, xOffset: .random(in: -250...250),
                yOffset: .random(in: 400...800), size: .random(in: 6...14),
                delay: .random(in: 0...0.6), duration: .random(in: 1.8...3.5), rotation: .random(in: 360...1080)))
        }
        self.particles = p
    }
    var body: some View {
        ZStack {
            ForEach(particles) { p in
                RoundedRectangle(cornerRadius: 2).fill(p.color)
                    .frame(width: p.size, height: p.size * 1.6)
                    .rotationEffect(.degrees(animate ? p.rotation : 0))
                    .offset(x: animate ? p.xOffset : 0, y: animate ? p.yOffset : -60)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: p.duration).delay(p.delay), value: animate)
            }
        }.onAppear { animate = true }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct FloatingCloud: View {
    let width: CGFloat; let height: CGFloat; let startX: CGFloat; let y: CGFloat
    let speed: Double; let containerWidth: CGFloat
    @State private var xPos: CGFloat = 0
    var body: some View {
        ZStack {
            Ellipse().fill(Color.white.opacity(0.9)).frame(width: width, height: height)
            Ellipse().fill(Color.white.opacity(0.7)).frame(width: width*0.7, height: height*0.7).offset(x: -width*0.2, y: -height*0.15)
            Ellipse().fill(Color.white.opacity(0.8)).frame(width: width*0.6, height: height*0.6).offset(x: width*0.2, y: -height*0.1)
        }
        .shadow(color: .white.opacity(0.3), radius: 4, y: 2)
        .position(x: xPos, y: y)
        .onAppear { xPos = startX; withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) { xPos = containerWidth + width } }
        .accessibilityHidden(true)
    }
}

struct SparkleView: View {
    @State private var opacity: Double = 0; @State private var scale: CGFloat = 0.5
    let x: CGFloat; let y: CGFloat; let delay: Double
    var body: some View {
        Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(.yellow)
            .opacity(opacity).scaleEffect(scale).position(x: x, y: y)
            .onAppear { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(delay)) { opacity = 0.9; scale = 1.2 } }
            .accessibilityHidden(true)
    }
}

struct PulseRing: View {
    @State private var s: CGFloat = 1.0; @State private var o: Double = 0.6; let color: Color
    var body: some View {
        Circle().stroke(color, lineWidth: 3).scaleEffect(s).opacity(o)
            .onAppear { withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { s = 1.6; o = 0 } }
            .accessibilityHidden(true)
    }
}

struct StreakFlame: View {
    let streak: Int
    @State private var flicker = false
    var body: some View {
        HStack(spacing: 4) {
            Text("🔥").font(.system(size: streak >= 5 ? 28 : 22))
                .scaleEffect(flicker ? 1.15 : 1.0)
                .rotationEffect(.degrees(flicker ? 3 : -3))
            Text("\(streak)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { flicker = true }
        }
        .accessibilityLabel("Focus streak: \(streak) sessions")
    }
}

struct SmokePuff: View {
    @State private var y: CGFloat = 0; @State private var opacity: Double = 0.6
    let startX: CGFloat
    var body: some View {
        Circle().fill(Color.white.opacity(opacity)).frame(width: 8, height: 8)
            .offset(x: startX, y: y)
            .onAppear {
                withAnimation(.easeOut(duration: 3).repeatForever(autoreverses: false)) { y = -30; opacity = 0 }
            }.accessibilityHidden(true)
    }
}

// MARK: - Focus Shield (Unique Anti-Distraction Visual)

struct FocusShieldView: View {
    let progress: Double
    @State private var shieldPulse = false
    @State private var distractionAngles: [Double] = (0..<6).map { _ in Double.random(in: 0...360) }
    @State private var distractionVisible: [Bool] = Array(repeating: false, count: 6)

    let distractions = ["📱", "💬", "🎮", "📺", "🔔", "📧"]

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.25 * progress), Color.blue.opacity(0.15 * progress), .clear],
                        center: .center, startRadius: 80, endRadius: 200
                    )
                )
                .frame(width: 420, height: 420)
                .scaleEffect(shieldPulse ? 1.04 : 1.0)

            Circle()
                .stroke(
                    AngularGradient(colors: [.cyan.opacity(0.6 * progress), .blue.opacity(0.3 * progress),
                                              .purple.opacity(0.4 * progress), .cyan.opacity(0.6 * progress)], center: .center),
                    lineWidth: 3
                )
                .frame(width: 310, height: 310)
                .rotationEffect(.degrees(shieldPulse ? 360 : 0))

            ForEach(0..<6, id: \.self) { i in
                let angle = distractionAngles[i] * .pi / 180
                let radius: CGFloat = distractionVisible[i] ? 180 : 250
                Text(distractions[i])
                    .font(.system(size: 20))
                    .opacity(distractionVisible[i] ? 0.7 : 0)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                    .scaleEffect(distractionVisible[i] ? 0.6 : 1.0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { shieldPulse = true }
            for i in 0..<6 {
                let delay = Double(i) * 1.5 + Double.random(in: 0...1)
                Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        distractionVisible[i] = true
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

// MARK: - Level Progress Bar

struct LevelProgressBar: View {
    @EnvironmentObject var kingdom: KingdomState
    @State private var animatedProgress: Double = 0
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill")
                        .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                    Text("Level \(kingdom.level)").font(.headline).bold().foregroundColor(.primary)
                }
                Spacer()
                Text(kingdom.kingdomTitle).font(.subheadline)
                    .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing)).bold()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * animatedProgress)
                    HStack { Spacer(); Text("\(kingdom.totalXP) XP").font(.system(size: 10, weight: .bold)).foregroundColor(.white).padding(.trailing, 8) }
                }
            }.frame(height: 16)
        }
        .padding()
        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.3)) { animatedProgress = kingdom.xpProgress } }
        .onChange(of: kingdom.totalXP) { withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { animatedProgress = kingdom.xpProgress } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(kingdom.level), \(kingdom.kingdomTitle), \(kingdom.totalXP) experience points")
        .accessibilityValue("\(Int(kingdom.xpProgress * 100)) percent to next level")
    }
}

// MARK: - Kingdom Landscape (Zoned Districts)

struct KingdomView: View {
    @EnvironmentObject var kingdom: KingdomState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraYaw: Double = 0
    @State private var cameraPitch: Double = 0
    @State private var isDraggingCamera = false
    var skyColors: [Color] {
        switch kingdom.level {
        case 1: return [Color(red:0.98,green:0.7,blue:0.5), Color(red:0.55,green:0.75,blue:0.95)]
        case 2: return [Color(red:0.45,green:0.75,blue:0.98), Color(red:0.35,green:0.6,blue:0.9)]
        case 3: return [Color(red:0.4,green:0.7,blue:0.95), Color(red:0.3,green:0.55,blue:0.85)]
        case 4: return [Color(red:0.35,green:0.65,blue:0.95), Color(red:0.25,green:0.5,blue:0.85)]
        case 5: return [Color(red:0.95,green:0.65,blue:0.4), Color(red:0.85,green:0.45,blue:0.55)]
        case 6...7: return [Color(red:0.3,green:0.25,blue:0.55), Color(red:0.15,green:0.15,blue:0.4)]
        default: return [Color(red:0.08,green:0.08,blue:0.25), Color(red:0.15,green:0.1,blue:0.35)]
        }
    }

    struct ZoneLayout {
        let category: ShopCategory; let xRange: ClosedRange<CGFloat>; let yRange: ClosedRange<CGFloat>
    }
    var zones: [ZoneLayout] {[
        ZoneLayout(category: .defense, xRange: 0.02...0.98, yRange: 0.55...0.62),
        ZoneLayout(category: .economy, xRange: 0.05...0.45, yRange: 0.64...0.78),
        ZoneLayout(category: .housing, xRange: 0.55...0.95, yRange: 0.64...0.78),
        ZoneLayout(category: .culture, xRange: 0.25...0.75, yRange: 0.78...0.92),
        ZoneLayout(category: .nature, xRange: 0.10...0.90, yRange: 0.58...0.95),
    ]}

    func zonePosition(zone: ZoneLayout, index: Int, total: Int, w: CGFloat, h: CGFloat, jx: CGFloat, jy: CGFloat) -> CGPoint {
        let cols = max(1, min(4, total))
        let col = index % cols; let row = index / cols
        let xSpan = zone.xRange.upperBound - zone.xRange.lowerBound
        let ySpan = zone.yRange.upperBound - zone.yRange.lowerBound
        let cellW = xSpan / CGFloat(cols)
        let x = (zone.xRange.lowerBound + cellW * (CGFloat(col) + 0.5) + jx) * w
        let y = (zone.yRange.lowerBound + CGFloat(row) * min(ySpan * 0.5, 0.08) + jy) * h
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            ZStack {
                LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
                    .animation(.easeInOut(duration: 1.5), value: kingdom.level)

                if kingdom.level >= 6 && !reduceMotion {
                    ForEach(0..<8, id: \.self) { i in SparkleView(x: CGFloat.random(in: 0...w), y: CGFloat.random(in: 0...(h*0.35)), delay: Double(i)*0.3) }
                }

                if kingdom.allTasksComplete {
                    LinearGradient(colors: [Color.cyan.opacity(0.18), Color.purple.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    Text("🎉 3D Celebration Mode Unlocked")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.22)))
                        .position(x: w * 0.5, y: h * 0.08)
                }

                if !reduceMotion {
                    FloatingCloud(width: 80, height: 30, startX: -80, y: h*0.1, speed: 28, containerWidth: w)
                    FloatingCloud(width: 110, height: 40, startX: -180, y: h*0.18, speed: 38, containerWidth: w)
                }

                MountainRange()
                    .fill(LinearGradient(colors: [Color(red:0.35,green:0.45,blue:0.55).opacity(0.5), Color(red:0.25,green:0.35,blue:0.45).opacity(0.3)], startPoint: .top, endPoint: .bottom))
                    .frame(height: h*0.45).offset(y: h*0.18)

                RollingHills()
                    .fill(LinearGradient(colors: [Color(red:0.28,green:0.65,blue:0.3), Color(red:0.18,green:0.52,blue:0.22)], startPoint: .top, endPoint: .bottom))
                    .frame(height: h*0.5).offset(y: h*0.28)

                VStack { Spacer()
                    Rectangle().fill(LinearGradient(colors: [Color(red:0.2,green:0.55,blue:0.2), Color(red:0.13,green:0.42,blue:0.13)], startPoint: .top, endPoint: .bottom)).frame(height: h*0.42)
                }

                ZoneRoadShape().stroke(Color.yellow.opacity(0.25), style: StrokeStyle(lineWidth: 4, dash: [8,6]))
                    .frame(width: w*0.7, height: h*0.28).position(x: w*0.5, y: h*0.76)

                ForEach([ShopCategory.defense, .economy, .housing, .culture], id: \.rawValue) { cat in
                    let zone = zones.first(where: { $0.category == cat })!
                    let catBuildings = kingdom.buildingsInZone(cat)
                    if !catBuildings.isEmpty {
                        let labelX = (zone.xRange.lowerBound + zone.xRange.upperBound) / 2 * w
                        let labelY = zone.yRange.lowerBound * h - 6
                        Text(cat.name).font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(cat.color.opacity(0.5)))
                            .position(x: labelX, y: labelY)
                    }
                }

                ForEach(ShopCategory.allCases, id: \.rawValue) { cat in
                    let zone = zones.first(where: { $0.category == cat })!
                    let catBuildings = kingdom.buildingsInZone(cat)
                    ForEach(Array(catBuildings.enumerated()), id: \.element.id) { idx, building in
                        let pos = zonePosition(zone: zone, index: idx, total: catBuildings.count, w: w, h: h, jx: building.jitterX, jy: building.jitterY)
                        let isLarge = [BuildingType.castle,.palace,.fortress,.bank,.academy,.university].contains(building.type)
                        let sz: CGFloat = isLarge ? 44 : 34

                        Button(action: { kingdom.selectedBuilding = building }) {
                            VStack(spacing: 0) {
                                ZStack {
                                    Ellipse().fill(Color.black.opacity(0.2)).frame(width: 36, height: 10).offset(y: sz * 0.5)
                                    Mini3DBuildingView(type: building.type, size: sz)
                                        .shadow(color: .black.opacity(0.35), radius: 3, y: 3)
                                }
                                Text(building.type.name)
                                    .font(.system(size: 8, weight: .bold, design: .rounded)).foregroundColor(.white)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Capsule().fill(cat.color.opacity(0.7)))
                            }
                        }
                        .scaleEffect(building.scale).position(pos)
                        .rotation3DEffect(.degrees(-12), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                        .accessibilityLabel("\(building.type.name) in \(cat.name) zone")
                        .accessibilityHint("Tap to explore this building's interior")
                    }
                }

                if kingdom.population > 0 {
                    let pop = min(kingdom.population, 12)
                    ForEach(0..<pop, id: \.self) { i in
                        Text(["🧑","👩","🧒","👴","👵"][i % 5]).font(.system(size: 14))
                            .position(x: w * (0.25 + CGFloat(i % 4) * 0.18), y: h * (0.72 + CGFloat(i / 4) * 0.055))
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                            .accessibilityHidden(true)
                    }
                }

                if kingdom.buildings.isEmpty {
                    VStack(spacing: 14) {
                        ZStack {
                            PulseRing(color: .white.opacity(0.5)).frame(width: 120, height: 120)
                            Text("🏗️").font(.system(size: 72))
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 4)
                                .rotation3DEffect(.degrees(-8), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                        }
                        Text("Your Kingdom Awaits").font(.system(.title2, design: .rounded)).bold().foregroundColor(.white).shadow(color: .black.opacity(0.3), radius: 4)
                        Text("Earn coins → Buy buildings in the Shop!").font(.subheadline).foregroundColor(.white.opacity(0.9))
                    }.position(x: w*0.5, y: h*0.72)
                }

                VStack {
                    HStack {
                        Text("Tap a building to explore inside")
                            .font(.system(size: 10, design: .rounded)).foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.ultraThinMaterial).clipShape(Capsule()).padding(10)
                        Spacer()
                        Text(kingdom.kingdomTitle)
                            .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.ultraThinMaterial).clipShape(Capsule()).padding(10)
                    }
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(
                LinearGradient(colors: [.white.opacity(0.5),.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            .rotation3DEffect(.degrees(2 + cameraPitch), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
            .rotation3DEffect(.degrees(cameraYaw), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        guard !reduceMotion else { return }
                        isDraggingCamera = true
                        cameraYaw = Double(value.translation.width / 18)
                        cameraPitch = Double(-value.translation.height / 24)
                    }
                    .onEnded { _ in
                        isDraggingCamera = false
                        settleCameraForCurrentState(animated: true)
                    }
            )
            .onAppear { settleCameraForCurrentState(animated: false) }
            .onChange(of: kingdom.allTasksComplete) { _ in
                guard !isDraggingCamera else { return }
                settleCameraForCurrentState(animated: true)
            }
            .onChange(of: reduceMotion) { _ in
                settleCameraForCurrentState(animated: true)
            }
        }
    }

    private func settleCameraForCurrentState(animated: Bool) {
        let targetYaw = (kingdom.allTasksComplete && !reduceMotion) ? 3.5 : 0
        let targetPitch = (kingdom.allTasksComplete && !reduceMotion) ? -1.5 : 0
        let apply = {
            cameraYaw = targetYaw
            cameraPitch = targetPitch
        }
        if animated { withAnimation(.spring(response: 0.6, dampingFraction: 0.8), apply) }
        else { apply() }
    }
}

struct ZoneRoadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let w = rect.width; let h = rect.height
        p.move(to: CGPoint(x: w*0.5, y: 0))
        p.addLine(to: CGPoint(x: w*0.5, y: h))
        p.move(to: CGPoint(x: 0, y: h*0.4))
        p.addLine(to: CGPoint(x: w, y: h*0.4))
        p.move(to: CGPoint(x: w*0.2, y: h*0.1))
        p.addQuadCurve(to: CGPoint(x: w*0.8, y: h*0.1), control: CGPoint(x: w*0.5, y: h*0.05))
        return p
    }
}

// MARK: - 3D Building Visual Components

struct Mini3DBuildingView: View {
    let type: BuildingType
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08)
                .fill(sideColor)
                .frame(width: size * 0.72, height: size * 0.5)
                .offset(x: size * 0.08, y: size * 0.07)

            RoundedRectangle(cornerRadius: size * 0.1)
                .fill(frontColor)
                .frame(width: size * 0.72, height: size * 0.52)
                .overlay(
                    VStack(spacing: size * 0.06) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(windowColor)
                            .frame(width: size * 0.45, height: size * 0.09)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(windowColor.opacity(0.9))
                            .frame(width: size * 0.38, height: size * 0.09)
                        if type.category != .defense {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(doorColor)
                                .frame(width: size * 0.14, height: size * 0.18)
                                .offset(y: size * 0.04)
                        }
                    }
                    .padding(.top, size * 0.06)
                )

            TriangleRoof()
                .fill(roofColor)
                .frame(width: size * 0.82, height: size * 0.32)
                .offset(y: -size * 0.35)

            if type == .watchtower {
                Rectangle().fill(roofColor).frame(width: size * 0.08, height: size * 0.45).offset(y: -size * 0.1)
                Rectangle().fill(frontColor).frame(width: size * 0.32, height: size * 0.12).offset(y: -size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(12), axis: (x: 1, y: -1, z: 0), perspective: 0.5)
    }

    private var frontColor: Color { type.category.color.opacity(0.95) }
    private var sideColor: Color { type.category.color.opacity(0.75) }
    private var roofColor: Color { type.category == .culture ? Color.brown : Color.gray.opacity(0.8) }
    private var windowColor: Color { Color.white.opacity(0.8) }
    private var doorColor: Color { Color.black.opacity(0.2) }
}

struct TriangleRoof: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct InteriorScene3D: View {
    let type: BuildingType
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color.black.opacity(0.12), Color.clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 260, height: 150)
                .offset(y: 20)

            VStack(spacing: 0) {
                Rectangle().fill(wallColor).frame(height: 95)
                Rectangle().fill(floorColor).frame(height: 70)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .frame(width: 280, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .rotation3DEffect(.degrees(12), axis: (x: 1, y: 0, z: 0), perspective: 0.45)

            HStack(spacing: 24) {
                if type.category == .housing || type.category == .economy {
                    RoundedRectangle(cornerRadius: 8).fill(Color.brown.opacity(0.7)).frame(width: 64, height: 24)
                }
                if type.category == .culture {
                    RoundedRectangle(cornerRadius: 4).fill(Color.brown.opacity(0.8)).frame(width: 78, height: 42)
                        .overlay(Rectangle().fill(Color.white.opacity(0.8)).frame(height: 2).offset(y: -8))
                }
                if type.category == .defense {
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.7)).frame(width: 58, height: 52)
                }
            }
            .offset(y: 24)
        }
    }

    private var wallColor: Color { type.category.color.opacity(0.18) }
    private var floorColor: Color { type.category == .culture ? Color.brown.opacity(0.55) : Color.gray.opacity(0.45) }
}

// MARK: - Building Interior (Tap to Enter)

struct BuildingInteriorSheet: View {
    @EnvironmentObject var kingdom: KingdomState
    let building: KingdomBuilding
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    InteriorVisual(type: building.type)
                    BuildingInfoCard(type: building.type, buildingsOfType: kingdom.buildingsOfType(building.type))
                    BuildingStatsCard(type: building.type, kingdom: kingdom)
                    if building.type.category == .culture { KnowledgeSection(knowledge: kingdom.knowledgeMap) }
                    if building.type.category == .economy { EconomySection(income: kingdom.economyIncome) }
                    if building.type.category == .defense { DefenseSection(shield: kingdom.streakShield, streak: kingdom.focusStreak) }
                    RecentActivitySection(history: Array(kingdom.taskHistory.suffix(5).reversed()))
                }.padding(18)
            }
            .background(LinearGradient(colors: [Color(.systemBackground), building.type.category.color.opacity(0.05)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Inside: \(building.type.name)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { dismiss() } } }
            .onAppear {
                AccessibilityAudio.shared.announceBuilding(building: building.type.name, category: building.type.category.name, benefit: building.type.benefit)
            }
        }
    }
}

struct InteriorVisual: View {
    let type: BuildingType
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [type.category.color.opacity(0.15), type.category.color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .frame(height: 200)

            RoundedRectangle(cornerRadius: 16).stroke(type.category.color.opacity(0.2), lineWidth: 2)
                .frame(width: 280, height: 170)
                .overlay(
                    VStack(spacing: 0) {
                        Rectangle().fill(interiorWallColor).frame(height: 100)
                        Rectangle().fill(interiorFloorColor).frame(height: 70)
                    }.clipShape(RoundedRectangle(cornerRadius: 14)).padding(2)
                )

            VStack(spacing: 8) {
                ImmersiveBuildingCard(type: type)
                Text(type.name).font(.system(.title3, design: .rounded)).bold().foregroundColor(.primary)
            }
        }
    }
    var interiorWallColor: Color {
        switch type.category {
        case .housing: return Color(red: 0.95, green: 0.92, blue: 0.85)
        case .economy: return Color(red: 0.95, green: 0.93, blue: 0.8)
        case .culture: return Color(red: 0.9, green: 0.88, blue: 0.95)
        case .defense: return Color(red: 0.88, green: 0.88, blue: 0.9)
        case .nature: return Color(red: 0.85, green: 0.95, blue: 0.85)
        }
    }
    var interiorFloorColor: Color {
        switch type.category {
        case .housing: return Color(red: 0.7, green: 0.55, blue: 0.4)
        case .economy: return Color(red: 0.85, green: 0.8, blue: 0.7)
        case .culture: return Color(red: 0.6, green: 0.5, blue: 0.65)
        case .defense: return Color(red: 0.6, green: 0.6, blue: 0.65)
        case .nature: return Color(red: 0.4, green: 0.7, blue: 0.4)
        }
    }
}

struct ImmersiveBuildingCard: View {
    let type: BuildingType

    var body: some View {
#if os(visionOS) && canImport(RealityKit)
        RealityView { content, attachments in
            let root = Entity()

            let floorMesh = MeshResource.generatePlane(width: 0.36, depth: 0.24)
            let floorMaterial = SimpleMaterial(color: UIColor(type.category.color.opacity(0.16)), isMetallic: false)
            let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
            floor.position = [0, -0.08, 0]
            floor.transform.rotation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

            let bodyMesh = MeshResource.generateBox(size: [0.17, 0.1, 0.12], cornerRadius: 0.01)
            let bodyMaterial = SimpleMaterial(color: UIColor(type.category.color.opacity(0.92)), isMetallic: false)
            let body = ModelEntity(mesh: bodyMesh, materials: [bodyMaterial])
            body.position = [0, -0.02, 0]

            let roofMesh = MeshResource.generateBox(size: [0.19, 0.03, 0.14], cornerRadius: 0.008)
            let roofMaterial = SimpleMaterial(color: .darkGray, roughness: 0.35, isMetallic: false)
            let roof = ModelEntity(mesh: roofMesh, materials: [roofMaterial])
            roof.position = [0, 0.05, 0]

            root.addChild(floor)
            root.addChild(body)
            root.addChild(roof)

            if let info = attachments.entity(for: "label") {
                info.position = [0, 0.12, 0.07]
                root.addChild(info)
            }

            content.add(root)
        } attachments: {
            Attachment(id: "label") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.name).font(.caption).bold()
                    Text(type.benefit).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                .padding(6)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: 290, height: 170)
#else
        InteriorScene3D(type: type)
#endif
    }
}

struct BuildingInfoCard: View {
    let type: BuildingType; let buildingsOfType: Int
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: type.category.icon).foregroundColor(type.category.color)
                Text(type.category.name + " District").font(.system(.headline, design: .rounded))
                Spacer()
                Text("Owned: \(buildingsOfType)").font(.subheadline).foregroundColor(.secondary)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Benefit").font(.caption).foregroundColor(.secondary)
                    Text(type.benefit).font(.system(.body, design: .rounded)).bold().foregroundColor(type.category.color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Value").font(.caption).foregroundColor(.secondary)
                    Text("💰 \(type.cost) coins").font(.system(.body, design: .rounded)).foregroundColor(.orange)
                }
            }
        }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

struct BuildingStatsCard: View {
    let type: BuildingType; let kingdom: KingdomState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kingdom Impact").font(.system(.headline, design: .rounded))
            HStack(spacing: 0) {
                StatPill(emoji: "👥", label: "Pop", value: kingdom.population, color: .blue)
                StatPill(emoji: "💵", label: "Income", value: kingdom.economyIncome, color: .green)
                StatPill(emoji: "📖", label: "XP+", value: kingdom.xpBoostPercent, color: .purple)
                StatPill(emoji: "🛡️", label: "Shield", value: kingdom.streakShield, color: .red)
                StatPill(emoji: "🌸", label: "Beauty", value: kingdom.beautyScore, color: .pink)
            }
        }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

struct StatPill: View {
    let emoji: String; let label: String; let value: Int; let color: Color
    var body: some View {
        VStack(spacing: 2) { Text(emoji).font(.system(size: 14)); Text("\(value)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(color); Text(label).font(.system(size: 8)).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
    }
}

struct KnowledgeSection: View {
    let knowledge: [KnowledgeEntry]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "brain.head.profile").foregroundColor(.purple); Text("Knowledge Map").font(.system(.headline, design: .rounded)); Spacer() }
            if knowledge.isEmpty {
                Text("Complete tasks to build your knowledge library").font(.subheadline).foregroundColor(.secondary).padding(.vertical, 8)
            } else {
                ForEach(knowledge.prefix(6)) { k in
                    HStack(spacing: 12) {
                        Circle().fill(k.masteryColor).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.topic).font(.system(.subheadline, design: .rounded)).bold()
                            Text("\(k.masteryLabel) · \(k.tasksCompleted) sessions").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Lv.\(k.masteryLevel)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(k.masteryColor)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(k.masteryColor.opacity(0.12)).clipShape(Capsule())
                    }
                }
            }
        }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

struct EconomySection: View {
    let income: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "chart.line.uptrend.xyaxis").foregroundColor(.green); Text("Economy Report").font(.system(.headline, design: .rounded)); Spacer() }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(income > 0 ? "Ready to collect (one-time)" : "All collected").font(.caption).foregroundColor(.secondary)
                    Text(income > 0 ? "+\(income) coins" : "Each shop pays once").font(.system(.title3, design: .rounded)).bold().foregroundColor(income > 0 ? .green : .secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status").font(.caption).foregroundColor(.secondary)
                    Text(income > 0 ? "Collect in Shop" : "Fully collected")
                        .font(.subheadline).bold().foregroundColor(income > 0 ? .green : .secondary)
                }
            }
        }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

struct DefenseSection: View {
    let shield: Int; let streak: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "shield.checkered").foregroundColor(.red); Text("Defense Report").font(.system(.headline, design: .rounded)); Spacer() }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Streak Shield Level").font(.caption).foregroundColor(.secondary)
                    Text("\(shield)").font(.system(.title3, design: .rounded)).bold().foregroundColor(.red)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Current Streak").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 4) { Text("🔥"); Text("\(streak)").font(.system(.title3, design: .rounded)).bold().foregroundColor(.orange) }
                }
            }
        }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

struct RecentActivitySection: View {
    let history: [TaskHistoryEntry]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "clock.arrow.circlepath").foregroundColor(.blue); Text("Recent Activity").font(.system(.headline, design: .rounded)); Spacer() }
            if history.isEmpty {
                Text("No completed tasks yet").font(.subheadline).foregroundColor(.secondary)
            } else {
                ForEach(history.prefix(5)) { entry in
                    HStack(spacing: 10) {
                        Circle().fill(entry.wasGroupComplete ? Color.green : Color.blue).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.system(.caption, design: .rounded)).foregroundColor(.primary).lineLimit(1)
                            Text(entry.completedAt, style: .relative).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("+\(entry.coinsEarned)💰").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.orange)
                    }
                }
            }
        }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - Swift Charts Visualizations

struct DailyActivityData: Identifiable {
    let id = UUID(); let day: String; let count: Int; let coins: Int
}

struct DailyActivityChart: View {
    let history: [TaskHistoryEntry]
    private var chartData: [DailyActivityData] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return (-6...0).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: Date())!
            let dayTasks = history.filter { cal.isDate($0.completedAt, inSameDayAs: date) }
            return DailyActivityData(day: formatter.string(from: date), count: dayTasks.count,
                                     coins: dayTasks.reduce(0) { $0 + $1.coinsEarned })
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundColor(.blue)
                Text("7-Day Activity").font(.system(.headline, design: .rounded))
                Spacer()
            }
            Chart(chartData) { item in
                BarMark(x: .value("Day", item.day), y: .value("Tasks", item.count))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .bottom, endPoint: .top)
                    )
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        if item.count > 0 {
                            Text("\(item.count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                        }
                    }
            }
            .chartYAxis { AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                AxisValueLabel().font(.system(size: 10, design: .rounded))
            } }
            .chartXAxis { AxisMarks { value in
                AxisValueLabel().font(.system(size: 11, weight: .medium, design: .rounded))
            } }
            .frame(height: 160)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Weekly activity chart showing tasks completed each day")
        }
        .padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

struct KnowledgeMasteryChart: View {
    let knowledge: [KnowledgeEntry]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile").foregroundColor(.purple)
                Text("Mastery Overview").font(.system(.headline, design: .rounded))
                Spacer()
            }
            Chart(knowledge.prefix(8)) { k in
                BarMark(x: .value("Level", k.masteryLevel), y: .value("Topic", k.topic))
                    .foregroundStyle(
                        LinearGradient(colors: [k.masteryColor, k.masteryColor.opacity(0.5)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(6)
                    .annotation(position: .trailing) {
                        Text(k.masteryLabel)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(k.masteryColor)
                    }
            }
            .chartXScale(domain: 0...4)
            .chartXAxis { AxisMarks(values: [0, 1, 2, 3, 4]) { value in
                AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                AxisValueLabel().font(.system(size: 10, design: .rounded))
            } }
            .chartYAxis { AxisMarks { AxisValueLabel().font(.system(size: 11, weight: .medium, design: .rounded)) } }
            .frame(height: CGFloat(max(knowledge.prefix(8).count, 1)) * 40 + 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Knowledge mastery chart showing progress across topics")
        }
        .padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - Activity & Knowledge Hub

struct ActivityHubSheet: View {
    @EnvironmentObject var kingdom: KingdomState; @Binding var show: Bool
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    ActivitySummaryCard(total: kingdom.taskHistory.count, today: kingdom.todayTaskCount,
                                        coins: kingdom.totalCoinsEarned, streak: kingdom.focusStreak)

                    DailyActivityChart(history: kingdom.taskHistory)

                    if !kingdom.knowledgeMap.isEmpty {
                        KnowledgeMasteryChart(knowledge: kingdom.knowledgeMap)
                        KnowledgeSection(knowledge: kingdom.knowledgeMap)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("All Completed Tasks").font(.system(.headline, design: .rounded))
                        if kingdom.taskHistory.isEmpty {
                            Text("Complete focus sessions to build your history")
                                .font(.subheadline).foregroundColor(.secondary).padding(.vertical, 16)
                        } else {
                            ForEach(kingdom.taskHistory.reversed()) { entry in
                                HStack(spacing: 12) {
                                    VStack(spacing: 2) {
                                        Text(entry.wasGroupComplete ? "⭐" : "✅").font(.system(size: 20))
                                    }.frame(width: 32)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title).font(.system(.subheadline, design: .rounded)).foregroundColor(.primary)
                                        HStack(spacing: 8) {
                                            Text(entry.topic).font(.caption).foregroundColor(.purple)
                                            Text("·").foregroundColor(.secondary)
                                            Text(entry.completedAt, style: .relative).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text("+\(entry.coinsEarned)").font(.system(.caption, design: .rounded)).bold().foregroundColor(.orange)
                                }.padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                }.padding(18)
            }
            .background(LinearGradient(colors: [Color(.systemBackground), Color.blue.opacity(0.03)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Activity Hub").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { show = false } } }
            .onAppear {
                AccessibilityAudio.shared.announceScreen("Activity Hub", detail: "\(kingdom.taskHistory.count) total tasks completed. \(kingdom.knowledgeMap.count) topics studied. \(kingdom.focusStreak) day streak.")
            }
        }
    }
}

struct ActivitySummaryCard: View {
    let total: Int; let today: Int; let coins: Int; let streak: Int
    var body: some View {
        VStack(spacing: 16) {
            Text("📊").font(.system(size: 48)).accessibilityHidden(true)
            HStack(spacing: 0) {
                VStack(spacing: 4) { Text("\(total)").font(.system(.title2, design: .rounded)).bold(); Text("Total").font(.caption2).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
                VStack(spacing: 4) { Text("\(today)").font(.system(.title2, design: .rounded)).bold().foregroundColor(.green); Text("Today").font(.caption2).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
                VStack(spacing: 4) { Text("\(coins)💰").font(.system(.title2, design: .rounded)).bold().foregroundColor(.orange); Text("Earned").font(.caption2).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
                VStack(spacing: 4) { Text("🔥\(streak)").font(.system(.title2, design: .rounded)).bold().foregroundColor(.red); Text("Streak").font(.caption2).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
            }
        }.padding(20).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(total) total tasks, \(today) today, \(coins) coins earned, \(streak) day streak")
    }
}

// MARK: - Level Up Announcement

struct LevelUpBanner: View {
    let oldLevel: Int; let newLevel: Int; let title: String; let onDismiss: () -> Void
    @State private var appear = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { onDismiss() }
            VStack(spacing: 20) {
                Text("⬆️").font(.system(size: 60)).scaleEffect(appear ? 1.2 : 0.5)
                Text("KINGDOM UPGRADED!").font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.yellow)
                    .shadow(color: .orange, radius: 8)
                Text("\(title)").font(.system(.title, design: .rounded)).bold().foregroundColor(.white)
                Text("Level \(oldLevel) → Level \(newLevel)").font(.headline).foregroundColor(.white.opacity(0.8))
                Button(action: onDismiss) {
                    Text("Continue Building").font(.system(.headline, design: .rounded)).foregroundColor(.white)
                        .padding(.horizontal, 32).padding(.vertical, 14)
                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 10)
            }
            .padding(30).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: .purple.opacity(0.4), radius: 20).padding(40)
            .scaleEffect(appear ? 1 : 0.8).opacity(appear ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appear = true } }
    }
}

// MARK: - Stats Header

struct HeaderStats: View {
    @EnvironmentObject var kingdom: KingdomState
    var body: some View {
        HStack(spacing: 10) {
            StatCard(icon: "timer", value: "\(kingdom.totalFocusMinutes)", label: "Minutes", gradient: [.blue, .cyan])
            StatCard(icon: "building.2.fill", value: "\(kingdom.buildingCount)", label: "Buildings", gradient: [.purple, .pink])
            StatCard(icon: "dollarsign.circle.fill", value: "\(kingdom.coins)", label: "Coins", gradient: [.orange, .yellow])
            if kingdom.focusStreak > 0 {
                VStack(spacing: 4) {
                    StreakFlame(streak: kingdom.focusStreak)
                    Text("Streak").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: 70).padding(.vertical, 10)
                .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .orange.opacity(0.2), radius: 8, y: 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Focus streak: \(kingdom.focusStreak) sessions")
            }
        }
    }
}

struct StatCard: View {
    let icon: String; let value: String; let label: String; let gradient: [Color]
    @State private var appeared = false
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3)
                .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(appeared ? 1 : 0.5)
            Text(value).font(.system(.title3, design: .rounded)).bold().foregroundColor(.primary).contentTransition(.numericText())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.3), lineWidth: 1))
        .shadow(color: gradient[0].opacity(0.15), radius: 8, y: 4)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) { appeared = true } }
        .accessibilityElement(children: .combine).accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Task Views

struct ActiveTasksList: View {
    @EnvironmentObject var kingdom: KingdomState
    @Binding var selectedTask: TaskPiece?; @Binding var showTimer: Bool
    @State private var showAddTask = false; @State private var newTaskTitle = ""
    var activeTasks: [TaskPiece] { kingdom.tasks.filter { !$0.completed } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Active Tasks").font(.system(.title3, design: .rounded)).bold().foregroundColor(.primary)
                Spacer()
                Button(action: { showAddTask = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 14))
                        Text("Add").font(.system(.subheadline, design: .rounded)).bold()
                    }.foregroundColor(.purple).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.purple.opacity(0.1)).clipShape(Capsule())
                }
                Text("\(activeTasks.count) left").font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
            if activeTasks.isEmpty { EmptyTasksView() }
            else {
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { i, task in
                    TaskRowView(task: task, index: i) { selectedTask = task; showTimer = true }
                }
            }
        }
        .alert("Add a Task", isPresented: $showAddTask) {
            TextField("What do you need to do?", text: $newTaskTitle)
            Button("Add") {
                if !newTaskTitle.isEmpty {
                    let g = UUID()
                    kingdom.addTasks([TaskPiece(title: newTaskTitle, minutes: 25, groupID: g)], groupID: g, topic: TaskAI.extractTopic(from: newTaskTitle))
                    newTaskTitle = ""
                }
            }
            Button("Cancel", role: .cancel) { newTaskTitle = "" }
        } message: { Text("Manually add a task to your list. It earns coins just like AI tasks.") }
    }
}

struct EmptyTasksView: View {
    @State private var bounce = false
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54))
                .foregroundStyle(LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom))
                .scaleEffect(bounce ? 1.05 : 1.0)
                .onAppear { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { bounce = true } }
            Text("All tasks complete!").font(.system(.headline, design: .rounded)).foregroundColor(.primary)
            Text("Add more tasks to keep building").font(.subheadline).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

struct TaskRowView: View {
    @EnvironmentObject var kingdom: KingdomState
    let task: TaskPiece; let index: Int; let onFocus: () -> Void
    @State private var appeared = false; @State private var isEditing = false; @State private var editText = ""
    let grads: [[Color]] = [[.blue,.cyan],[.purple,.pink],[.pink,.orange],[.orange,.yellow],[.green,.mint],[.cyan,.blue],[.indigo,.purple],[.mint,.green]]
    var g: [Color] { grads[abs(task.title.hashValue) % grads.count] }
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: g, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 36, height: 36)
                Image(systemName: "brain.head.profile").font(.system(size: 14)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.system(.body, design: .rounded)).foregroundColor(.primary).lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill").font(.system(size: 10))
                    Text("\(task.minutes) min").font(.caption)
                }.foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { editText = task.title; isEditing = true }) {
                Image(systemName: "pencil").font(.system(size: 14)).foregroundColor(.secondary)
                    .padding(8).background(Circle().fill(Color.gray.opacity(0.1)))
            }
            Button(action: onFocus) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Focus").font(.system(.subheadline, design: .rounded)).bold()
                }.foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10)
                .background(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .green.opacity(0.3), radius: 6, y: 3)
            }
        }
        .padding(14).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
        .scaleEffect(appeared ? 1 : 0.95).opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06)) { appeared = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task: \(task.title), \(task.minutes) minutes")
        .accessibilityHint("Double tap to start focus timer. Swipe right for more actions.")
        .alert("Rename Task", isPresented: $isEditing) {
            TextField("Task name", text: $editText)
            Button("Save") { if !editText.isEmpty { kingdom.renameTask(id: task.id, newTitle: editText) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Edit the task name to match what you want to focus on.") }
    }
}

struct QuizAvailableBanner: View {
    let action: () -> Void; @State private var glow = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack { Circle().fill(Color.yellow.opacity(glow ? 0.3 : 0.1)).frame(width: 50, height: 50); Text("🎓").font(.system(size: 28)) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quiz Ready!").font(.system(.headline, design: .rounded)).foregroundColor(.primary)
                    Text("Prove your knowledge to earn coins").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right.circle.fill").font(.title3)
                    .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom))
            }.padding(16)
            .background(LinearGradient(colors: [Color.yellow.opacity(0.15), Color.orange.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.orange.opacity(0.4), lineWidth: 1.5))
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { glow = true } }
    }
}

struct ActionButtons: View {
    @EnvironmentObject var kingdom: KingdomState
    @Binding var showTaskInput: Bool; @Binding var showShop: Bool
    var body: some View {
        VStack(spacing: 14) {
            Button(action: { showTaskInput = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile").font(.title3)
                    Text("Add New Task (AI)").font(.system(.headline, design: .rounded))
                }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .purple.opacity(0.35), radius: 12, y: 6)
            }
            .accessibilityLabel("Add new task with AI breakdown")
            .accessibilityHint("Opens AI-powered task analysis to break any learning goal into focused steps")
            Button(action: { showShop = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "storefront.fill").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kingdom Shop").font(.system(.headline, design: .rounded))
                        if kingdom.coins > 0 {
                            Text("💰 \(kingdom.coins) coins to spend").font(.caption)
                        }
                    }
                }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .orange.opacity(0.3), radius: 12, y: 6)
            }
            .accessibilityLabel("Kingdom shop, \(kingdom.coins) coins available")
            .accessibilityHint("Browse and purchase buildings for your kingdom")
        }
    }
}

// MARK: - Task Input Sheet

struct TaskInputSheet: View {
    @EnvironmentObject var kingdom: KingdomState; @Binding var show: Bool
    @State private var taskInput = ""; @State private var isAnalyzing = false
    @State private var breakdown: [String] = []; @State private var showResults = false
    @State private var analysisProgress: Double = 0
    let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .cyan, .indigo, .mint]
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color.purple.opacity(0.05)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        if !showResults { InputView(taskInput: $taskInput, isAnalyzing: $isAnalyzing, analysisProgress: $analysisProgress, onAnalyze: analyzeTask) }
                        else { ResultsView(breakdown: breakdown, colors: colors, originalInput: taskInput, onAddAll: addAllTasks) }
                    }.padding(20)
                }
            }.navigationTitle("AI Task Breakdown").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { show = false } } }
        }
    }
    func analyzeTask() {
        AccessibilityAudio.shared.speak("Analyzing your task. Please wait.")
        isAnalyzing = true; analysisProgress = 0
        for i in 1...20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.07) {
                withAnimation { analysisProgress = Double(i) / 20.0 }
                if i == 20 {
                    breakdown = TaskAI.breakdownTask(taskInput); isAnalyzing = false
                    let topic = TaskAI.extractTopic(from: taskInput)
                    AccessibilityAudio.shared.announceBreakdown(topic: topic, count: breakdown.count, steps: breakdown)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showResults = true }
                }
            }
        }
    }
    func addAllTasks() {
        let g = UUID(); let topic = TaskAI.extractTopic(from: taskInput)
        kingdom.addTasks(breakdown.map { TaskPiece(title: $0, minutes: 25, groupID: g) }, groupID: g, topic: topic); show = false
    }
}

struct InputView: View {
    @Binding var taskInput: String; @Binding var isAnalyzing: Bool; @Binding var analysisProgress: Double; let onAnalyze: () -> Void
    @ObservedObject private var audio = AccessibilityAudio.shared
    let suggestions = ["Study for biology exam", "Learn statistics", "Write research paper", "Learn ML math",
                        "Build a mobile app", "Prepare presentation", "Practice guitar", "Learn Spanish",
                        "Study chemistry", "Research history"]
    @State private var analyzePhase = 0
    @State private var micPulse = false
    private let analyzeMessages = ["Scanning your task...", "Identifying key learning areas...", "Building your personalized plan...", "Finalizing steps..."]

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle().fill(RadialGradient(colors: [.purple.opacity(0.15), .clear], center: .center, startRadius: 0, endRadius: 70)).frame(width: 140, height: 140)
                Image(systemName: "brain.head.profile").font(.system(size: 64))
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            }.accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("What do you want to focus on?").font(.system(.title2, design: .rounded)).bold().foregroundColor(.primary)
                Text("Type any learning goal clearly (example: \"Learn SwiftUI layout\") and AI will generate a step-by-step plan. You can still add your own custom tasks anytime.").font(.subheadline).foregroundColor(.secondary)
            }.multilineTextAlignment(.center)
            HStack(spacing: 12) {
                TextField("e.g., Learn quantum physics, Study for SAT...", text: $taskInput)
                    .font(.system(.body, design: .rounded)).foregroundColor(.primary).textFieldStyle(.plain)
                    .padding(16).background(Color(.systemBackground)).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(colors: [.purple.opacity(0.4), .blue.opacity(0.3)], startPoint: .leading, endPoint: .trailing), lineWidth: 2))
                Button(action: toggleVoiceInput) {
                    ZStack {
                        Circle()
                            .fill(audio.isListening
                                  ? LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                            .frame(width: 52, height: 52)
                            .scaleEffect(micPulse ? 1.15 : 1.0)
                            .shadow(color: audio.isListening ? .red.opacity(0.4) : .purple.opacity(0.3), radius: 8, y: 4)
                        Image(systemName: audio.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                    }
                }
                .accessibilityLabel(audio.isListening ? "Stop listening" : "Speak your task")
                .accessibilityHint(audio.isListening ? "Tap to stop voice input" : "Tap to speak what you want to learn")
            }
            if audio.isListening {
                HStack(spacing: 10) {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                        .scaleEffect(micPulse ? 1.3 : 0.8).opacity(micPulse ? 1 : 0.5)
                    Text("Listening... speak your task now")
                        .font(.system(.subheadline, design: .rounded)).foregroundColor(.red)
                }
                .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { micPulse = true } }
                .onDisappear { micPulse = false }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Try these or type your own:").font(.system(.caption, design: .rounded)).foregroundColor(.secondary).padding(.leading, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(action: { taskInput = s }) {
                                Text(s).font(.system(.subheadline, design: .rounded)).foregroundColor(.purple)
                                    .padding(.horizontal, 16).padding(.vertical, 10).background(Color.purple.opacity(0.08))
                                    .cornerRadius(20).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.purple.opacity(0.2), lineWidth: 1.5))
                            }
                        }
                    }
                }
            }
            if isAnalyzing {
                VStack(spacing: 12) {
                    ProgressView(value: analysisProgress).progressViewStyle(LinearProgressViewStyle(tint: .purple)).scaleEffect(y: 2)
                    Text(analyzeMessages[min(analyzePhase, analyzeMessages.count - 1)])
                        .font(.caption).foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.3), value: analyzePhase)
                }.padding()
                .onAppear { analyzePhase = 0 }
                .onChange(of: analysisProgress) {
                    if analysisProgress > 0.25 { analyzePhase = 1 }
                    if analysisProgress > 0.55 { analyzePhase = 2 }
                    if analysisProgress > 0.85 { analyzePhase = 3 }
                }
            }
            Spacer().frame(height: 20)
            Button(action: onAnalyze) {
                HStack(spacing: 10) { Image(systemName: "wand.and.stars"); Text("Break It Down") }
                    .font(.system(.headline, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(taskInput.isEmpty ? Color.gray.opacity(0.4) : Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }.disabled(taskInput.isEmpty || isAnalyzing)
        }
        .onAppear {
            audio.requestMicPermission()
            if audio.speechEnabled {
                audio.announceScreen("AI Task Breakdown", detail: "Type or tap the microphone to speak what you want to learn.")
            }
        }
        .onDisappear { if audio.isListening { audio.stopListening() } }
    }

    func toggleVoiceInput() {
        Haptics.impact(.medium)
        if audio.isListening {
            audio.stopListening()
        } else {
            audio.startListening { transcript in
                taskInput = transcript
            }
        }
    }
}

struct ResultsView: View {
    let breakdown: [String]; let colors: [Color]; let originalInput: String; let onAddAll: () -> Void
    private var detectedTopic: String { TaskAI.displayTopic(from: originalInput) }
    private var aiInsight: TaskAI.InsightPack { TaskAI.insightPack(for: originalInput, breakdown: breakdown) }
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ZStack { Circle().fill(Color.green.opacity(0.15)).frame(width: 48, height: 48); Image(systemName: "checkmark.circle.fill").font(.title).foregroundColor(.green) }
                    VStack(alignment: .leading, spacing: 4) { Text("Analysis Complete").font(.system(.headline, design: .rounded)).foregroundColor(.primary); Text("\(breakdown.count) personalized tasks created").font(.subheadline).foregroundColor(.secondary) }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Image(systemName: "sparkle").font(.caption).foregroundColor(.purple)
                    Text("AI analyzed: \"\(originalInput)\"").font(.system(.caption, design: .rounded)).foregroundColor(.purple).lineLimit(1)
                    Spacer()
                }.padding(.horizontal, 4)
            }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .green.opacity(0.1), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Topic: \(detectedTopic)").font(.system(.headline, design: .rounded)).foregroundColor(.primary)
                Text(aiInsight.summary).font(.subheadline).foregroundColor(.secondary)
                Text(aiInsight.whyItMatters).font(.caption).foregroundColor(.purple)
                ForEach(aiInsight.milestones, id: \.self) { milestone in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.mint).font(.caption)
                        Text(milestone).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.purple.opacity(0.12), lineWidth: 1))

            ForEach(Array(breakdown.enumerated()), id: \.offset) { i, step in
                TaskBreakdownRow(number: i+1, title: step, color: colors[i % colors.count], delay: Double(i)*0.08)
            }
            Button(action: onAddAll) {
                HStack(spacing: 10) { Image(systemName: "plus.circle.fill"); Text("Add All Tasks") }
                    .font(.system(.headline, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .green.opacity(0.3), radius: 10, y: 5)
            }
        }
    }
}

struct TaskBreakdownRow: View {
    let number: Int; let title: String; let color: Color; let delay: Double
    @State private var appeared = false
    var body: some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(color.opacity(0.15)).frame(width: 42, height: 42); Text("\(number)").font(.system(.subheadline, design: .rounded)).bold().foregroundColor(color) }
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(.body, design: .rounded)).foregroundColor(.primary); Text("25 min").font(.caption).foregroundColor(.secondary) }
            Spacer(); Image(systemName: "clock.badge.checkmark").font(.caption).foregroundColor(color.opacity(0.5))
        }.padding(14).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: color.opacity(0.12), radius: 8, y: 4).scaleEffect(appeared ? 1 : 0.92).opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(delay)) { appeared = true } }
    }
}

// MARK: - Focus Timer with Shield

struct FocusTimerSheet: View {
    @EnvironmentObject var kingdom: KingdomState; @Binding var show: Bool; let task: TaskPiece
    @State private var timeLeft: Int; @State private var isRunning = false
    @State private var timer: Timer?; @State private var isComplete = false; @State private var breatheScale: CGFloat = 1.0
    init(show: Binding<Bool>, task: TaskPiece, duration: Int = 15) {
        self._show = show; self.task = task; self._timeLeft = State(initialValue: duration)
    }
    var totalDuration: Int { kingdom.focusDuration }
    var progress: Double { 1.0 - (Double(timeLeft) / Double(totalDuration)) }
    var timeText: String { String(format: "%02d:%02d", timeLeft / 60, timeLeft % 60) }
    var body: some View {
        GeometryReader { _ in
            ZStack {
                AnimatedTimerBackground(progress: progress).ignoresSafeArea()
                if isComplete { CompletionScreen(show: $show, streak: kingdom.focusStreak) }
                else {
                    ZStack {
                        if isRunning { FocusShieldView(progress: progress) }
                        TimerContent(taskTitle: task.title, timeText: timeText, progress: progress, isRunning: isRunning, breatheScale: breatheScale,
                                     streak: kingdom.focusStreak, onToggle: toggleTimer, onReset: resetTimer,
                                     onClose: { timer?.invalidate(); show = false })
                    }
                }
            }
        }.onDisappear { timer?.invalidate() }
    }
    func toggleTimer() {
        Haptics.selection()
        isRunning.toggle()
        if isRunning {
            AccessibilityAudio.shared.speak("Focus timer started for \(task.title). Stay focused!", priority: true)
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breatheScale = 1.08 }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                if timeLeft > 0 {
                    timeLeft -= 1
                    AccessibilityAudio.shared.announceTimerUpdate(seconds: timeLeft)
                } else { completeSession() }
            }
        } else {
            AccessibilityAudio.shared.speak("Timer paused.")
            withAnimation { breatheScale = 1.0 }; timer?.invalidate()
        }
    }
    func resetTimer() { timer?.invalidate(); timeLeft = totalDuration; isRunning = false; withAnimation { breatheScale = 1.0 } }
    func completeSession() { timer?.invalidate(); isRunning = false; kingdom.completeTask(task)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { isComplete = true } }
}

struct AnimatedTimerBackground: View {
    let progress: Double
    var body: some View {
        LinearGradient(colors: [
            Color(red: 0.08 + progress * 0.05, green: 0.06 + progress * 0.08, blue: 0.2 + progress * 0.15),
            Color(red: 0.12 + progress * 0.08, green: 0.08 + progress * 0.06, blue: 0.3 + progress * 0.1)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
        .animation(.easeInOut(duration: 1), value: progress)
    }
}

struct TimerContent: View {
    let taskTitle: String; let timeText: String; let progress: Double; let isRunning: Bool
    let breatheScale: CGFloat; let streak: Int
    let onToggle: () -> Void; let onReset: () -> Void; let onClose: () -> Void
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered").font(.title3).foregroundColor(.cyan)
                    Text(isRunning ? "Defending Your Kingdom" : "Focus Session")
                        .font(.system(.title3, design: .rounded)).foregroundColor(.white.opacity(0.9))
                }
                Text(taskTitle).font(.system(.headline, design: .rounded)).foregroundColor(.white).multilineTextAlignment(.center).padding(.horizontal)
                if streak > 1 {
                    HStack(spacing: 4) { Text("🔥").font(.system(size: 14)); Text("\(streak) streak").font(.caption).foregroundColor(.orange) }
                }
            }.padding(.top, 40)

            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 20).frame(width: 260, height: 260)
                Circle().trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: [.green, .cyan, .blue, .purple, .green], center: .center),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .frame(width: 260, height: 260).rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.5), value: progress)
                Circle().fill(Color.white.opacity(0.04)).frame(width: 220, height: 220).scaleEffect(breatheScale)
                VStack(spacing: 10) {
                    Text(timeText).font(.system(size: 56, weight: .bold, design: .rounded)).foregroundColor(.white).monospacedDigit()
                    Text(isRunning ? "Shield active — stay focused" : "Tap play to activate shield")
                        .font(.system(.caption, design: .rounded)).foregroundColor(.white.opacity(0.6))
                }
            }

            HStack(spacing: 60) {
                Button(action: onToggle) {
                    ZStack { Circle().fill(Color.white.opacity(0.15)).frame(width: 72, height: 72)
                        Image(systemName: isRunning ? "pause.fill" : "play.fill").font(.system(size: 28)).foregroundColor(.white) }
                }
                .accessibilityLabel(isRunning ? "Pause timer" : "Start timer")
                .accessibilityHint(isRunning ? "Pauses the focus session" : "Begins the focus countdown")
                Button(action: onReset) {
                    ZStack { Circle().fill(Color.white.opacity(0.08)).frame(width: 72, height: 72)
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 24)).foregroundColor(.white.opacity(0.7)) }
                }
                .accessibilityLabel("Reset timer")
            }
            Spacer()
            Button(action: onClose) {
                Text("Close").font(.system(.body, design: .rounded)).foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 24).padding(.vertical, 12).background(.ultraThinMaterial).clipShape(Capsule())
            }.padding(.bottom, 30)
        }
    }
}

struct CompletionScreen: View {
    @EnvironmentObject var kingdom: KingdomState
    @Binding var show: Bool; let streak: Int
    @State private var celebrate = false; @State private var showConfetti = false
    @State private var coinsPop = false
    var body: some View {
        ZStack {
            if showConfetti { ConfettiView(count: 60) }
            VStack(spacing: 24) {
                Spacer()
                ZStack { PulseRing(color: .yellow.opacity(0.4)).frame(width: 180, height: 180)
                    Text("🎉").font(.system(size: 100)).scaleEffect(celebrate ? 1.15 : 0.9) }
                VStack(spacing: 14) {
                    Text("Session Complete!").font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(.white)

                    HStack(spacing: 10) {
                        Text("💰").font(.system(size: 32)).scaleEffect(coinsPop ? 1.2 : 0.8)
                        Text("+\(kingdom.lastCoinsEarned) coins").font(.system(.title2, design: .rounded)).bold().foregroundColor(.orange)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.orange.opacity(0.15)).clipShape(Capsule())

                    if kingdom.lastGroupBonus > 0 {
                        HStack(spacing: 8) {
                            Text("⭐").font(.system(size: 24))
                            Text("ALL TASKS DONE! +\(kingdom.lastGroupBonus) bonus!").font(.system(.headline, design: .rounded)).foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.yellow.opacity(0.15)).clipShape(Capsule())
                    }

                    if streak > 1 {
                        HStack(spacing: 6) { Text("🔥"); Text("\(streak) session streak!").font(.headline).foregroundColor(.orange) }
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color.orange.opacity(0.15)).clipShape(Capsule())
                    }

                    Text("Spend your coins in the Kingdom Shop!").font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.7)).padding(.top, 4)
                }
                Spacer()
                Button(action: { show = false }) {
                    HStack(spacing: 10) { Image(systemName: "crown.fill"); Text("View Kingdom & Shop") }
                        .font(.system(.headline, design: .rounded)).foregroundColor(.white).padding(.horizontal, 36).padding(.vertical, 18)
                        .background(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .green.opacity(0.4), radius: 12, y: 6)
                }.padding(.bottom, 40)
            }.padding()
        }
        .onAppear {
            showConfetti = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5).repeatForever(autoreverses: true)) { celebrate = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5).delay(0.3)) { coinsPop = true }
        }
    }
}

// MARK: - Quiz System

struct QuizSheet: View {
    @EnvironmentObject var kingdom: KingdomState; @Binding var show: Bool; let groupID: UUID
    @State private var understanding = 3; @State private var keyLearning = ""; @State private var confidence = 3; @State private var showResults = false
    var groupTasks: [TaskPiece] { kingdom.tasks.filter { $0.groupID == groupID } }
    var topicName: String { kingdom.groupTopics[groupID] ?? "this topic" }
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color.purple.opacity(0.03)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                if showResults { QuizResultsView(show: $show, reward: calculateReward()) }
                else {
                    ScrollView {
                        VStack(spacing: 22) {
                            QuizHeader(taskCount: groupTasks.count, topic: topicName)
                            QuizQuestion(title: "How well do you understand \(topicName)?", value: $understanding, lowLabel: "Just started", highLabel: "Expert level")
                            KeyLearningInput(text: $keyLearning)
                            QuizQuestion(title: "Could you teach \(topicName) to someone else?", value: $confidence, lowLabel: "Not yet", highLabel: "Absolutely")
                            SubmitQuizButton(isEnabled: !keyLearning.isEmpty, action: submitQuiz)
                        }.padding(20)
                    }
                }
            }.navigationTitle("Knowledge Check").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !showResults { ToolbarItem(placement: .navigationBarTrailing) { Button("Cancel") { show = false } } } }
        }
    }
    func calculateReward() -> Int { groupTasks.count * 50 + (understanding + confidence) * 10 }
    func submitQuiz() {
        Haptics.notify(.success)
        let reward = calculateReward()
        AccessibilityAudio.shared.announceQuizResult(score: understanding + confidence, coins: reward)
        kingdom.coins += reward; kingdom.completedGroups.insert(groupID)
        kingdom.showShopHint = true
        let topic = kingdom.groupTopics[groupID] ?? TaskAI.extractTopic(from: groupTasks.first?.title ?? "")
        if let i = kingdom.knowledgeMap.firstIndex(where: { $0.topic.lowercased() == topic.lowercased() }) {
            kingdom.knowledgeMap[i].quizScore = (understanding + confidence) * 10
            if understanding >= 4 && kingdom.knowledgeMap[i].masteryLevel < 4 { kingdom.knowledgeMap[i].masteryLevel += 1 }
        } else {
            kingdom.knowledgeMap.append(KnowledgeEntry(topic: topic.capitalized, tasksCompleted: groupTasks.count, quizScore: (understanding + confidence) * 10, masteryLevel: understanding >= 4 ? 2 : 1))
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showResults = true }
    }
}

struct QuizHeader: View {
    let taskCount: Int; let topic: String
    var body: some View {
        VStack(spacing: 16) {
            ZStack { Circle().fill(RadialGradient(colors: [.yellow.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 60)).frame(width: 120, height: 120); Text("🎓").font(.system(size: 64)) }
            Text("Reflect on Your Learning").font(.system(.title2, design: .rounded)).bold().foregroundColor(.primary)
            Text("Topic: \(topic)").font(.system(.headline, design: .rounded)).foregroundColor(.purple)
            Text("You completed \(taskCount) focus sessions").font(.subheadline).foregroundColor(.secondary)
        }.padding(.top, 10)
    }
}

struct QuizQuestion: View {
    let title: String; @Binding var value: Int; let lowLabel: String; let highLabel: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundColor(.primary)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { r in
                    Button(action: { withAnimation(.spring(response: 0.3)) { value = r } }) {
                        ZStack { Circle().fill(r <= value ? LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.1)], startPoint: .top, endPoint: .bottom)).frame(width: 48, height: 48)
                            Text("\(r)").font(.system(.headline, design: .rounded)).foregroundColor(r <= value ? .white : .secondary) }
                    }
                }
            }
            HStack { Text(lowLabel).font(.caption).foregroundColor(.secondary); Spacer(); Text(highLabel).font(.caption).foregroundColor(.secondary) }
        }.padding(18).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

struct KeyLearningInput: View {
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's one key thing you learned?").font(.system(.headline, design: .rounded)).foregroundColor(.primary)
            TextEditor(text: $text).font(.system(.body, design: .rounded)).foregroundColor(.primary).frame(height: 100).padding(10)
                .background(Color(.systemBackground)).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.25), lineWidth: 1.5))
            Text("Be honest - this reinforces your learning").font(.caption).foregroundColor(.secondary)
        }.padding(18).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

struct SubmitQuizButton: View {
    let isEnabled: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: "gift.fill"); Text("Submit & Claim Reward") }
                .font(.system(.headline, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(isEnabled ? Color.purple : Color.gray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }.disabled(!isEnabled)
    }
}

struct QuizResultsView: View {
    @EnvironmentObject var kingdom: KingdomState; @Binding var show: Bool; let reward: Int
    @State private var showCoins = false; @State private var showConfetti = false
    var body: some View {
        ZStack {
            if showConfetti { ConfettiView(count: 40) }
            VStack(spacing: 28) {
                Spacer(); Text("🎆").font(.system(size: 100))
                Text("Knowledge Proven!").font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(.primary)
                VStack(spacing: 18) {
                    Text("You earned:").font(.system(.title3, design: .rounded)).foregroundColor(.secondary)
                    HStack(spacing: 10) { Text("💰").font(.system(size: 36)); Text("\(reward)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundColor(.orange); Text("coins").font(.system(.title3, design: .rounded)).foregroundColor(.secondary) }.scaleEffect(showCoins ? 1.08 : 1.0)
                    HStack(spacing: 6) { Image(systemName: "sparkles").foregroundColor(.purple); Text("Spend them in the Kingdom Shop!").font(.system(.headline, design: .rounded)).foregroundColor(.purple) }
                }
                Spacer()
                Button(action: { show = false }) {
                    HStack(spacing: 10) { Image(systemName: "crown.fill"); Text("View Kingdom & Shop") }
                        .font(.system(.headline, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }.padding(.horizontal).padding(.bottom, 30)
            }.padding()
        }
        .onAppear { showConfetti = true; withAnimation(.spring(response: 0.6, dampingFraction: 0.6).repeatForever(autoreverses: true)) { showCoins = true } }
    }
}

// MARK: - Interactive Kingdom Shop

struct KingdomShopView: View {
    @EnvironmentObject var kingdom: KingdomState; @Binding var show: Bool
    @State private var selectedCategory: ShopCategory = .housing
    @State private var purchaseAnimation: BuildingType? = nil

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color.orange.opacity(0.04), Color.purple.opacity(0.03)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ShopWalletBar(coins: kingdom.coins, buildings: kingdom.buildingCount)
                        Text("Build in 3D: buy shops and buildings, then explore your kingdom in immersive view.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        KingdomStatsBar()
                        ShopAdvisorBanner(tip: kingdom.aiAdvisorTip)
                        if kingdom.economyIncome > 0 {
                            ShopCollectIncomeButton(income: kingdom.economyIncome) { kingdom.collectEconomyIncome() }
                        }
                        ShopCategoryPicker(selected: $selectedCategory)
                        ShopCategoryDescription(category: selectedCategory)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(BuildingType.forCategory(selectedCategory), id: \.rawValue) { type in
                                ShopBuildingCard(
                                    type: type,
                                    owned: kingdom.buildingsOfType(type),
                                    canAfford: kingdom.canAfford(type),
                                    isPurchasing: purchaseAnimation == type
                                ) {
                                    purchaseBuilding(type)
                                }
                            }
                        }
                        Spacer().frame(height: 30)
                    }.padding(.horizontal, 18).padding(.top, 10)
                }
            }
            .navigationTitle("Kingdom Shop").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { show = false } } }
            .onAppear {
                AccessibilityAudio.shared.announceScreen("Kingdom Shop", detail: "You have \(kingdom.coins) coins. Browse 5 building categories to grow your kingdom.")
            }
        }
    }

    private func purchaseBuilding(_ type: BuildingType) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { purchaseAnimation = type }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            kingdom.purchaseBuilding(type: type)
            withAnimation(.spring(response: 0.3)) { purchaseAnimation = nil }
        }
    }
}

struct ShopWalletBar: View {
    let coins: Int; let buildings: Int
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("💰").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(coins)").font(.system(.title2, design: .rounded)).bold().foregroundColor(.orange)
                    Text("coins").font(.caption2).foregroundColor(.secondary)
                }
            }.frame(maxWidth: .infinity)
            Divider().frame(height: 36)
            HStack(spacing: 8) {
                Text("🏘️").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(buildings)").font(.system(.title2, design: .rounded)).bold().foregroundColor(.purple)
                    Text("buildings").font(.caption2).foregroundColor(.secondary)
                }
            }.frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14).padding(.horizontal, 8)
        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .orange.opacity(0.1), radius: 8, y: 4)
    }
}

struct KingdomStatsBar: View {
    @EnvironmentObject var kingdom: KingdomState
    var body: some View {
        HStack(spacing: 0) {
            KingdomStatPill(emoji: "👥", value: kingdom.population, label: "Pop", color: .blue)
            KingdomStatPill(emoji: "💵", value: kingdom.economyIncome, label: "Income", color: .green)
            KingdomStatPill(emoji: "📖", value: kingdom.xpBoostPercent, label: "XP%", color: .purple)
            KingdomStatPill(emoji: "🛡️", value: kingdom.streakShield, label: "Shield", color: .red)
            KingdomStatPill(emoji: "🌸", value: kingdom.beautyScore, label: "Beauty", color: .pink)
        }
        .padding(.vertical, 10).padding(.horizontal, 4)
        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct KingdomStatPill: View {
    let emoji: String; let value: Int; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(emoji).font(.system(size: 16))
            Text("\(value)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct ShopAdvisorBanner: View {
    let tip: String
    @State private var sparkle = false
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.cyan.opacity(0.15)).frame(width: 48, height: 48)
                Text("🤖").font(.system(size: 26)).scaleEffect(sparkle ? 1.1 : 1.0)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("AI City Advisor").font(.system(.caption, design: .rounded)).bold().foregroundColor(.cyan)
                Text(tip).font(.system(.subheadline, design: .rounded)).foregroundColor(.primary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(LinearGradient(colors: [Color.cyan.opacity(0.08), Color.blue.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.25), lineWidth: 1.5))
        .onAppear { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { sparkle = true } }
    }
}

struct ShopCollectIncomeButton: View {
    let income: Int; let action: () -> Void
    @State private var pulse = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "dollarsign.circle.fill").font(.title3).scaleEffect(pulse ? 1.15 : 1.0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Collect One-Time Bonus").font(.system(.subheadline, design: .rounded)).bold()
                    Text("+\(income) coins — each building pays once").font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundColor(.white).padding(14)
            .background(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

struct ShopCategoryPicker: View {
    @Binding var selected: ShopCategory
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ShopCategory.allCases) { cat in
                    Button(action: { withAnimation(.spring(response: 0.3)) { selected = cat } }) {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(selected == cat
                                          ? LinearGradient(colors: [cat.color, cat.color.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                          : LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 52, height: 52)
                                Image(systemName: cat.icon).font(.system(size: 20))
                                    .foregroundColor(selected == cat ? .white : .secondary)
                            }
                            Text(cat.name).font(.system(size: 11, weight: selected == cat ? .bold : .medium, design: .rounded))
                                .foregroundColor(selected == cat ? cat.color : .secondary)
                        }
                    }
                }
            }.padding(.horizontal, 4)
        }
    }
}

struct ShopCategoryDescription: View {
    let category: ShopCategory
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon).foregroundColor(category.color)
            Text(category.description).font(.system(.subheadline, design: .rounded)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct ShopBuildingCard: View {
    let type: BuildingType; let owned: Int; let canAfford: Bool; let isPurchasing: Bool
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.16))
                    .offset(y: 8)

                RoundedRectangle(cornerRadius: 16)
                    .fill(canAfford
                          ? LinearGradient(colors: [type.category.color.opacity(0.1), type.category.color.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.gray.opacity(0.06), Color.gray.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                VStack(spacing: 8) {
                    Mini3DBuildingView(type: type, size: 54)
                        .scaleEffect(isPurchasing ? 1.2 : 1.0)
                        .opacity(isPurchasing ? 0.65 : 1.0)
                    Text(type.name).font(.system(.subheadline, design: .rounded)).bold()
                        .foregroundColor(.primary).lineLimit(1)
                    Text(type.benefit).font(.system(size: 11, design: .rounded))
                        .foregroundColor(type.category.color).lineLimit(1)
                    if owned > 0 {
                        Text("Owned: \(owned)").font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(type.category.color.opacity(0.7)))
                    }
                }.padding(.vertical, 14)
            }
            .frame(height: 160)
            .rotation3DEffect(.degrees(12), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                canAfford ? type.category.color.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: 1.5))

            Button(action: onBuy) {
                HStack(spacing: 6) {
                    Text("💰").font(.system(size: 12))
                    Text("\(type.cost)").font(.system(.subheadline, design: .rounded)).bold()
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(canAfford ? type.category.color : Color.gray.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canAfford)
            .accessibilityLabel("Buy \(type.name) for \(type.cost) coins")
            .accessibilityHint(canAfford ? "Double tap to purchase" : "Not enough coins")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.name), \(type.benefit), costs \(type.cost) coins\(owned > 0 ? ", owned \(owned)" : "")")
    }
}

// MARK: - Onboarding

struct OnboardingOverlay: View {
    @Binding var isVisible: Bool; @State private var scale: CGFloat = 0.9; @State private var opacity: Double = 0
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { dismiss() }
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 20) {
                    Text("🏰").font(.system(size: 80))
                    Text("Kingdom Builder").font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(.primary)
                    Text("Turn overwhelming tasks into focused sessions.\nEach session builds your kingdom.").font(.system(.body, design: .rounded)).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    VStack(alignment: .leading, spacing: 14) {
                        OnboardingStep(icon: "brain.head.profile", color: .purple, text: "AI breaks any task into focused pieces")
                        OnboardingStep(icon: "dollarsign.circle.fill", color: .orange, text: "Earn coins, buy buildings, build your kingdom")
                        OnboardingStep(icon: "building.2.fill", color: .green, text: "Tap buildings to explore inside & see stats")
                        OnboardingStep(icon: "chart.bar.xaxis", color: .blue, text: "Track knowledge, quiz yourself, master topics")
                        OnboardingStep(icon: "ear.badge.waveform", color: .pink, text: "Audio accessibility: text-to-speech & sound cues")
                    }.padding(.horizontal, 30)
                }
                Spacer()
                Button(action: dismiss) {
                    HStack(spacing: 10) { Image(systemName: "crown.fill"); Text("Start Building") }
                        .font(.system(.headline, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 20)
                        .background(LinearGradient(colors: [.purple, .blue, .cyan], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 18)).shadow(color: .purple.opacity(0.4), radius: 15, y: 8)
                }.padding(.horizontal, 30).padding(.bottom, 50)
            }.background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 30)).padding(20).scaleEffect(scale).opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { scale = 1.0; opacity = 1.0 }
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityAudio.shared.speechEnabled = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                AccessibilityAudio.shared.announceOnboarding()
            }
        }
    }
    func dismiss() {
        AccessibilityAudio.shared.stopSpeaking()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { scale = 0.9; opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isVisible = false }
    }
}

struct OnboardingStep: View {
    let icon: String; let color: Color; let text: String
    var body: some View {
        HStack(spacing: 14) { Image(systemName: icon).font(.title3).foregroundColor(color).frame(width: 36)
            Text(text).font(.system(.subheadline, design: .rounded)).foregroundColor(.primary) }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var kingdom: KingdomState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTaskInput = false; @State private var showTimer = false
    @State private var showQuiz = false; @State private var showShop = false
    @State private var showActivity = false; @State private var showOnboarding = true
    @State private var showAccessibility = false
    @State private var selectedTask: TaskPiece?; @State private var quizGroupID: UUID?

    var hasQuizAvailable: Bool {
        kingdom.tasks.contains { t in
            let g = kingdom.tasks.filter { $0.groupID == t.groupID }
            return g.allSatisfy({ $0.completed }) && !g.isEmpty && !kingdom.completedGroups.contains(t.groupID)
        }
    }

    

    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                ZStack {
                    LinearGradient(colors: [Color(red:0.95,green:0.95,blue:0.98), Color(red:0.92,green:0.91,blue:0.97)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            HeaderStats()
                            LevelProgressBar()
                            KingdomView().frame(height: max(400, geometry.size.height * 0.48))
                            if hasQuizAvailable {
                                QuizAvailableBanner { if let g = getFirstUnquizzedGroup() { quizGroupID = g; showQuiz = true } }
                            }
                            ActiveTasksList(selectedTask: $selectedTask, showTimer: $showTimer)
                            ActionButtons(showTaskInput: $showTaskInput, showShop: $showShop)
                            Button(action: { showActivity = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "chart.bar.xaxis").font(.title3)
                                    Text("Activity & Knowledge Hub").font(.system(.headline, design: .rounded))
                                }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                                .background(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                            }
                            .accessibilityLabel("Activity and Knowledge Hub")
                            .accessibilityHint("View your study charts, mastery progress, and task history")
                            Button(action: { showAccessibility = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "ear.badge.waveform").font(.title3)
                                    Text("Accessibility & Audio").font(.system(.headline, design: .rounded))
                                }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                                .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .purple.opacity(0.3), radius: 12, y: 6)
                            }
                            .accessibilityLabel("Accessibility and audio settings")
                            .accessibilityHint("Configure text to speech and sound cues for visually impaired users")
                            Spacer().frame(height: 30)
                        }.padding(.horizontal, 18).padding(.top, 10)
                    }
                    if showOnboarding && !kingdom.hasSeenOnboarding {
                        OnboardingOverlay(isVisible: $showOnboarding)
                            .onDisappear {
                                kingdom.hasSeenOnboarding = true; kingdom.loadDemoTask()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    AccessibilityAudio.shared.announceScreen("Kingdom Builder",
                                        detail: "Your kingdom has \(kingdom.buildingCount) buildings and \(kingdom.coins) coins. You have \(kingdom.tasks.filter { !$0.completed }.count) active tasks. Tap Add New Task to speak or type what you want to learn.")
                                }
                            }
                    }
                    if kingdom.showCelebration && !reduceMotion {
                        ConfettiView(count: 30).onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { kingdom.showCelebration = false } }
                    }
                    if kingdom.showLevelUp {
                        LevelUpBanner(oldLevel: kingdom.previousLevel, newLevel: kingdom.level, title: kingdom.kingdomTitle,
                                      onDismiss: { kingdom.showLevelUp = false })
                    }
                }
                .navigationTitle("Kingdom Builder").navigationBarTitleDisplayMode(.large)
                .sheet(isPresented: $showTaskInput) { TaskInputSheet(show: $showTaskInput) }
                .sheet(isPresented: $showTimer) { if let t = selectedTask { FocusTimerSheet(show: $showTimer, task: t, duration: kingdom.focusDuration) } }
                .sheet(isPresented: $showQuiz) { if let g = quizGroupID { QuizSheet(show: $showQuiz, groupID: g) } }
                .sheet(isPresented: $showShop) { KingdomShopView(show: $showShop) }
                .sheet(isPresented: $showActivity) { ActivityHubSheet(show: $showActivity) }
                .sheet(isPresented: $showAccessibility) { AccessibilitySettingsView() }
                .sheet(item: $kingdom.selectedBuilding) { bld in
                    BuildingInteriorSheet(building: bld)
                }
            }.navigationViewStyle(.stack)
        }
    }

    func getFirstUnquizzedGroup() -> UUID? {
        for t in kingdom.tasks {
            let g = kingdom.tasks.filter { $0.groupID == t.groupID }
            if g.allSatisfy({ $0.completed }) && !g.isEmpty && !kingdom.completedGroups.contains(t.groupID) { return t.groupID }
        }
        return nil
    }
}
