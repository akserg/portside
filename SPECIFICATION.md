# Wharfside — Product Specification

**Version**: 1.1  
**Date**: 2026-07-04  
**Project**: Wharfside — AI-native container manager for apple/container  
**Platform**: macOS 26+ (Apple silicon)  
**Language**: Swift 6 + SwiftUI  
**AI**: Apple FoundationModels (on-device) — see [AI_INTEGRATION.md](AI_INTEGRATION.md)

---

## 1. Executive Summary

Wharfside is a native macOS desktop application for managing containers built on Apple's [`apple/container`](https://github.com/apple/container) runtime (v1.0+). It provides the full management surface expected of a Docker-Desktop-class tool — and differentiates through on-device AI: one-click crash diagnosis, resource advice, and a natural-language command palette, all powered by the FoundationModels framework. No API keys, no cloud; logs and metrics never leave the Mac. Several free GUIs for apple/container exist; the AI layer plus professionally distributed (signed, notarized, auto-updating) releases are Wharfside's positioning.

### Target Audience
- Developers managing containerized applications on macOS
- DevOps engineers using apple/container for local development
- Container enthusiasts wanting a visual management tool
- Technical users who prefer GUI over CLI

### Key Objectives
- ✅ Simplify container management through visual interface
- ✅ Provide real-time monitoring and resource tracking
- ✅ Enable quick container operations (start, stop, delete, exec)
- ✅ Maintain performance and efficiency (lightweight, <30 MB)
- ✅ Ensure seamless integration with apple/container ecosystem
- ✅ Differentiate through on-device AI: crash diagnosis, resource advice, ⌘K natural-language commands
- ✅ Ship signed, notarized releases with auto-update from day one

---

## 2. Architecture Overview

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Wharfside App                       │
│                    (SwiftUI Frontend)                       │
├─────────────────────────────────────────────────────────────┤
│  Views Layer (SwiftUI)                                      │
│  ├── ContainersView          ├── ImagesView                 │
│  ├── VolumesView             ├── BuildsView                 │
│  ├── MachinesView            ├── SettingsView               │
│  └── DashboardView           └── DetailsPanels              │
├─────────────────────────────────────────────────────────────┤
│  ViewModels Layer (MVVM)                                    │
│  ├── ContainerListViewModel  ├── ImageListViewModel         │
│  ├── MachineListViewModel    ├── DashboardViewModel         │
│  ├── SettingsViewModel       └── SharedStateViewModel       │
├─────────────────────────────────────────────────────────────┤
│  Services Layer                                             │
│  ├── ContainerService        ├── ImageService               │
│  ├── MachineService          ├── MonitoringService          │
│  └── PreferencesService                                     │
├─────────────────────────────────────────────────────────────┤
│  Analysis Layer (deterministic — WharfsideAnalysis package) │
│  ├── LogDigestion            ├── PatternClustering          │
│  └── HeuristicEngine (stats, trends, crash loops)           │
├─────────────────────────────────────────────────────────────┤
│  AI Layer (FoundationModels, on-device — AI_INTEGRATION.md) │
│  ├── AIAvailabilityService   ├── LogDiagnosisService        │
│  └── CommandPalette tools + PendingActionQueue              │
├─────────────────────────────────────────────────────────────┤
│  API Client Layer                                           │
│  └── ContainerAPIClient (XPC Communication)                 │
├─────────────────────────────────────────────────────────────┤
│  System Services                                            │
│  ├── container-apiserver     ├── container-runtime-linux    │
│  └── Other background services                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Design Pattern: MVVM

**Model**: Data structures representing containers, images, machines, etc.  
**View**: SwiftUI components for UI rendering  
**ViewModel**: Bridges Model and View, handles business logic and state management  

**Benefits**:
- Testability: ViewModels can be tested independently
- Reusability: ViewModels work across different UI components
- Maintainability: Clear separation of concerns
- Performance: Efficient state updates

### 2.3 Communication Flow

```
User Action
    ↓
SwiftUI View (triggers state update)
    ↓
ViewModel @Published property updated
    ↓
Service Layer processes request
    ↓
ContainerAPIClient sends XPC message
    ↓
container-apiserver (background daemon)
    ↓
Container Runtime
    ↓
Result returned to Service Layer
    ↓
ViewModel updates @Published property
    ↓
SwiftUI View re-renders with new state
```

### 2.4 Key Technologies

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **UI Framework** | SwiftUI | Native macOS, declarative, modern |
| **State Management** | @Observable (Observation framework) | Modern replacement for Combine/@StateObject on macOS 26 |
| **Concurrency** | async/await | Modern Swift concurrency model |
| **API Communication** | ContainerAPIClient | Direct XPC, type-safe |
| **Data Persistence** | UserDefaults, Codable | Simple preferences storage |
| **Networking** | URLSession (HTTP fallback) | Fallback for remote connections |
| **AI** | FoundationModels (`SystemLanguageModel`, `LanguageModelSession`, `@Generable`, tools) | On-device LLM; availability-gated with heuristic fallback |

---

## 3. Core Features (Phase 1)

### 3.1 Application Structure

