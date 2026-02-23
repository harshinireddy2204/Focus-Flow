# Kingdom Builder — Focus Flow

A gamified focus app that turns overwhelming tasks into an interactive kingdom-building experience. Built entirely with SwiftUI for the **Apple Swift Student Challenge 2026**.

## What It Does

Students type any task — "study for biology exam", "learn statistics", "practice guitar" — and an **on-device AI engine** breaks it into focused sessions. Each completed session earns coins that players spend in the Kingdom Shop to build their own city with structured districts, interactive buildings, and a growing economy.

## Key Features

### AI Task Breakdown (Works for Any Topic)
- On-device NLP extracts the **action** (learn, build, write, practice, memorize...) and **subject** from any input
- 15+ expert-curated domains (biology, chemistry, physics, history, languages, music, art, coding, etc.)
- Dynamic step generation for topics not in the curated list
- Editable task names — rename any AI-generated step to fit your needs
- Manual task addition for quick custom entries

### Interactive Kingdom Building
- **5 Building Categories**: Housing, Economy, Culture, Defense, Nature
- **20 Unique Buildings**: Cottage → Palace, Market Stall → Bank, Library → Academy, Watchtower → Castle, Garden → Lake
- **Zoned City Layout**: Buildings are organized into districts — defense on the border, commerce and housing in the middle, culture at the center, nature scattered throughout
- **Tap-to-Enter Interiors**: Tap any building to see inside — view stats, kingdom impact, economy reports, knowledge maps, and activity history

### Coin Economy
- **+10 coins** per completed focus session
- **+50 bonus coins** for completing all tasks in a group
- Quiz rewards scale with understanding and confidence scores
- Economy buildings generate **passive income** you can collect
- Spend coins strategically across 5 categories to shape your kingdom

### Knowledge Memory System
- Tracks every topic you study with **mastery levels** (Beginner → Expert)
- Quiz scores stored per topic and contribute to mastery progression
- Knowledge Map viewable inside Culture buildings and the Activity Hub
- Topics carry across sessions — the app remembers what you've learned

### Swift Charts Visualizations
- **7-Day Activity Bar Chart**: color-graded bars showing daily task completions with annotations
- **Knowledge Mastery Chart**: horizontal bar chart mapping every studied topic to its mastery level
- Built with Apple's native `Charts` framework for polished, accessible data visualization

### Haptic Feedback
- Task completion, building purchase, coin collection, level-up, quiz submission, and timer controls all trigger tactile feedback
- Uses `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`, and `UISelectionFeedbackGenerator` for varied intensities

### Full Accessibility
- **VoiceOver**: every interactive element has `accessibilityLabel` and `accessibilityHint`
- **Reduce Motion**: confetti, floating clouds, and sparkle animations are suppressed when the system Reduce Motion setting is on
- **Dynamic Type**: stat cards, task rows, and navigation use system font scaling
- Combined accessibility elements on stat cards, task rows, building cards, and the activity summary for streamlined VoiceOver navigation

### Focus Shield (Anti-Distraction Visual)
- Animated shield visualization during focus sessions
- Distraction emojis (📱💬🎮📺🔔📧) are repelled by the shield
- Shield intensity grows as the session progresses

### Activity & Knowledge Hub
- Swift Charts 7-day activity overview and mastery visualization
- Full history of every completed task with timestamps and coins
- Knowledge Map with mastery levels across all studied topics
- Summary stats: total sessions, today's count, coins earned, streak

### Rich Demo State
- App launches with pre-built kingdom (4 buildings across zones), completed Biology tasks, an active Statistics task group, 120 coins, knowledge entries, and full task history — judges see the full experience within seconds

### Kingdom Progression
Settlement → Hamlet → Village → Town → Borough → City → Metropolis → Capital → Empire → Legendary Realm

## Tech Stack

- **SwiftUI** — entire UI, animations, and state management
- **Swift Charts** — native data visualizations for activity and mastery tracking
- **UIKit Haptics** — tactile feedback across all key interactions
- **No external dependencies** — runs fully offline
- **No assets required** — all visuals use SF Symbols, emojis, and SwiftUI shapes/gradients
- **Single file architecture** — `KingdomBuilder.swift` contains the complete app

## How to Run

### On iPad (Swift Playgrounds)
1. Open **Swift Playgrounds** on your iPad
2. Create a new App project
3. Replace the default code with `KingdomBuilder.swift`
4. Tap **Run**

### On Mac (Swift Playgrounds)
1. Open **Swift Playgrounds** on your Mac
2. Create a new App project
3. Replace the default code with `KingdomBuilder.swift`
4. Click **Run**

### On Mac (Xcode)
1. Open **Xcode** and create a new App Playground (`.swiftpm`)
2. Replace the content with `KingdomBuilder.swift`
3. Select an iPad simulator and run

## Architecture

```
KingdomBuilder.swift
├── App Entry Point (FocusFlowApp)
├── Haptics Engine (UIKit feedback integration)
├── Data Models
│   ├── TaskPiece, KingdomBuilding, BuildingType
│   ├── ShopCategory (Housing/Economy/Culture/Defense/Nature)
│   ├── TaskHistoryEntry, KnowledgeEntry
│   └── ConfettiParticle, DailyActivityData
├── State Management (KingdomState)
│   ├── Kingdom Stats, XP/Level System
│   ├── AI City Advisor
│   ├── Task History & Knowledge Memory
│   ├── Rich Demo State (pre-loaded buildings, history, knowledge)
│   └── Zone-based Building Placement
├── AI Task Breakdown Engine (TaskAI)
│   ├── 15+ Domain-Specific Breakdowns
│   ├── Action Detection (10 action types)
│   ├── Topic Extraction (NLP stop-word removal)
│   └── Dynamic Step Generation
├── Swift Charts Visualizations
│   ├── DailyActivityChart (7-day bar chart)
│   └── KnowledgeMasteryChart (horizontal mastery bars)
├── Visual Components
│   ├── Custom Shapes (Mountains, Hills, Roads)
│   ├── Animations (Confetti, Clouds, Sparkles, Shield)
│   └── Focus Shield (Anti-Distraction)
├── Kingdom View (Zoned District Layout + Reduce Motion)
├── Building Interior View (Tap-to-Enter)
├── Activity & Knowledge Hub (Charts + History)
├── Kingdom Shop (5-Category Store + Haptics)
├── Focus Timer with Shield + Haptics
├── Quiz System with Knowledge Memory
├── Accessibility (VoiceOver, Reduce Motion, Dynamic Type)
└── Onboarding
```

## What Makes It Different

| Existing Apps | Kingdom Builder |
|---|---|
| Forest: tree grows passively | You **choose** what to build and where |
| Freedom: blocks websites | Focus Shield **visualizes** defeating distractions |
| Todoist: plain task lists | AI **breaks down** any topic into study plans |
| Pomodoro apps: just a timer | Timer earns coins for an **interactive economy** |
| Habitica: generic RPG quests | Buildings have **real game mechanics** (income, XP boost, streak protection) |
| Most apps: no data viz | **Swift Charts** show your 7-day activity and mastery progress |
| Most apps: basic accessibility | **Full VoiceOver, Reduce Motion, Dynamic Type** support |

## Screenshots

*Three screenshots should be provided showing:*
1. The main kingdom view with zoned districts and buildings
2. The AI task breakdown with personalized steps
3. The Activity Hub with Swift Charts visualizations

## Author

**Harshini Reddy Dommata**

Built for the Apple Swift Student Challenge 2026.

## License

This project was created as an individual submission for the Swift Student Challenge. All code is original.
