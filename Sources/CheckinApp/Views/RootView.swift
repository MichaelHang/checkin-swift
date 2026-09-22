import SwiftUI
import SwiftData
import CheckinCore

/// Main navigation shell: regular-width windows use `NavigationSplitView` (sidebar + detail);
/// below the compact-width threshold it collapses to a bottom `TabView` (today / calendar /
/// period / stats).
///
/// The soft background gradient (accent-tinted, low saturation) gives the native Liquid
/// Glass sidebar / toolbar / sheets depth to blur without dominating.
enum SidebarSelection: Hashable {
    case today
    case calendar
    case period
    case stats
    // "Backup" is debug-only (JSON export/import for diagnosing data issues); the whole tab
    // is compiled out of Release. In Xcode this relies on SWIFT_ACTIVE_COMPILATION_CONDITIONS
    // = DEBUG on the CheckinApp target; SwiftPM debug builds define -DDEBUG as well.
    #if DEBUG
    case backup
    #endif
}

struct RootView: View {
    @Query(sort: \PersistedTask.createdAt, order: .forward) private var tasks: [PersistedTask]
    @Query private var records: [PersistedCheckinRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var selection: SidebarSelection? = .today
    @State private var width: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                backgroundGradient
                if w < Constants.compactWidthThreshold {
                    compactTabs
                } else {
                    splitView
                }
            }
            .onAppear { width = w }
            .onChange(of: w) { _, newW in width = newW }
        }
        .frame(minWidth: Constants.minWindowWidth, minHeight: Constants.minWindowHeight)
    }

    // MARK: - Wide window: NavigationSplitView

    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        GlassSidebar {
            List(selection: $selection) {
                Label("今日", systemImage: "sun.max.fill").tag(SidebarSelection.today)
                Label("日历", systemImage: "calendar").tag(SidebarSelection.calendar)
                Label("周期", systemImage: "repeat").tag(SidebarSelection.period)
                Label("统计", systemImage: "chart.bar.fill").tag(SidebarSelection.stats)
                #if DEBUG
                Label("备份", systemImage: "externaldrive.fill").tag(SidebarSelection.backup)
                #endif
            }
            .navigationTitle(Constants.appName)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .today {
        case .today: TodayView()
        case .calendar: CalendarView()
        case .period: PeriodView()
        case .stats: StatsView()
        #if DEBUG
        case .backup: BackupView()
        #endif
        }
    }

    // MARK: - Compact window: bottom TabView

    private var compactTabs: some View {
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max.fill") }
            CalendarView()
                .tabItem { Label("日历", systemImage: "calendar") }
            PeriodView()
                .tabItem { Label("周期", systemImage: "repeat") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
            #if DEBUG
            BackupView()
                .tabItem { Label("备份", systemImage: "externaldrive.fill") }
            #endif
        }
    }

    // MARK: - Background (low-saturation accent gradient for depth)

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.16),
                Color.accentColor.opacity(0.06),
                Color.blue.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