#### Main Window Layout
```
┌─────────────────────────────────────────────────────────────┐
│  📦 Wharfside                  🔍  ⚙️  🔔  ☰         │
├──────────────┬──────────────────────────────────────────────┤
│              │                                               │
│  🐳 Containers (nav)                  CPU: 0.01% / 1200%    │
│  📦 Images                            MEM: 249.6MB / 7.47GB │
│  💾 Volumes                           [Show charts]          │
│  🔨 Builds                                                   │
│  🖥️ Machines                         🔍 Search    ≡ ●       │
│  ⚙️ Settings                                                │
│              ├─ Name ─ Container ID ─ Image ─ Ports ─ ...  │
│              │ splash-whale 43218j... free-willy 8000:8000  │
│              │ barnacle-bob 70398a... bikini-bottom    -    │
│              │ yarr-matey    87324g... blue-beard      -    │
│              │                                               │
│              │                                               │
│              │                                               │
│              │ Engine running  RAM 2.2GB  CPU 0.22%         │
└──────────────┴──────────────────────────────────────────────┘
```

#### Navigation Sidebar
- **Width**: 240px (collapsible)
- **Items**: 6 main sections
- **Current selection**: Highlighted with blue background
- **Icons**: SF Symbols for consistent styling

### 3.2 Dashboard View

**Purpose**: Quick overview of system health and container status  

**Components**:
1. **System Status Bar** (top of content area)
   - CPU usage gauge: `X.XX% / YYY%` (used / allocated)
   - Memory gauge: `XXX.XMB / Y.YY GB` (used / total)
   - Service status indicator: Green (running) / Red (stopped)
   - "Show charts" button links to detailed analytics

2. **Quick Stats**
   - Total containers: running / total
   - Total images: count
   - Recent activity: last container created/started

3. **At-a-Glance Containers**
   - Mini-list showing recently active containers
   - Status badges (🟢 running, ⚪ stopped, 🟡 paused)

### 3.3 Containers View

**Purpose**: Comprehensive container management interface  

#### Features

**Table Columns**:
| Column | Type | Example |
|--------|------|---------|
| Status | Badge | 🟢 Running |
| Name | String | `my-web-app` |
| Container ID | Monospace (shortened) | `a1b2c3d4` |
| Image | String (clickable) | `nginx:latest` |
| Port(s) | String | `8080:80, 3000:3000` |
| Last Started | Relative time | `2 hours ago` |
| CPU % | Percentage | `12.5%` |
| Memory % | Percentage | `256MB` |
| Actions | Buttons/Menu | ▶ ⋯ 🗑 |

**Controls**:

1. **Search Bar**
   - Real-time filtering by name, image, ID
   - Debounced to avoid excessive re-renders
   - Placeholder: "Search containers..."

2. **Filter Toggle**
   - "Only show running containers" checkbox
   - Optional dropdown: All / Running / Stopped / Paused

3. **Bulk Actions**
   - "Start All" button (if any stopped)
   - "Stop All" button (if any running)
   - Confirmation dialog before destructive actions

4. **Individual Container Actions**

   **Hover State**: Show action buttons
   ```
   my-app  a1b2c3... nginx:1.0  8080:80  2h ago  5%  [▶ ⋯ 🗑]
   ```

   **Action Menu** (⋯ button):
   - Start (if stopped)
   - Stop (if running)
   - Pause / Unpause
   - Restart
   - Kill (force stop)
   - Exec/Open Terminal
   - View Logs
   - Inspect
   - Delete (with confirmation)

5. **Right-Click Context Menu**
   - Same actions as action menu
   - Quick access without mouse hover

**Details Panel** (on selection):
- Opens side panel or modal
- Shows full container inspection data
- JSON editor view
- Port bindings, environment variables, volumes
- Live update as container state changes

#### State Badges
- 🟢 **Running**: Container is executing
- ⚪ **Stopped**: Container exited or never started
- 🟡 **Paused**: Container paused — only if apple/container exposes pause; verify in M0 XPC spike, otherwise drop the state
- 🔴 **Error**: Last start/run failed

### 3.4 Images View

**Purpose**: Manage container images  

#### Features

**Table Columns**:
| Column | Type | Example |
|--------|------|---------|
| Repository | String | `nginx` |
| Tag | String | `latest`, `1.24-alpine` |
| Image ID | Monospace (shortened) | `sha256:a1b2...` |
| Size | Formatted | `142.3 MB` |
| Created | Relative time | `3 weeks ago` |
| Actions | Buttons/Menu | ⋯ 🗑 |

**Controls**:

1. **Search/Filter**
   - Search by repository, tag, ID
   - Filter by: Local / Remote (from registry)

2. **Primary Actions**
   - **Pull**: Search registry and pull image
   - **Build**: Select Dockerfile and build
   - **Import**: Import from file

3. **Image Menu** (⋯):
   - Tag / Rename
   - Push to registry
   - Copy image ID
   - Inspect (view full details)
   - Delete (with confirmation)
   - Export

4. **Bulk Actions**
   - Select multiple images
   - Delete multiple
   - Export multiple

### 3.5 Volumes View

**Purpose**: Manage persistent volumes  

#### Features

