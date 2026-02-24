# Kingdom Builder — Focus Flow

A gamified focus app that turns overwhelming tasks into an interactive kingdom-building experience. Built entirely with SwiftUI for the **Apple Swift Student Challenge 2026**.

## What It Does

Students type **or speak** any task — "study for biology exam", "learn statistics", "practice guitar" — and an **on-device AI engine** breaks it into focused sessions. Each completed session earns coins that players spend in the Kingdom Shop to build their own city with structured districts, interactive buildings, and a growing economy.

**Designed for everyone** — including blind and visually impaired users who can use the entire app through voice input and text-to-speech, start to finish.

## Key Features

### AI Task Breakdown (Works for Any Topic)
- On-device NLP extracts the **action** (learn, build, write, practice, memorize...) and **subject** from any input
- 15+ expert-curated domains (biology, chemistry, physics, history, languages, music, art, coding, etc.)
- Dynamic step generation for topics not in the curated list
- Editable task names — rename any AI-generated step to fit your needs
- Manual task addition for quick custom entries

### Voice Input (Speech-to-Text)
- **Microphone button** on the task input screen — tap and speak your task
- Uses Apple's `SFSpeechRecognizer` with **on-device recognition** (no internet needed)
- Real-time transcription — see your words appear as you speak
- Visual pulse indicator shows when the app is listening
- Accessible to blind users: announces "Listening... say your task now" when activated

### Interactive Kingdom Building
- **5 Building Categories**: Housing, Economy, Culture, Defense, Nature
- **20 Unique Buildings**: Cottage → Palace, Market Stall → Bank, Library → Academy, Watchtower → Castle, Garden → Lake
- **Zoned City Layout**: Districts for defense, commerce, housing, culture, and nature
- **Tap-to-Enter Interiors**: Tap any building to see inside with stats, reports, and knowledge maps

### Full Audio Accessibility (Blind User Support)
- **Auto-detects VoiceOver** — speech turns on automatically when VoiceOver is running
- **Spoken onboarding** — the app introduces itself aloud on first launch
- **Screen announcements** — every sheet (shop, activity hub, settings, buildings) announces its content on open
- **Task breakdown read aloud** — AI reads the topic, step count, and every step
- **Timer voice updates** — announces start, 30 seconds, 10 seconds, and completion
- **Rewards announced** — coins earned, group bonuses, level-ups all spoken
- **Building info spoken** — building name, zone, and benefit read when tapped
- **Sound cues** — distinct `SystemSoundID` sounds for coins, completions, building, and level-ups
- **Accessibility Settings panel** — toggle speech and sounds, test each sound, preview the voice

### Coin Economy
- **+10 coins** per completed focus session
- **+50 bonus coins** for completing all tasks in a group
- Quiz rewards scale with understanding and confidence scores
- Economy buildings give a **one-time coin bonus** when collected — each shop/bank pays once, no infinite farming

### Knowledge Memory System
- Tracks every topic with **mastery levels** (Beginner → Expert)
- Quiz scores stored per topic and contribute to mastery
- Knowledge Map in Culture buildings and Activity Hub

### Swift Charts Visualizations
- **7-Day Activity Bar Chart** with gradient fills and annotations
- **Knowledge Mastery Chart** mapping topics to mastery levels
- Built with Apple's native `Charts` framework

### Haptic Feedback
- Tactile feedback on task complete, building purchase, coin collection, level-up, quiz, and timer

### Accessibility Summary
- **Blind users**: Voice input + full text-to-speech + VoiceOver labels on every element
- **Low-vision**: Dynamic Type support, high-contrast gradients
- **Motion-sensitive**: Reduce Motion suppresses all decorative animations
- **Deaf users**: All information is visual — no audio-only content

### People & Citizens
- **Population** from housing buildings (Cottage +2, House +5, Manor +10, Palace +25)
- **Citizens** appear in the kingdom view — up to 12 people (🧑👩🧒👴👵) when you have housing

### 3D-Style Kingdom
- **rotation3DEffect** on all buildings for depth and perspective
- **Shadow** under each building for a grounded look
- **Perspective** on the kingdom container for a subtle 3D tilt

### Kingdom Progression
Starts at **Level 1 (Settlement)**. Progress: Settlement → Hamlet → Village → Town → Borough → City → Metropolis → Capital → Empire → Legendary Realm

## Tech Stack

