import AppKit
import ApplicationServices
import CoreBluetooth
import EventKit
import ServiceManagement
import SwiftUI

/// First-run setup, shown inside the open island: who you are, which tools, which permissions.
@Observable @MainActor
final class Onboarding {
    enum Step: Int, CaseIterable { case welcome, personas, tools, permissions, done }

    private(set) var step = Step.welcome
    private(set) var forward = true
    var personas: [Persona] = []
    var tools: Set<Tool> = []

    func go(to next: Step) {
        forward = next.rawValue > step.rawValue
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? Motion.easeOut(0.15) : Motion.snappy) { step = next }
    }

    /// Picking personas resets the tool picks to what they recommend; the tools step can then adjust.
    func toggle(_ persona: Persona) {
        if let index = personas.firstIndex(of: persona) { personas.remove(at: index) } else { personas.append(persona) }
        tools = personas.isEmpty ? [] : Layout.merging(personas).tools
    }

    func toggle(_ tool: Tool) {
        if tools.contains(tool) { tools.remove(tool) } else { tools.insert(tool) }
    }
}

/// The strip beside the notch during setup: the name on the left, progress on the right.
struct OnboardingStrip: View {
    let step: Onboarding.Step

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Icon(name: "widget-5-bold", size: 13)
                Text("Islet").font(Typeface.label)
            }
            .foregroundStyle(Palette.paper)
            Spacer()
            HStack(spacing: 4) {
                ForEach(Onboarding.Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Palette.paper : item.rawValue < step.rawValue ? Palette.graphite : Palette.rail)
                        .frame(width: item == step ? 14 : 5, height: 5)
                }
            }
            .animation(Motion.snappy, value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Onboarding.Step.allCases.count)")
        }
    }
}

struct OnboardingView: View {
    let app: NotchController
    let flow: Onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        page
            .id(flow.step)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(x: flow.forward ? 16 : -16)), // in from the direction of travel
                removal: .opacity.animation(Motion.easeOut(0.1))))
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var page: some View {
        switch flow.step {
        case .welcome: welcome
        case .personas: personas
        case .tools: tools
        case .permissions: PermissionsPage(app: app, flow: flow)
        case .done: done
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Welcome to Islet")
                    .font(Typeface.heading)
                    .foregroundStyle(Palette.paper)
                Text("Your everyday tools, right in the notch. Tell it what you do and it sets itself up around you.")
                    .font(Typeface.body)
                    .foregroundStyle(Palette.graphite)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            HStack(spacing: 10) {
                Button("Skip setup") { app.finishOnboarding() }
                    .buttonStyle(SecondaryStyle())
                Button("Get started") { flow.go(to: .personas) }
                    .buttonStyle(PrimaryStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var personas: some View {
        Page(title: "What do you do?", subtitle: "Pick one or more. Islet puts the tools you'll use most closest to hand.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Persona.allCases) { persona in
                    PersonaCard(persona: persona, selected: flow.personas.contains(persona)) {
                        withAnimation(Motion.snappy) { flow.toggle(persona) }
                    }
                }
            }
        } footer: {
            footer(back: .welcome, next: "Continue", enabled: !flow.personas.isEmpty) { flow.go(to: .tools) }
        }
    }

    private var tools: some View {
        Page(title: "Your tools", subtitle: "These fit what you do. Tap to add or remove; you can change them any time in Settings.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Tool.allCases.filter { $0 != .home }) { tool in
                    ToolChip(tool: tool, on: flow.tools.contains(tool)) {
                        withAnimation(Motion.snappy) { flow.toggle(tool) }
                    }
                }
            }
        } footer: {
            footer(back: .personas, next: "Continue", enabled: true) {
                app.applyOnboardingChoices()
                flow.go(to: .permissions)
            }
        }
    }

    private var done: some View {
        Page(title: "You're all set", subtitle: "Hover the notch any time to open Islet. Everything here can be changed in Settings.") {
            OpenAtLoginRow()
        } footer: {
            footer(back: .permissions, next: "Finish", enabled: true) { app.finishOnboarding() }
        }
    }

    private func footer(back: Onboarding.Step, next: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Button("Back") { flow.go(to: back) }
                .buttonStyle(SecondaryStyle())
            Spacer()
            Button(next, action: action)
                .buttonStyle(PrimaryStyle())
                .disabled(!enabled)
        }
    }
}

/// One setup page: a heading block, the content, and the buttons, on a fixed rhythm.
private struct Page<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typeface.heading).foregroundStyle(Palette.paper)
                Text(subtitle).font(Typeface.body).foregroundStyle(Palette.graphite)
            }
            content
            footer
        }
    }
}

// MARK: Pieces

private struct PersonaCard: View {
    let persona: Persona
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(name: persona.symbol, size: 16)
                    .foregroundStyle(selected ? Color.black : Palette.paper)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(selected ? Palette.paper : Palette.rail))
                VStack(alignment: .leading, spacing: 4) {
                    Text(persona.title)
                        .font(Typeface.headline)
                        .foregroundStyle(Palette.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    HStack(spacing: 5) {
                        // A peek at the first tools this persona brings.
                        ForEach(persona.ranking.prefix(4), id: \.self) { Icon(name: $0.symbol, size: 11) }
                    }
                    .foregroundStyle(selected ? Palette.graphite : Palette.ash)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.rail.opacity(selected ? 1 : hovering ? 0.6 : 0.35))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.paper.opacity(selected ? 0.5 : 0), lineWidth: 1)
            }
            .scaleEffect(selected ? 1.02 : 1) // the picked card lifts a little
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.ease(0.15), value: hovering)
        .accessibilityLabel(persona.title)
        .accessibilityHint(persona.blurb)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(persona.blurb)
    }
}