**Table Columns**:
| Column | Type | Example |
|--------|------|---------|
| Name | String | `data-volume` |
| Mount Point | Path | `/var/lib/docker/volumes/data-volume/_data` |
| Size | Formatted | `2.5 GB` |
| Created | Date | `Jun 1, 2026` |
| Actions | Buttons/Menu | ⋯ 🗑 |

**Controls**:

1. **Create Volume**
   - Dialog: Volume name, driver options
   - Create button

2. **Volume Details**
   - Mount point information
   - Size on disk
   - Containers using this volume
   - Modification date

3. **Volume Menu** (⋯):
   - Inspect
   - Open in Finder
   - Delete (with warning about containers)

4. **Bulk Operations**
   - Delete multiple volumes
   - Batch rename

### 3.6 Builds View

**Purpose**: Track and manage container image builds  

#### Features

**Build Queue/History**:
| Column | Type | Example |
|--------|------|---------|
| Status | Badge | ✓ Completed |
| Image | String | `my-app:v1.0` |
| Dockerfile | Path | `./Dockerfile` |
| Duration | Time | `2m 34s` |
| Started | Time | `10:30 AM` |
| Actions | Buttons | ◼ 📋 ⋯ |

**Status Indicators**:
- 🟢 **Completed**: Build finished successfully
- 🟡 **Building**: Build in progress (with progress bar)
- 🔴 **Failed**: Build failed
- ⚪ **Queued**: Waiting to start

**Controls**:

1. **Build Dialog**
   - Dockerfile path selector
   - Image name input
   - Build context (default: Dockerfile directory)
   - Build arguments/flags
   - "Build" button

2. **Build Details**
   - Real-time log output
   - Progress bar
   - Cancel button (if building)

3. **Build History**
   - Filter by status
   - Sort by date/duration
   - Search by image name

4. **Build Menu** (⋯):
   - View logs
   - Rebuild with same settings
   - Copy image name
   - Delete build history

### 3.7 Machines View

**Purpose**: Manage persistent container machines  

#### Features

**Machine List**:
| Column | Type | Example |
|--------|------|---------|
| Status | Badge | 🟢 Running |
| Name | String | `ubuntu-dev` |
| Image | String | `ubuntu:22.04` |
| CPUs | Count | `8` |
| Memory | Formatted | `16 GB` |
| Disk | Formatted | `75 GB` |
| IP Address | IP | `192.168.71.15` |
| Actions | Buttons | ⋯ 🗑 |

**Controls**:

1. **Create Machine**
   - Dialog form:
     - Machine name
     - Base image (dropdown)
     - CPU allocation (spinner)
     - Memory allocation (slider/input)
     - Disk size (spinner)
   - "Create" button

2. **Machine Operations**
   - Start: Launch machine
   - Stop: Graceful shutdown
   - Restart: Stop + Start
   - Delete: Remove machine (with confirmation)

3. **Machine Details**
   - Full resource specifications
   - IP address and network settings
   - Uptime
   - Associated containers

4. **SSH/Terminal**
   - "Open Terminal" button
   - SSH command suggested
   - Keyboard shortcut (⌘T)

5. **Machine Menu** (⋯):
   - Configure resources (edit CPU/memory)
   - SSH command (copy to clipboard)
   - Inspect (full details)
   - Delete

### 3.8 Settings View

**Purpose**: Application preferences and configuration  

#### Sections

**1. General**
- ☐ Start Wharfside at login
- ☐ Show in menu bar
- ☐ Check for updates automatically
- 📌 Update Interval: (Every day / Every week / Manual)

**2. Resources**
- Default CPU allocation: [slider] 1-16 CPUs
- Default Memory: [slider] 512MB - total system memory
- Default Disk: [input] GB
- "Apply as defaults for new containers/machines"

**3. Advanced**
- Log Level: [dropdown] Error / Warning / Info / Debug
- API Connection:
  - Service Status: 🟢 Connected / 🔴 Disconnected
  - Service Location: Unix socket (default)
  - Custom endpoint: [toggle + input]
- Data Location: [path input]
- "Reset to Defaults" button

**4. About**
- Application version: v1.0.0
- Build: 42
- Commit: abc123def
- Check for updates: [button]
- GitHub link
- Report issue: [link]
- License: MIT

**5. Privacy & Security**
- ☐ Send anonymous usage statistics
- ☐ Allow crash reporting
- ☐ Pre-release updates

---

## 4. Advanced Features (Phase 2)

### 4.1 Container Details Panel

**Trigger**: Click container name or "Inspect" action  

**Content Tabs**:

1. **Overview**
   - Container ID (full + copyable)
   - Image
   - Status
   - Created time
   - Started time
   - Exit status (if stopped)

2. **Ports**
   - Published ports (host:container)
   - Protocol (TCP/UDP)
   - Copy to clipboard button

3. **Volumes**
   - Mounted volumes
   - Volume name
   - Container path
   - Host path (if available)

4. **Environment**
   - Environment variables table
   - Search within variables
   - Copy variable values

5. **Network**
   - Connected networks
   - IP addresses
   - Gateway information
   - DNS settings

6. **JSON**
   - Full container inspection output
   - Syntax highlighting
   - Search/filter
   - Copy all button