- **SwiftUI** — UI, animations, state management
- **Swift Charts** — native data visualizations
- **AVFoundation** — `AVSpeechSynthesizer` for text-to-speech
- **Speech** — `SFSpeechRecognizer` for on-device voice input
- **AudioToolbox** — `SystemSoundID` for interaction sounds
- **UIKit** — Haptic feedback generators + `UIAccessibility` detection
- **No external dependencies** — runs fully offline
- **Single file architecture** — `KingdomBuilder.swift`

## How to Run

### On iPad (Swift Playgrounds)
1. Open **Swift Playgrounds** on your iPad
2. Create a new App project
3. Replace the default code with `KingdomBuilder.swift`
4. Tap **Run**

### On Mac (Xcode)
1. Open **Xcode** and create a new App Playground (`.swiftpm`)
2. Replace the content with `KingdomBuilder.swift`
3. Select an iPad simulator and run

## Architecture

```
KingdomBuilder.swift
├── App Entry Point (FocusFlowApp)
├── Haptics Engine (UIKit tactile feedback)
├── Audio Accessibility Engine (AccessibilityAudio)
│   ├── AVSpeechSynthesizer (text-to-speech)
│   ├── SFSpeechRecognizer (voice-to-text input)
│   ├── AudioToolbox SystemSoundID (sound cues)
│   ├── VoiceOver auto-detection
│   └── Context-aware screen announcements
├── Accessibility Settings View
│   ├── Speech & sound toggles
│   ├── Voice input info + permission status
│   └── Sound test buttons + voice preview
├── Data Models
│   ├── TaskPiece, KingdomBuilding, BuildingType
│   ├── ShopCategory, TaskHistoryEntry, KnowledgeEntry
│   └── ConfettiParticle, DailyActivityData
├── State Management (KingdomState)
│   ├── Kingdom Stats, XP/Level, AI Advisor
│   ├── Task History & Knowledge Memory
│   └── Rich Demo State + Zone-based Placement
├── AI Task Breakdown Engine (TaskAI)
│   ├── 15+ Domain Breakdowns
│   ├── Action Detection + Topic Extraction
│   └── Dynamic Step Generation
├── Swift Charts (Activity + Mastery)
├── Kingdom View (Zoned Districts + Reduce Motion)
├── Building Interior (Tap-to-Enter + Audio)
├── Activity & Knowledge Hub (Charts + History)
├── Kingdom Shop (5 Categories + Audio)
├── Focus Timer (Shield + Voice Countdown)
├── Quiz System (Knowledge Memory + Audio)
└── Onboarding (Spoken Introduction)
```

## What Makes It Different

| Existing Apps | Kingdom Builder |
|---|---|
| Forest: passive tree growth | You **choose** what to build and where |
| Freedom: blocks websites | Focus Shield **visualizes** defeating distractions |
| Todoist: plain task lists | AI **breaks down** any topic into study plans |
| Pomodoro: just a timer | Timer earns coins for an **interactive economy** |
| Habitica: generic RPG | Buildings have **real mechanics** (income, XP, shield) |
| No focus app has voice input | **Speak your tasks** with on-device recognition |
| No focus app reads content | **Full text-to-speech** for blind users start to finish |
| Most apps: basic a11y | **VoiceOver + Speech + Sound + Reduce Motion + Voice Input** |

## Accessibility Philosophy

Kingdom Builder was designed so that a blind student can use the entire app from opening to building their kingdom, without ever seeing the screen:
1. **Open the app** → onboarding speaks itself automatically
2. **Create a task** → tap microphone, speak "learn Spanish", AI reads back the study plan
3. **Start a timer** → voice announces start, 30s, 10s, and completion
4. **Earn rewards** → coins and bonuses are spoken aloud
5. **Build kingdom** → shop announces what's available, purchase confirmation is spoken
6. **Track progress** → activity hub announces stats and mastery levels

For sighted users, all audio features can be toggled off in the Accessibility Settings.

## Screenshots

*Three screenshots should be provided showing:*
1. The main kingdom view with zoned districts and buildings
2. The voice input microphone on the AI task breakdown screen
3. The Accessibility Settings panel with speech, sound, and voice input controls

## Author

**Harshini Reddy Dommata**

Built for the Apple Swift Student Challenge 2026.

## License

This project was created as an individual submission for the Swift Student Challenge. All code is original.
