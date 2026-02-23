import SwiftUI

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

enum BuildingType: String, CaseIterable, Codable {
    case hut, house, shop, market, fountain, castle, road, tower, garden, windmill
    var emoji: String {
        switch self {
        case .hut: return "🛖"; case .house: return "🏠"; case .shop: return "🏪"
        case .market: return "🏛️"; case .fountain: return "⛲"; case .castle: return "🏰"
        case .road: return "🛣️"; case .tower: return "🗼"; case .garden: return "🌳"; case .windmill: return "🌾"
        }
    }
    var name: String {
        switch self {
        case .hut: return "Hut"; case .house: return "House"; case .shop: return "Shop"
        case .market: return "Market"; case .fountain: return "Fountain"; case .castle: return "Castle"
        case .road: return "Road"; case .tower: return "Tower"; case .garden: return "Garden"; case .windmill: return "Windmill"
        }
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
    init(id: UUID = UUID(), type: BuildingType, col: Int, row: Int, jitterX: CGFloat = 0, jitterY: CGFloat = 0) {
        self.id = id; self.type = type; self.col = col; self.row = row; self.jitterX = jitterX; self.jitterY = jitterY
    }
}

struct Business: Identifiable {
    let id = UUID(); var name: String; var icon: String; var coinsPerHour: Int; var cost: Int; var owned: Int = 0
}

struct ConfettiParticle: Identifiable {
    let id = UUID(); let color: Color; let xOffset: CGFloat; let yOffset: CGFloat
    let size: CGFloat; let delay: Double; let duration: Double; let rotation: Double
}

// MARK: - State Management

class KingdomState: ObservableObject {
    @Published var tasks: [TaskPiece] = []
    @Published var buildings: [KingdomBuilding] = []
    @Published var businesses: [Business] = [
        Business(name: "Coffee Cart", icon: "☕", coinsPerHour: 5, cost: 50),
        Business(name: "Book Shop", icon: "📚", coinsPerHour: 10, cost: 100),
        Business(name: "Study Hall", icon: "✏️", coinsPerHour: 20, cost: 200),
        Business(name: "Library", icon: "🏛️", coinsPerHour: 50, cost: 500)
    ]
    @Published var coins: Int = 0
    @Published var totalFocusMinutes: Int = 0
    @Published var completedGroups: Set<UUID> = []
    @Published var buildingCount: Int = 0
    @Published var hasSeenOnboarding: Bool = false
    @Published var focusStreak: Int = 0
    @Published var showCelebration: Bool = false
    @Published var showLevelUp: Bool = false
    @Published var previousLevel: Int = 1

    let focusDuration: Int = 15

    var level: Int {
        let xp = totalXP
        if xp < 100 { return 1 }; if xp < 300 { return 2 }; if xp < 600 { return 3 }
        if xp < 1000 { return 4 }; if xp < 1500 { return 5 }; if xp < 2200 { return 6 }
        if xp < 3000 { return 7 }; if xp < 4000 { return 8 }; if xp < 5500 { return 9 }
        return 10
    }
    var totalXP: Int { totalFocusMinutes * 10 + buildingCount * 50 + coins }
    var xpForCurrentLevel: Int {
        let t = [0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5500, 99999]
        return t[min(level, t.count - 1) - 1]
    }
    var xpForNextLevel: Int {
        let t = [0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5500, 99999]
        return t[min(level, t.count - 1)]
    }
    var xpProgress: Double {
        let c = totalXP - xpForCurrentLevel; let n = xpForNextLevel - xpForCurrentLevel
        guard n > 0 else { return 1.0 }; return min(1.0, Double(c) / Double(n))
    }
    var passiveIncome: Int { businesses.reduce(0) { $0 + ($1.coinsPerHour * $1.owned) } }
    var kingdomTitle: String {
        switch level {
        case 1: return "Settlement"; case 2: return "Hamlet"; case 3: return "Village"
        case 4: return "Town"; case 5: return "Borough"; case 6: return "City"
        case 7: return "Metropolis"; case 8: return "Capital"; case 9: return "Empire"
        default: return "Legendary Realm"
        }
    }