### 4.2 Real-Time Logs

**Trigger**: "View Logs" action or dedicated tab  

**Features**:

1. **Log Viewer**
   - Real-time streaming output
   - Autoscroll (with manual control)
   - Timestamp for each line
   - Line numbers (optional)

2. **Controls**
   - Search/filter in logs
   - Case-sensitive toggle
   - Follow tail (live mode)
   - Clear logs button
   - Export logs (save to file)

3. **Log Levels** (if applicable)
   - Color-coded: Error, Warn, Info, Debug
   - Filter by level

4. **Performance**
   - Buffer recent logs (last 10k lines)
   - Virtualized rendering for large logs
   - Background thread for streaming

### 4.3 Terminal/Exec

**Trigger**: "Open Terminal" or "Exec" action  

**Features**:

1. **Integrated Terminal**
   - Full terminal emulator
   - Command history (↑/↓)
   - Working directory context
   - User indicator (root vs regular)

2. **Pre-filled Commands**
   - `/bin/sh` by default
   - Customizable startup command
   - Environment vars ready

3. **Terminal Preferences**
   - Font selection (monospace)
   - Font size
   - Color scheme (light/dark)
   - Scrollback buffer size

### 4.4 Resource Monitoring

**Trigger**: "Show charts" button in dashboard  

**Charts**:

1. **CPU Usage Over Time**
   - Line chart: CPU % vs time
   - Time ranges: 1h / 24h / 7d
   - Per-container breakdown

2. **Memory Usage Over Time**
   - Line chart: Memory vs time
   - Stacked area chart (all containers)
   - Time ranges: same as CPU

3. **Disk I/O**
   - Read/write throughput
   - Historical data

4. **Network I/O**
   - Upload/download speeds
   - Per-container if applicable

**Implementation**:
- Use Apple's built-in Swift Charts framework
- Efficient data point sampling for large time ranges
- Background update task

### 4.5 Notifications

**System Integration**:
- macOS Notification Center integration
- Sound alerts (configurable)
- Action buttons (open app, acknowledge)

**Event Types**:
- Container state changes
- Build completed (success/failure)
- Resource limits exceeded
- Errors and warnings

---

## 5. Technical Specifications

### 5.1 Project Structure

```
wharfside/
├── Sources/
│   └── Wharfside/
│       ├── App/
│       │   ├── WharfsideApp.swift
│       │   ├── AppDelegate.swift
│       │   └── SceneDelegate.swift
│       ├── Views/
│       │   ├── MainView.swift
│       │   ├── Sidebar.swift
│       │   ├── Containers/
│       │   │   ├── ContainersView.swift
│       │   │   ├── ContainerRowView.swift
│       │   │   ├── ContainerDetailsView.swift
│       │   │   └── ContainerActionsMenu.swift
│       │   ├── Images/
│       │   ├── Volumes/
│       │   ├── Builds/
│       │   ├── Machines/
│       │   ├── Settings/
│       │   └── Shared/
│       │       ├── SearchBar.swift
│       │       ├── LoadingView.swift
│       │       ├── ErrorView.swift
│       │       └── StatusBadge.swift
│       ├── ViewModels/
│       │   ├── ContainerListViewModel.swift
│       │   ├── ImageListViewModel.swift
│       │   ├── MachineListViewModel.swift
│       │   ├── DashboardViewModel.swift
│       │   ├── SettingsViewModel.swift
│       │   └── AppState.swift
│       ├── Services/
│       │   ├── ContainerService.swift
│       │   ├── ImageService.swift
│       │   ├── VolumeService.swift
│       │   ├── MachineService.swift
│       │   ├── MonitoringService.swift
│       │   ├── PreferencesService.swift
│       │   └── NotificationService.swift
│       ├── AI/
│       │   ├── AIAvailabilityService.swift
│       │   ├── LogDiagnosisService.swift
│       │   ├── GenerableModels.swift
│       │   └── Palette/ (Tools, PendingActionQueue — Phase 3)
│       ├── Models/
│       │   ├── Container.swift
│       │   ├── Image.swift
│       │   ├── Volume.swift
│       │   ├── Machine.swift
│       │   ├── Build.swift
│       │   └── SystemStatus.swift
│       ├── Utilities/
│       │   ├── Extensions.swift
│       │   ├── Formatters.swift
│       │   ├── Constants.swift
│       │   └── Logger.swift
│       └── Resources/
│           ├── Localizable.strings
│           ├── Assets.xcassets
│           └── Colors.xcassets
├── Tests/
│   ├── WharfsideTests/
│   │   ├── ViewModels/
│   │   ├── Services/
│   │   ├── Models/
│   │   └── Mocks/
│   └── WharfsideUITests/
│       └── *.swift
├── Packages/
│   └── WharfsideAnalysis/        # pure-Swift log digestion + heuristics (no app deps)
├── Package.swift
├── SPECIFICATION.md
├── PLAN.md
├── AI_INTEGRATION.md
├── README.md
├── CONTRIBUTING.md
└── LICENSE
```

### 5.2 Dependencies

**System Frameworks** (built-in macOS):
```swift
import Foundation
import SwiftUI
import Combine
import AppKit
import UserNotifications
```

