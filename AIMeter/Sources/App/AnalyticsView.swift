import SwiftUI

enum AnalyticsSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case byModel = "By Model"
    case byProject = "By Project"
    case dailyUsage = "Daily Usage"
    case efficiency = "Efficiency"
    case cache = "Cache"
    case prompts = "Prompts"
    case subagents = "Subagents"
    case sessions = "Top Sessions"
    case tools = "Tools"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:   return "chart.pie"
        case .byModel:    return "cpu"
        case .byProject:  return "folder"
        case .dailyUsage: return "calendar"
        case .efficiency: return "bolt"
        case .cache:      return "arrow.triangle.2.circlepath"
        case .prompts:    return "text.bubble"
        case .subagents:  return "person.2"
        case .sessions:   return "flame"
        case .tools:      return "wrench.and.screwdriver"
        }
    }
}

enum AnalyticsDateRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case sevenDays = "7d"
    case fourteenDays = "14d"
    case thirtyDays = "30d"
    case allTime = "All Time"

    var id: String { rawValue }

    var sinceDate: Date? {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        switch self {
        case .today:
            return startOfToday
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -6, to: startOfToday)
        case .fourteenDays:
            return calendar.date(byAdding: .day, value: -13, to: startOfToday)
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: startOfToday)
        case .allTime:
            return nil
        }
    }

    var untilDate: Date? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: now))
        case .sevenDays, .fourteenDays, .thirtyDays:
            return now
        case .allTime:
            return nil
        }
    }
}

struct AnalyticsView: View {
    @ObservedObject var service: SessionAnalyticsService

    @State private var selectedSection: AnalyticsSection = .overview
    @State private var selectedDateRange: AnalyticsDateRange = .sevenDays
    @State private var selectedProjects = Set<String>()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
                .background(Color.white.opacity(0.1))
            VStack(spacing: 0) {
                filterBar
                Divider()
                    .background(Color.white.opacity(0.08))
                Group {
                    if service.isLoading {
                        VStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.large)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            contentForSection(selectedSection)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .onAppear {
            service.load()
        }
        .onChange(of: selectedDateRange) { _, _ in
            reload()
        }
        .onChange(of: selectedProjects) { _, _ in
            reload()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AnalyticsSection.allCases) { section in
                sidebarItem(section)
            }
            Spacer()
            Button {
                reload()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .frame(width: 18, alignment: .center)
                    Text("Refresh")
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 180)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.03))
    }

    private func sidebarItem(_ section: AnalyticsSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 18, alignment: .center)
                Text(section.rawValue)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(selectedSection == section ? Color.white.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
            .foregroundColor(selectedSection == section ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AnalyticsDateRange.allCases) { range in
                    Button {
                        selectedDateRange = range
                    } label: {
                        HStack {
                            Text(range.rawValue)
                            if selectedDateRange == range {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text(selectedDateRange.rawValue)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
            }
            .menuStyle(.borderlessButton)

            Menu {
                let projects = service.availableProjects
                if projects.isEmpty {
                    Text("No projects")
                } else {
                    ForEach(projects, id: \.self) { project in
                        Button {
                            toggleProject(project)
                        } label: {
                            HStack {
                                Text(project)
                                if selectedProjects.contains(project) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(projectMenuTitle)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button("Reset") {
                selectedDateRange = .allTime
                selectedProjects.removeAll()
                reload()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02))
    }

    @ViewBuilder
    private func contentForSection(_ section: AnalyticsSection) -> some View {
        if let result = service.result {
            switch section {
            case .overview:
                AnalyticsOverviewSection(result: result)
            case .byModel:
                AnalyticsByModelSection(result: result)
            case .byProject:
                AnalyticsByProjectSection(result: result)
            case .dailyUsage:
                AnalyticsDailySection(result: result)
            case .efficiency:
                AnalyticsEfficiencySection(result: result)
            case .cache:
                AnalyticsCacheSection(result: result)
            case .prompts:
                AnalyticsPromptsSection(result: result)
            case .subagents:
                AnalyticsSubagentsSection(result: result)
            case .sessions:
                AnalyticsTopSessionsSection(result: result)
            case .tools:
                AnalyticsToolsSection(result: result)
            }
        } else {
            VStack(spacing: 8) {
                Text("No data available")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Click Refresh to load analytics")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var projectMenuTitle: String {
        if selectedProjects.isEmpty {
            return "All Projects"
        }
        if selectedProjects.count == 1, let onlyProject = selectedProjects.first {
            return onlyProject
        }
        return "\(selectedProjects.count) Projects"
    }

    private func toggleProject(_ project: String) {
        if selectedProjects.contains(project) {
            selectedProjects.remove(project)
        } else {
            selectedProjects.insert(project)
        }
    }

    private func reload() {
        service.filter.since = selectedDateRange.sinceDate
        service.filter.until = selectedDateRange.untilDate
        service.filter.projectNames = selectedProjects
        service.load()
    }
}