    func addTasks(_ newTasks: [TaskPiece], groupID: UUID) {
        tasks.append(contentsOf: newTasks.map { var t = $0; t.groupID = groupID; return t })
    }

    func completeTask(_ task: TaskPiece) {
        let oldLevel = level
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].completed = true }
        totalFocusMinutes += task.minutes
        buildingCount += 1
        focusStreak += 1
        addBuilding()
        checkGroupCompletion(groupID: task.groupID)
        showCelebration = true
        if level > oldLevel {
            previousLevel = oldLevel
            showLevelUp = true
        }
    }

    func addBuilding() {
        let buildingType: BuildingType
        switch buildingCount {
        case 1...2: buildingType = .hut; case 3...4: buildingType = .house
        case 5...6: buildingType = .shop; case 7...8: buildingType = .market
        case 9...10: buildingType = .tower; default: buildingType = .castle
        }
        let col = (buildingCount - 1) % 5
        let row = (buildingCount - 1) / 5
        let building = KingdomBuilding(
            type: buildingType, col: col, row: row,
            jitterX: CGFloat.random(in: -0.02...0.02),
            jitterY: CGFloat.random(in: -0.01...0.01)
        )
        buildings.append(building)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            if let i = buildings.firstIndex(where: { $0.id == building.id }) { buildings[i].scale = 1.0 }
        }
        if buildingCount % 3 == 0 { addDecoration() }
    }

    func addDecoration() {
        let types: [BuildingType] = [.garden, .road, .windmill]
        let type = types[buildingCount % types.count]
        let decoration = KingdomBuilding(
            type: type, col: Int.random(in: 0...5), row: Int.random(in: 0...2),
            jitterX: CGFloat.random(in: -0.03...0.03),
            jitterY: CGFloat.random(in: -0.01...0.01)
        )
        buildings.append(decoration)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            if let i = buildings.firstIndex(where: { $0.id == decoration.id }) { buildings[i].scale = 1.0 }
        }
    }

    func checkGroupCompletion(groupID: UUID) {
        let g = tasks.filter { $0.groupID == groupID }
        if g.allSatisfy({ $0.completed }) && !g.isEmpty && !completedGroups.contains(groupID) {
            completedGroups.insert(groupID)
        }
    }
    func buyBusiness(_ b: Business) {
        if coins >= b.cost { coins -= b.cost; if let i = businesses.firstIndex(where: { $0.id == b.id }) { businesses[i].owned += 1 } }
    }
    func collectPassiveCoins() { coins += passiveIncome }
    func loadDemoTask() {
        let g = UUID()
        addTasks([
            TaskPiece(title: "Review core concepts", minutes: 25, groupID: g),
            TaskPiece(title: "Practice with examples", minutes: 25, groupID: g),
            TaskPiece(title: "Test your understanding", minutes: 25, groupID: g)
        ], groupID: g)
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
        let topic = words.joined(separator: " ")
        return topic.isEmpty ? input : topic
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
        .accessibilityLabel("Level \(kingdom.level), \(kingdom.kingdomTitle)")
    }
}

// MARK: - Kingdom Landscape (Buildings ON Ground)

struct KingdomView: View {
    @EnvironmentObject var kingdom: KingdomState
    var skyColors: [Color] {
        switch kingdom.level {
        case 1: return [Color(red: 0.98, green: 0.7, blue: 0.5), Color(red: 0.55, green: 0.75, blue: 0.95)]
        case 2: return [Color(red: 0.45, green: 0.75, blue: 0.98), Color(red: 0.35, green: 0.6, blue: 0.9)]
        case 3: return [Color(red: 0.4, green: 0.7, blue: 0.95), Color(red: 0.3, green: 0.55, blue: 0.85)]
        case 4: return [Color(red: 0.35, green: 0.65, blue: 0.95), Color(red: 0.25, green: 0.5, blue: 0.85)]
        case 5: return [Color(red: 0.95, green: 0.65, blue: 0.4), Color(red: 0.85, green: 0.45, blue: 0.55)]
        case 6...7: return [Color(red: 0.3, green: 0.25, blue: 0.55), Color(red: 0.15, green: 0.15, blue: 0.4)]
        default: return [Color(red: 0.08, green: 0.08, blue: 0.25), Color(red: 0.15, green: 0.1, blue: 0.35)]
        }
    }