**System Frameworks (additional)**:
```swift
import FoundationModels   // on-device AI (macOS 26+)
import Charts             // Swift Charts — built-in, no third-party charting needed
import Observation        // @Observable state management
```

**External Dependencies** (keep this list ruthlessly short):
```swift
// In Package.swift
.package(url: "https://github.com/apple/container.git", from: "1.0.0"),   // ContainerAPIClient (XPC)
.package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),

// Phase 2+ only:
// .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", ...)   // embedded terminal
// Sparkle for auto-update (decision tracked in M1 issues)
```

Note: swift-argument-parser is not needed (GUI app, not a CLI); charting uses Apple's built-in Swift Charts, not third-party libraries.

### 5.3 Data Models

#### Container
```swift
struct Container: Identifiable, Codable {
    let id: String
    let name: String
    let imageId: String
    let imageName: String
    let status: ContainerStatus
    let state: ContainerState
    let ports: [PortBinding]
    let volumes: [VolumeMount]
    let environment: [String: String]
    let createdAt: Date
    let startedAt: Date?
    let exitCode: Int?
    
    enum Status: String {
        case running, stopped, paused, exited, error
    }
}

struct PortBinding: Identifiable, Codable {
    let id: String // "8080/tcp"
    let hostIp: String
    let hostPort: String
    let containerPort: String
    let `protocol`: String // "tcp" or "udp"
}

struct ContainerStats: Codable {
    let cpuPercent: Double
    let memoryUsage: UInt64
    let memoryLimit: UInt64
    let networkIn: UInt64
    let networkOut: UInt64
}
```

#### Image
```swift
struct Image: Identifiable, Codable {
    let id: String
    let repository: String
    let tag: String
    let size: UInt64
    let createdAt: Date
    let digest: String
}
```

#### Machine
```swift
struct Machine: Identifiable, Codable {
    let id: String
    let name: String
    let image: String
    let status: MachineStatus
    let cpus: Int
    let memory: UInt64 // in bytes
    let disk: UInt64 // in bytes
    let ipAddress: String?
    let createdAt: Date
    let startedAt: Date?
    
    enum Status: String {
        case running, stopped, error
    }
}
```

#### SystemStatus
```swift
struct SystemStatus: Codable {
    let serviceRunning: Bool
    let cpuUsage: Double // 0-100
    let cpuCount: Int
    let memoryUsage: UInt64
    let memoryTotal: UInt64
    let diskUsage: UInt64
    let diskTotal: UInt64
    let containerCount: Int
    let runningContainers: Int
    let imageCount: Int
}
```

### 5.4 State Management

#### AppState (Global State)

```swift
@MainActor
class AppState: ObservableObject {
    @Published var isServiceRunning: Bool = false
    @Published var systemStatus: SystemStatus?
    @Published var selectedTab: NavigationTab = .containers
    
    enum NavigationTab: Hashable {
        case containers, images, volumes, builds, machines, settings
    }
}
```

#### ViewModel Pattern

```swift
@MainActor
@Observable
final class ContainerListViewModel {
    var containers: [Container] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var searchText: String = ""
    var showRunningOnly: Bool = false

    private let service: any ContainerServicing
    private var pollTask: Task<Void, Never>?

    init(service: any ContainerServicing) {
        self.service = service
    }

    func startPolling() {
        pollTask = Task {
            while !Task.isCancelled {
                await refreshContainers()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() { pollTask?.cancel() }
    
    func refreshContainers() async {
        isLoading = true
        do {
            containers = try await service.listContainers()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    var filteredContainers: [Container] {
        containers
            .filter { showRunningOnly ? $0.status == .running : true }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
```

### 5.5 Service Layer

#### ContainerService

All runtime access goes through a protocol so ViewModels are testable with mocks and
the implementation can switch between XPC (`ContainerAPIClient`) and CLI fallback:

```swift
protocol ContainerServicing: Sendable {
    func listContainers() async throws -> [Container]
    func startContainer(_ id: String) async throws
    func stopContainer(_ id: String, timeout: TimeInterval) async throws
    func getContainerStats(_ id: String) async throws -> ContainerStats
    func deleteContainer(_ id: String, force: Bool) async throws
    func execContainer(id: String, command: [String]) async throws -> String
}

actor ContainerService: ContainerServicing {
    private let apiClient: ContainerAPIClient
    
    func listContainers() async throws -> [Container] {
        let options = ContainerListOptions()
        return try await apiClient.list(options: options)
    }
    
    func startContainer(_ id: String) async throws {
        try await apiClient.start(id: id)
    }
    
    func stopContainer(_ id: String, timeout: TimeInterval = 10) async throws {
        let options = ContainerStopOptions(timeoutInSeconds: Int(timeout))
        try await apiClient.stop(id: id, options: options)
    }
    
    func getContainerStats(_ id: String) async throws -> ContainerStats {
        try await apiClient.statistics(id: id)
    }
    
    func deleteContainer(_ id: String, force: Bool = false) async throws {
        try await apiClient.delete(id: id, force: force)
    }
    
    func execContainer(id: String, command: [String]) async throws -> String {
        try await apiClient.exec(id: id, command: command)
    }
}
```