private struct ToolChip: View {
    let tool: Tool
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(name: tool.symbol, size: 12)
                Text(tool.shortTitle).font(Typeface.body).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? Palette.paper : Palette.ash)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.rail.opacity(on ? 1 : 0.3))
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.paper.opacity(on ? 0.35 : 0), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(tool.detail)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Only the permissions the chosen tools need, each with a plain reason and a live status.
private struct PermissionsPage: View {
    let app: NotchController
    let flow: Onboarding
    @State private var granted: [Permission: Bool] = [:]

    enum Permission: CaseIterable {
        case accessibility, calendar, bluetooth, screen

        var title: String {
            switch self {
            case .accessibility: "Accessibility"
            case .calendar: "Calendar"
            case .bluetooth: "Bluetooth"
            case .screen: "Screen Recording"
            }
        }

        var reason: String {
            switch self {
            case .accessibility: "So volume, brightness and window snapping work."
            case .calendar: "So your week and Join buttons show on Home."
            case .bluetooth: "So headphone battery shows when they connect."
            case .screen: "So screenshots can capture what's on screen."
            }
        }

        var symbol: String {
            switch self {
            case .accessibility: "shield-check-linear"
            case .calendar: "calendar-linear"
            case .bluetooth: "headphones-round-linear"
            case .screen: "camera-linear"
            }
        }

        var settingsPane: String {
            switch self {
            case .accessibility: "Privacy_Accessibility"
            case .calendar: "Privacy_Calendars"
            case .bluetooth: "Privacy_Bluetooth"
            case .screen: "Privacy_ScreenCapture"
            }
        }

        @MainActor func needed(by preferences: Preferences) -> Bool {
            switch self {
            case .accessibility: preferences.isOn(.volumeHUD) || preferences.isOn(.windowSnapping)
            case .calendar: preferences.isOn(.calendar)
            case .bluetooth: preferences.isOn(.alerts)
            case .screen: preferences.isOn(.screenshot)
            }
        }

        var isGranted: Bool {
            switch self {
            case .accessibility: AXIsProcessTrusted()
            case .calendar: EKEventStore.authorizationStatus(for: .event) == .fullAccess
            case .bluetooth: CBManager.authorization == .allowedAlways
            case .screen: CGPreflightScreenCaptureAccess()
            }
        }
    }

    var body: some View {
        let needed = Permission.allCases.filter { $0.needed(by: app.preferences) }
        Page(title: "A few permissions", subtitle: needed.isEmpty ? "Your tools don't need any. Nothing to allow."
                                                                  : "Only what your tools need. You can skip any and allow it later.") {
            VStack(spacing: 8) {
                ForEach(needed, id: \.self) { permission in
                    PermissionRow(permission: permission, granted: granted[permission] ?? false) { allow(permission) }
                }
            }
        } footer: {
            HStack {
                Button("Back") { flow.go(to: .tools) }.buttonStyle(SecondaryStyle())
                Spacer()
                Button(needed.allSatisfy { granted[$0] ?? false } ? "Continue" : "Skip for now") { flow.go(to: .done) }
                    .buttonStyle(PrimaryStyle())
            }
        }
        .task {
            // Permissions change in System Settings, outside the app, so keep checking while this page is up.
            while !Task.isCancelled {
                granted = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, $0.isGranted) })
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func allow(_ permission: Permission) {
        switch permission {
        case .accessibility:
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .calendar where EKEventStore.authorizationStatus(for: .event) == .notDetermined:
            Task { await app.agenda.refresh() }
        case .screen where !CGRequestScreenCaptureAccess():
            openSettings(permission) // macOS only asks once; after that it's a switch in Settings
        default:
            openSettings(permission)
        }
    }

    private func openSettings(_ permission: Permission) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)")!)
    }
}

private struct PermissionRow: View {
    let permission: PermissionsPage.Permission
    let granted: Bool
    let allow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Icon(name: permission.symbol, size: 14)
                .foregroundStyle(Palette.paper)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.rail))
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(Typeface.headline).foregroundStyle(Palette.paper)
                Text(permission.reason).font(Typeface.caption).foregroundStyle(Palette.ash)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if granted {
                HStack(spacing: 4) {
                    Icon(name: "check-circle-bold", size: 13)
                    Text("Allowed").font(Typeface.label)
                }
                .foregroundStyle(Palette.graphite)
                .transition(.opacity)
            } else {
                Button("Allow", action: allow).buttonStyle(PrimaryStyle())
            }
        }
        .animation(Motion.easeOut(0.2), value: granted)
    }
}

private struct OpenAtLoginRow: View {
    @State private var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 10) {
            Icon(name: "widget-5-bold", size: 14)
                .foregroundStyle(Palette.paper)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.rail))
            VStack(alignment: .leading, spacing: 2) {
                Text("Open at login").font(Typeface.headline).foregroundStyle(Palette.paper)
                Text("So the island is there every time you start your Mac.").font(Typeface.caption).foregroundStyle(Palette.ash)
            }
            Spacer(minLength: 8)
            Toggle("Open at login", isOn: $on)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: on) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        on = SMAppService.mainApp.status == .enabled
                    }
                }
        }
    }
}