    func buildingPosition(col: Int, row: Int, jitterX: CGFloat, jitterY: CGFloat, w: CGFloat, h: CGFloat) -> CGPoint {
        let groundTop: CGFloat = 0.60
        let rowHeight: CGFloat = 0.11
        let cols: CGFloat = 6.0
        let x = (CGFloat(col) + 1) / cols * w * 0.85 + w * 0.08 + jitterX * w
        let y = (groundTop + CGFloat(row) * rowHeight + jitterY) * h
        return CGPoint(x: x, y: y)
    }

    func buildingScale(row: Int) -> CGFloat {
        switch row { case 0: return 0.85; case 1: return 0.95; default: return 1.05 }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            ZStack {
                LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
                    .animation(.easeInOut(duration: 1.5), value: kingdom.level)

                if kingdom.level >= 6 {
                    ForEach(0..<12, id: \.self) { i in
                        SparkleView(x: CGFloat.random(in: 0...w), y: CGFloat.random(in: 0...(h * 0.35)), delay: Double(i) * 0.25)
                    }
                }

                FloatingCloud(width: 80, height: 30, startX: -80, y: h*0.1, speed: 28, containerWidth: w)
                FloatingCloud(width: 110, height: 40, startX: -180, y: h*0.18, speed: 38, containerWidth: w)
                FloatingCloud(width: 65, height: 24, startX: -40, y: h*0.06, speed: 22, containerWidth: w)

                MountainRange()
                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.45, blue: 0.55).opacity(0.5),
                                                   Color(red: 0.25, green: 0.35, blue: 0.45).opacity(0.3)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.45).offset(y: h * 0.18)

                RollingHills()
                    .fill(LinearGradient(colors: [Color(red: 0.28, green: 0.65, blue: 0.3), Color(red: 0.18, green: 0.52, blue: 0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.5).offset(y: h * 0.28)

                VStack {
                    Spacer()
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.55, blue: 0.2), Color(red: 0.13, green: 0.42, blue: 0.13)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: h * 0.35)
                }

                GrassTextureLine()
                    .stroke(Color(red: 0.15, green: 0.45, blue: 0.15).opacity(0.3), lineWidth: 1.5)
                    .frame(height: h * 0.1).offset(y: h * 0.27)

                ForEach(kingdom.buildings.sorted(by: { $0.row < $1.row })) { building in
                    let pos = buildingPosition(col: building.col, row: building.row, jitterX: building.jitterX, jitterY: building.jitterY, w: w, h: h)
                    let depthScale = buildingScale(row: building.row)

                    VStack(spacing: 0) {
                        ZStack {
                            Ellipse()
                                .fill(Color.black.opacity(0.15))
                                .frame(width: 40 * depthScale, height: 10 * depthScale)
                                .offset(y: building.type == .castle ? 28 : 22)

                            Text(building.type.emoji)
                                .font(.system(size: (building.type == .castle ? 52 : 38) * depthScale))
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                        }

                        Text(building.type.name)
                            .font(.system(size: max(8, 9 * depthScale), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                    }
                    .scaleEffect(building.scale)
                    .position(pos)
                }

                if kingdom.buildings.isEmpty {
                    VStack(spacing: 14) {
                        ZStack {
                            PulseRing(color: .white.opacity(0.5)).frame(width: 120, height: 120)
                            Text("🏗️").font(.system(size: 72))
                        }
                        Text("Your Kingdom Awaits").font(.system(.title2, design: .rounded)).bold().foregroundColor(.white).shadow(color: .black.opacity(0.3), radius: 4)
                        Text("Complete focus sessions to build!").font(.subheadline).foregroundColor(.white.opacity(0.9))
                    }
                    .accessibilityLabel("Empty kingdom. Complete focus sessions to add buildings.")
                }

                VStack {
                    HStack {
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
                LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
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
    var activeTasks: [TaskPiece] { kingdom.tasks.filter { !$0.completed } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Active Tasks").font(.system(.title3, design: .rounded)).bold().foregroundColor(.primary)
                Spacer()
                Text("\(activeTasks.count) remaining").font(.subheadline).foregroundColor(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
            if activeTasks.isEmpty { EmptyTasksView() }
            else {
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { i, task in
                    TaskRowView(task: task, index: i) { selectedTask = task; showTimer = true }
                }
            }
        }
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
    let task: TaskPiece; let index: Int; let onFocus: () -> Void
    @State private var appeared = false
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
            Button(action: onFocus) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Focus").font(.system(.subheadline, design: .rounded)).bold()
                }.foregroundColor(.white).padding(.horizontal, 18).padding(.vertical, 10)
                .background(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .green.opacity(0.3), radius: 6, y: 3)
            }
        }
        .padding(14).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
        .scaleEffect(appeared ? 1 : 0.95).opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06)) { appeared = true } }
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
    @Binding var showTaskInput: Bool; @Binding var showBusiness: Bool; let hasBusinesses: Bool
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
            if hasBusinesses {
                Button(action: { showBusiness = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.crop.circle.fill").font(.title3)
                        Text("Manage Businesses").font(.system(.headline, design: .rounded))
                    }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .orange.opacity(0.3), radius: 12, y: 6)
                }
            }
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
        isAnalyzing = true; analysisProgress = 0
        for i in 1...20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.07) {
                withAnimation { analysisProgress = Double(i) / 20.0 }
                if i == 20 { breakdown = TaskAI.breakdownTask(taskInput); isAnalyzing = false
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showResults = true } }
            }
        }
    }
    func addAllTasks() {
        let g = UUID()
        kingdom.addTasks(breakdown.map { TaskPiece(title: $0, minutes: 25, groupID: g) }, groupID: g); show = false
    }
}