### 5.6 XPC Integration

**Communication Protocol**:

```swift
// Using ContainerAPIClient from apple/container
let client = ContainerAPIClient()

// Create container
try await client.create(
    configuration: ContainerConfiguration(id: "my-app"),
    kernel: kernel,
    options: .default
)

// List containers
let containers = try await client.list(options: ContainerListOptions())

// Get statistics
let stats = try await client.statistics(id: "container-id")
```

### 5.7 Concurrency Model

**Async/Await Pattern**:

```swift
// View initiating action
struct ContainerListView: View {
    @State var viewModel: ContainerListViewModel
    
    var body: some View {
        List(viewModel.filteredContainers) { container in
            ContainerRowView(container: container)
                .onTapGesture {
                    Task {
                        await handleStartContainer(container)
                    }
                }
        }
    }
    
    private func handleStartContainer(_ container: Container) async {
        await viewModel.startContainer(container.id)
    }
}

// ViewModel handling async operations
@MainActor
class ContainerListViewModel: ObservableObject {
    func startContainer(_ id: String) async {
        do {
            try await service.startContainer(id)
            await refreshContainers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

**Background Updates**:

```swift
// Continuous polling with task cancellation
@MainActor
class MonitoringViewModel: ObservableObject {
    private var updateTask: Task<Void, Never>?
    
    func startMonitoring() {
        updateTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
    }
    
    func stopMonitoring() {
        updateTask?.cancel()
    }
}
```

### 5.8 Error Handling

**Custom Error Types**:

```swift
enum WharfsideError: LocalizedError {
    case serviceNotRunning
    case connectionFailed(String)
    case invalidOperation(String)
    case containerNotFound(String)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .serviceNotRunning:
            return "Container service is not running"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .containerNotFound(let id):
            return "Container not found: \(id)"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
```

**Retry Logic**:

```swift
func withRetry<T>(maxAttempts: Int = 3, delay: TimeInterval = 1.0, operation: () async throws -> T) async throws -> T {
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(delay * Double(attempt) * 1_000_000_000))
            }
        }
    }
    
    throw lastError ?? WharfsideError.apiError("Unknown error")
}
```

---

## 6. UI/UX Design Guidelines

### 6.1 Visual Style

**Color Palette**:
- **Primary**: Blue (#007AFF) - CTA buttons, active states
- **Success**: Green (#34C759) - Running containers
- **Warning**: Orange (#FF9500) - Warnings, builds in progress
- **Error**: Red (#FF3B30) - Errors, stopped state
- **Neutral**: Gray (#999999) - Disabled, secondary text
- **Background**: System (light/dark mode aware)

**Typography**:
- **Title**: SF Pro Display, 18pt, bold
- **Subtitle**: SF Pro Text, 13pt, medium
- **Body**: SF Pro Text, 11pt, regular
- **Monospace**: Menlo, Monaco, 10pt (for IDs, ports)

**Icons**:
- Use SF Symbols exclusively for consistency
- Weight: "regular" (default)
- Size scales automatically with text

### 6.2 macOS Human Interface Guidelines Compliance

✅ Follow official Apple HIG:
- Respect system preferences (dark mode, dynamic type)
- Use native controls (NSButton, NSTable, etc. via SwiftUI)
- Consistent keyboard navigation
- Focus indicators for accessibility
- Natural language and terminology

### 6.3 Interaction Patterns

**Hover Effects**:
- Buttons: Subtle scale/highlight
- Table rows: Background highlight on hover
- Links: Underline on hover

**Click Feedback**:
- Button press: Slight depression animation
- Action completion: Brief toast notification
- Loading states: Spinner during operations

**Keyboard Shortcuts**:
| Shortcut | Action |
|----------|--------|
| ⌘N | New container |
| ⌘R | Refresh |
| ⌘, | Open Settings |
| ⌘W | Close window |
| ⌘Q | Quit app |
| Space | Play/pause container |
| Delete | Delete selected item |
| ⌘T | Open terminal |

**Confirmation Dialogs**:
```
┌─────────────────────────────────────┐
│  Delete container?                   │
│  This action cannot be undone.       │
│  Container: my-app (a1b2c3d4)        │
│                                      │
│            [Cancel]  [Delete]        │
└─────────────────────────────────────┘
```

### 6.4 Responsive Design

**Breakpoints**:
- **Narrow** (<600px): Sidebar collapses, single column
- **Medium** (600-1000px): Sidebar collapsible, full features
- **Wide** (>1000px): Sidebar always visible, side panels available

**Minimum Window Size**: 800 x 600px

---

## 7. Performance Considerations

### 7.1 Optimization Strategies

**View Rendering**:
- Lazy list rendering for large container lists
- View model memoization (@StateObject)
- Avoid expensive computations in body property
- Use `.id()` modifier for list items

**Data Fetching**:
- Debounced search (300ms delay)
- Incremental list updates (delta) when possible
- Background refresh tasks
- Pagination for large datasets

**Memory Management**:
- Cancel background tasks on view deinit
- Release large data structures promptly
- Use weak references in closures
- Limit log buffering (keep last 10k lines)

**Caching**:
- Cache container list for 2 seconds
- Cache image metadata for 5 seconds
- Persistent cache for user preferences
- TTL-based invalidation

### 7.2 Expected Performance Metrics

| Metric | Target | Notes |
|--------|--------|-------|
| App startup | <1 second | Cold start |
| Container list load | <500ms | 50 containers |
| Search results | <100ms | Debounced |
| Tab switch | <200ms | Instant in cache |
| Memory usage | <100 MB | At rest, idle |
| CPU usage (idle) | <1% | System monitoring |

---

## 8. Testing Strategy

### 8.1 Unit Tests

**ViewModels**:
```swift
class ContainerListViewModelTests: XCTestCase {
    func testFilterContainersBySearchText() {
        let viewModel = ContainerListViewModel(service: MockContainerService())
        viewModel.containers = [
            Container(id: "1", name: "web-app", ...),
            Container(id: "2", name: "database", ...),
        ]
        
        viewModel.searchText = "web"
        
        XCTAssertEqual(viewModel.filteredContainers.count, 1)
        XCTAssertEqual(viewModel.filteredContainers[0].name, "web-app")
    }
}
```

**Services**:
```swift
// Swift Testing (preferred on macOS 26 toolchain)
@Test func startContainerSuccess() async throws {
    let mockClient = MockContainerAPIClient()
    let service = ContainerService(apiClient: mockClient)

    try await service.startContainer("container-id")   // throws → test fails

    #expect(mockClient.startWasCalled)
}
// Note: XCTAssertNoThrow does not support async closures — do not use it with async calls.
```

### 8.2 Integration Tests

```swift
class ContainerServiceIntegrationTests: XCTestCase {
    func testCreateAndStartContainer() async {
        let service = ContainerService(apiClient: realAPIClient)
        
        // Create container
        try await service.createContainer(configuration: testConfig)
        
        // Start container
        try await service.startContainer("test-container")
        
        // Verify running
        let containers = try await service.listContainers()
        XCTAssertTrue(containers.first?.status == .running)
    }
}
```

### 8.3 UI Tests

```swift
class ContainerViewUITests: XCTestCase {
    let app = XCUIApplication()
    