struct InputView: View {
    @Binding var taskInput: String; @Binding var isAnalyzing: Bool; @Binding var analysisProgress: Double; let onAnalyze: () -> Void
    let suggestions = ["Study for biology exam", "Learn statistics", "Write research paper", "Learn ML math",
                        "Build a mobile app", "Prepare presentation", "Practice guitar", "Learn Spanish",
                        "Study chemistry", "Research history"]
    @State private var analyzePhase = 0
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
                Text("Type anything — AI will create your perfect study plan").font(.subheadline).foregroundColor(.secondary)
            }.multilineTextAlignment(.center)
            TextField("e.g., Learn quantum physics, Study for SAT, Practice drawing...", text: $taskInput)
                .font(.system(.body, design: .rounded)).foregroundColor(.primary).textFieldStyle(.plain)
                .padding(16).background(Color(.systemBackground)).cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(colors: [.purple.opacity(0.4), .blue.opacity(0.3)], startPoint: .leading, endPoint: .trailing), lineWidth: 2))
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
    }
}

struct ResultsView: View {
    let breakdown: [String]; let colors: [Color]; let originalInput: String; let onAddAll: () -> Void
    private var detectedTopic: String { TaskAI.extractTopic(from: originalInput.lowercased()) }
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
        isRunning.toggle()
        if isRunning {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breatheScale = 1.08 }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                if timeLeft > 0 { timeLeft -= 1 } else { completeSession() }
            }
        } else { withAnimation { breatheScale = 1.0 }; timer?.invalidate() }
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
                Button(action: onReset) {
                    ZStack { Circle().fill(Color.white.opacity(0.08)).frame(width: 72, height: 72)
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 24)).foregroundColor(.white.opacity(0.7)) }
                }
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
    @Binding var show: Bool; let streak: Int
    @State private var celebrate = false; @State private var showConfetti = false
    var body: some View {
        ZStack {
            if showConfetti { ConfettiView(count: 60) }
            VStack(spacing: 28) {
                Spacer()
                ZStack { PulseRing(color: .yellow.opacity(0.4)).frame(width: 180, height: 180)
                    Text("🎉").font(.system(size: 100)).scaleEffect(celebrate ? 1.15 : 0.9) }
                VStack(spacing: 12) {
                    Text("Session Complete!").font(.system(.largeTitle, design: .rounded)).bold().foregroundColor(.white)
                    Text("New building added to your kingdom!").font(.system(.title3, design: .rounded)).foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.center)
                    if streak > 1 {
                        HStack(spacing: 6) { Text("🔥"); Text("\(streak) session streak!").font(.headline).foregroundColor(.orange) }
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Color.orange.opacity(0.15)).clipShape(Capsule())
                    }
                }
                Spacer()
                Button(action: { show = false }) {
                    HStack(spacing: 10) { Image(systemName: "crown.fill"); Text("View Kingdom") }
                        .font(.system(.headline, design: .rounded)).foregroundColor(.white).padding(.horizontal, 36).padding(.vertical, 18)
                        .background(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .green.opacity(0.4), radius: 12, y: 6)
                }.padding(.bottom, 40)
            }.padding()
        }
        .onAppear { showConfetti = true; withAnimation(.spring(response: 0.5, dampingFraction: 0.5).repeatForever(autoreverses: true)) { celebrate = true } }
    }
}

// MARK: - Quiz System

struct QuizSheet: View {
    @EnvironmentObject var kingdom: KingdomState; @Binding var show: Bool; let groupID: UUID
    @State private var understanding = 3; @State private var keyLearning = ""; @State private var confidence = 3; @State private var showResults = false
    var groupTasks: [TaskPiece] { kingdom.tasks.filter { $0.groupID == groupID } }
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color.purple.opacity(0.03)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                if showResults { QuizResultsView(show: $show, reward: calculateReward()) }
                else {
                    ScrollView {
                        VStack(spacing: 22) {
                            QuizHeader(taskCount: groupTasks.count)
                            QuizQuestion(title: "How well do you understand this topic?", value: $understanding, lowLabel: "Just started", highLabel: "Expert level")
                            KeyLearningInput(text: $keyLearning)
                            QuizQuestion(title: "Could you teach this to someone else?", value: $confidence, lowLabel: "Not yet", highLabel: "Absolutely")
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
        kingdom.coins += calculateReward(); kingdom.completedGroups.insert(groupID)
        let b = KingdomBuilding(type: .fountain, col: 3, row: 1)
        kingdom.buildings.append(b)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            if let i = kingdom.buildings.firstIndex(where: { $0.id == b.id }) { kingdom.buildings[i].scale = 1.0 }
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showResults = true }
    }
}

struct QuizHeader: View {
    let taskCount: Int
    var body: some View {
        VStack(spacing: 16) {
            ZStack { Circle().fill(RadialGradient(colors: [.yellow.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 60)).frame(width: 120, height: 120); Text("🎓").font(.system(size: 64)) }
            Text("Reflect on Your Learning").font(.system(.title2, design: .rounded)).bold().foregroundColor(.primary)
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
                    HStack(spacing: 6) { Image(systemName: "sparkles").foregroundColor(.purple); Text("Special Fountain unlocked!").font(.system(.headline, design: .rounded)).foregroundColor(.purple) }
                }
                Spacer()
                Button(action: { show = false }) {
                    HStack(spacing: 10) { Image(systemName: "crown.fill"); Text("View Kingdom & Businesses") }
                        .font(.system(.headline, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }.padding(.horizontal).padding(.bottom, 30)
            }.padding()
        }
        .onAppear { showConfetti = true; withAnimation(.spring(response: 0.6, dampingFraction: 0.6).repeatForever(autoreverses: true)) { showCoins = true } }
    }
}

// MARK: - Business System

struct BusinessSheet: View {
    @EnvironmentObject var kingdom: KingdomState; @Binding var show: Bool
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color.orange.opacity(0.03)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        BusinessHeader(coins: kingdom.coins, income: kingdom.passiveIncome)
                        ForEach(kingdom.businesses) { b in BusinessCard(business: b, canAfford: kingdom.coins >= b.cost, onBuy: { kingdom.buyBusiness(b) }) }
                        if kingdom.passiveIncome > 0 { CollectIncomeButton { kingdom.collectPassiveCoins() } }
                    }.padding(20)
                }
            }.navigationTitle("Kingdom Businesses").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { show = false } } }
        }
    }
}