    func testStartContainerFromUI() {
        app.launch()
        
        app.tables["ContainerList"].cells.firstMatch.rightClick()
        app.menuItems["Start"].click()
        
        XCTAssertTrue(app.staticTexts["Running"].exists)
    }
}
```

### 8.4 Mock Services

Actors cannot be subclassed — mocks conform to the `ContainerServicing` protocol instead:

```swift
final class MockContainerService: ContainerServicing, @unchecked Sendable {
    var containers: [Container] = []
    private(set) var listWasCalled = false

    func listContainers() async throws -> [Container] {
        listWasCalled = true
        return containers
    }
    // remaining protocol methods record calls / return fixtures
}
```

---

## 9. Distribution & Deployment

### 9.1 Build Configuration

**Xcode Project Structure**:
- **Minimum Deployment Target**: macOS 26
- **Build Configuration**: Debug / Release
- **Code Signing**: Automatic (Apple Developer ID)

**Release Build**:
```bash
xcodebuild -scheme Wharfside -configuration Release \
    -derivedDataPath build \
    -archivePath build/Wharfside.xcarchive archive
```

### 9.2 Packaging

**DMG Installer**:
```
Wharfside-1.0.0.dmg
├── Wharfside.app
├── Applications (symlink)
└── README.txt
```

**Notarization** (Gatekeeper) — `altool` is discontinued; use `notarytool`:
```bash
xcrun notarytool submit Wharfside-1.0.0.dmg \
    --keychain-profile "wharfside-notary" \
    --wait