struct BusinessHeader: View {
    let coins: Int; let income: Int
    var body: some View {
        VStack(spacing: 18) {
            Text("💼").font(.system(size: 56))
            HStack(spacing: 40) {
                VStack(spacing: 4) { Text("\(coins)").font(.system(.title, design: .rounded)).bold().foregroundColor(.primary); Text("Coins").font(.caption).foregroundColor(.secondary) }
                VStack(spacing: 4) { HStack(spacing: 4) { Text("+\(income)").font(.system(.title, design: .rounded)).bold().foregroundColor(.green); Text("/hr").font(.caption).foregroundColor(.secondary) }; Text("Passive Income").font(.caption).foregroundColor(.secondary) }
            }
            Text("Build businesses to earn coins while you study!").font(.subheadline).foregroundColor(.secondary)
        }.padding(20).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct BusinessCard: View {
    let business: Business; let canAfford: Bool; let onBuy: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Text(business.icon).font(.system(size: 44))
            VStack(alignment: .leading, spacing: 6) {
                Text(business.name).font(.system(.headline, design: .rounded)).foregroundColor(.primary)
                HStack(spacing: 4) { Text("+\(business.coinsPerHour)").font(.subheadline).foregroundColor(.green).bold(); Text("coins/hr").font(.caption).foregroundColor(.secondary) }
                if business.owned > 0 { Text("Owned: \(business.owned)").font(.caption).foregroundColor(.purple).bold() }
            }
            Spacer()
            Button(action: onBuy) {
                VStack(spacing: 4) { Text("💰 \(business.cost)").font(.system(.subheadline, design: .rounded)).bold(); Text("Buy").font(.caption) }
                    .foregroundColor(.white).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(canAfford ? Color.orange : Color.gray.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 12))
            }.disabled(!canAfford)
        }.padding(16).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

struct CollectIncomeButton: View {
    let action: () -> Void; @State private var pulse = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: "dollarsign.circle.fill").scaleEffect(pulse ? 1.15 : 1.0); Text("Collect Passive Income") }
                .font(.system(.headline, design: .rounded)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true } }
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
                        OnboardingStep(icon: "brain.head.profile", color: .purple, text: "AI breaks big tasks into focused pieces")
                        OnboardingStep(icon: "shield.checkered", color: .cyan, text: "Focus Shield blocks distractions")
                        OnboardingStep(icon: "flame.fill", color: .orange, text: "Build streaks, earn coins, grow your kingdom")
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
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { scale = 1.0; opacity = 1.0 } }
    }
    func dismiss() {
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
    @State private var showTaskInput = false; @State private var showTimer = false
    @State private var showQuiz = false; @State private var showBusiness = false
    @State private var showOnboarding = true; @State private var selectedTask: TaskPiece?; @State private var quizGroupID: UUID?

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
                    LinearGradient(colors: [Color(red: 0.95, green: 0.95, blue: 0.98), Color(red: 0.92, green: 0.91, blue: 0.97)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            HeaderStats()
                            LevelProgressBar()
                            KingdomView().frame(height: max(380, geometry.size.height * 0.45))
                            if hasQuizAvailable {
                                QuizAvailableBanner { if let g = getFirstUnquizzedGroup() { quizGroupID = g; showQuiz = true } }
                            }
                            ActiveTasksList(selectedTask: $selectedTask, showTimer: $showTimer)
                            ActionButtons(showTaskInput: $showTaskInput, showBusiness: $showBusiness,
                                          hasBusinesses: kingdom.coins > 0 || kingdom.businesses.contains { $0.owned > 0 })
                            Spacer().frame(height: 30)
                        }.padding(.horizontal, 18).padding(.top, 10)
                    }
                    if showOnboarding && !kingdom.hasSeenOnboarding {
                        OnboardingOverlay(isVisible: $showOnboarding)
                            .onDisappear { kingdom.hasSeenOnboarding = true; kingdom.loadDemoTask() }
                    }
                    if kingdom.showCelebration {
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
                .sheet(isPresented: $showBusiness) { BusinessSheet(show: $showBusiness) }
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