xcrun stapler staple Wharfside-1.0.0.dmg
```
(One-time setup: `xcrun notarytool store-credentials "wharfside-notary" --apple-id <id> --team-id <team> --password <app-specific-password>`.)

### 9.3 Auto-Update

**Sparkle Framework** (optional):
- Publish releases with `.dmg` on GitHub
- Update feed with version info
- In-app notification of new versions
- Auto-download and install

### 9.4 Distribution Channels

1. **GitHub Releases**: Direct download
2. **Homebrew**: `brew install wharfside/wharfside/wharfside` (own tap first; main homebrew-cask once established)
3. **Mac App Store**: (future consideration)
4. **Website**: wharfside.app

---

## 10. Accessibility (A11y)

### 10.1 VoiceOver Support

- All interactive elements have descriptive labels
- Use `.accessibilityLabel()` and `.accessibilityHint()`
- Images/icons have alt text
- Color not sole means of conveying information

### 10.2 Keyboard Navigation

- Tab through all controls
- Enter/Space to activate buttons
- Arrow keys for list navigation
- Escape to dismiss dialogs
- Focus indicators visible

### 10.3 Dynamic Type

- Text scales with system preferences
- Minimum font sizes respected
- Layouts adjust for larger text

### 10.4 Color Contrast

- Minimum 4.5:1 contrast ratio for text
- UI controls have visible focus indicators
- Color blindness support (patterns + color)

---

## 11. Security Considerations

### 11.1 XPC Communication

- ✅ Use authenticated XPC connections
- ✅ Validate all messages from API server
- ✅ Handle timeout errors gracefully
- ✅ Secure credential storage (Keychain for future features)

### 11.2 User Data

- ✅ Preferences stored securely (UserDefaults + Keychain if needed)
- ✅ No sensitive data in logs
- ✅ Clear sensitive data on app quit

### 11.3 Code Signing

- ✅ Sign all binaries with Apple Developer ID
- ✅ Enable hardened runtime
- ✅ Request minimal permissions

---

## 12. Documentation

### 12.1 Code Documentation

```swift
/// Refreshes the list of containers from the API.
///
/// - Throws: `WharfsideError` if the API call fails
/// - Note: This method is called automatically every 2 seconds
func refreshContainers() async throws {
    // Implementation
}
```

### 12.2 User Documentation

- **README.md**: Quick start guide
- **User Guide**: Feature descriptions, screenshots
- **FAQ**: Common questions
- **Troubleshooting**: Known issues and solutions

### 12.3 Developer Documentation

- **Architecture.md**: System design
- **Contributing.md**: Development setup
- **API.md**: Internal API documentation

---

## 13. Timeline & Milestones

The authoritative plan lives in [PLAN.md](PLAN.md) (milestones M0–M3 with issue-level
breakdown, mirrored as GitHub milestones/issues). Summary:

**M0 — Foundation (~2 weeks)**: Xcode scaffold, CI, XPC capability spike,
`ContainerServicing` protocol with XPC + CLI implementations, `AIAvailabilityService`,
app shell, landing page.

**M1 — MVP 0.1 (~5–6 weeks)**: Containers, Images, Logs views done well; log digestion
pipeline; `@Generable` crash diagnosis with streaming card; signing + notarization
pipeline; Homebrew tap; public launch. *Hero feature: "Explain this crash."*

**M2 — Depth 0.2 (~4–5 weeks)**: Volumes, Machines, Dashboard (Swift Charts), heuristic
engine + AI advice tier, exec shell (SwiftTerm).

**M3 — Command Palette 0.3 (~4–6 weeks)**: ⌘K natural-language palette with
FoundationModels tool calling and confirmation queue; multi-container correlation;
docs site.

Builds view and notifications from the original spec are deferred past 0.3 — scope
control favors the AI differentiator over feature breadth.

---

## 14. Success Criteria

### M1 (public 0.1)
- ✅ Core container operations functional (Containers, Images, Logs)
- ✅ Crash diagnosis produces a useful, typed result on fixture and real containers
- ✅ Graceful degraded mode verified with Apple Intelligence disabled
- ✅ Notarized artifact installable via Homebrew tap
- ✅ <30 MB binary size
- ✅ <100 MB memory usage
- ✅ Launch time <1 second
- ✅ 80% code test coverage

### M2–M3
- ✅ Monitoring, heuristics (labeled honestly), and AI advice tier working
- ✅ Command palette: zero unconfirmed mutations in test harness
- ✅ 80%+ coverage on WharfsideAnalysis package (the correctness core)

### Release Readiness
- ✅ Code signed and notarized
- ✅ Distributed via GitHub/Homebrew
- ✅ Documentation complete
- ✅ Zero critical bugs
- ✅ Performance benchmarks met

---

## 15. Future Enhancements

1. **Docker Compatibility Mode**: Support both apple/container and Docker
2. **Cloud Integration**: Manage remote containers
3. **CI/CD Integration**: Webhook support for automated builds
4. **Container Orchestration**: Compose file support
5. **Analytics**: Historical stats and trends
6. **Team Collaboration**: Share settings/configurations
7. **Plugins**: Extensibility system
8. **Web UI**: Browser-based management interface

---

## Appendix A: Keyboard Shortcuts

```
Global
  ⌘N      New container
  ⌘R      Refresh
  ⌘,      Preferences
  ⌘Q      Quit
  ⌘W      Close window

Containers View
  Space   Play/Pause
  Delete  Delete selected
  ⌘T      Terminal

Search
  ⌘F      Focus search
  Escape  Clear search

Lists
  ↑↓      Navigate
  ↵       Activate
  Space   Toggle selection
```

---

## Appendix B: Error Messages

| Error | User Message | Solution |
|-------|-------------|----------|
| XPC connection failed | "Cannot connect to container service" | Restart app or run `container system start` |
| Container not found | "Container no longer exists" | Refresh list (⌘R) |
| Invalid configuration | "Invalid container configuration" | Check settings and retry |
| Permission denied | "You don't have permission to perform this action" | Run with admin or check permissions |

---

## Appendix C: Release Notes Template

```
# Wharfside v1.0.0

## New Features
- 🎉 Initial release
- Core container management UI
- Real-time monitoring dashboard
- Image and volume management

## Improvements
- Optimized performance
- Improved error handling

## Bug Fixes
- Fixed list rendering lag
- Corrected status indicators

## Known Issues
- Large logs (>100k lines) may display slowly

## Upgrade Notes
- Requires macOS 26+ (Apple silicon)
- Requires apple/container v1.0+
```

---

**Document Version**: 1.1  
**Last Updated**: 2026-07-04  
**Status**: Ready for Development