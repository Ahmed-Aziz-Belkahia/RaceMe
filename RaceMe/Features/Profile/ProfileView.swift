import SwiftUI

/// You.
///
/// The Racer Card at the top, now live — it's been changing every time they race,
/// which is what was promised on S11. Then the record, the pace trend, the
/// history, and settings behind one gear.
struct ProfileView: View {
    @Bindable var app: AppState

    @Environment(\.motion) private var motion
    @State private var showingSettings = false

    private var profile: RunnerProfile { app.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                RacerCardView(profile: profile, sweep: false)
                    .padding(.horizontal, 20)
                    .staggeredAppear(0)
                record
                paceTrend
                history
                Color.clear.frame(height: 90)
            }
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .atmosphere(.idle)
        .sheet(isPresented: $showingSettings) {
            SettingsView(app: app)
                .presentationBackground(Track.base)
                .providesMotionPreference()
        }
        .refreshable { await app.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(profile.handle.isEmpty ? "You" : "@\(profile.handle)")
                .font(Prose.title(30))
                .foregroundStyle(Track.chalk)
            Spacer()
            Button {
                Haptics.shared.play(.select)
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Track.chalkFaint)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.pressable(scale: 0.9, haptic: nil))
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
    }

    // MARK: Record

    private var record: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackLabel("Career", color: Track.chalkDim)
                .padding(.horizontal, 20)

            HStack(spacing: 0) {
                bigStat("WINS", "\(profile.careerWins)", Track.you)
                divider
                bigStat("LOSSES", "\(profile.careerLosses)", Track.them)
                divider
                bigStat("RACES", "\(profile.totalRaces)", Track.chalk)
            }
            .padding(.horizontal, 20)
        }
        .staggeredAppear(1)
    }

    private var divider: some View {
        Rectangle().fill(Track.hairline).frame(width: 1, height: 34)
    }

    private func bigStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            TrackLabel(label, size: 10)
            Text(value)
                .font(Bib.numeral(38))
                .bibTracking(38)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Pace trend

    /// Drawn as a strip of track seen from above, with the handicap as a chalk
    /// reference line. Anything below the line is a run faster than your own
    /// recent form, and that's the only reading that matters here.
    private var paceTrend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TrackLabel("Pace trend", color: Track.chalkDim)
                Spacer()
                Text("Handicap \(Fmt.pace(profile.handicapPaceSecPerKm, unit: profile.unit))/\(profile.unit.short.lowercased())")
                    .font(Bib.mono(13, weight: .bold))
                    .foregroundStyle(Track.chalkFaint)
            }
            .padding(.horizontal, 20)

            if app.recentResults.count < 2 {
                EmptyLine(
                    text: "Two races and this fills in. It's the line your handicap is calculated from.",
                    actionTitle: "Race now",
                    action: { app.startStagedRace() }
                )
                .padding(.horizontal, 20)
            } else {
                PaceTrendChart(
                    paces: app.recentResults.reversed().map(\.userPace),
                    handicap: profile.handicapPaceSecPerKm,
                    unit: profile.unit
                )
                .frame(height: 120)
                .padding(.horizontal, 20)
            }
        }
        .staggeredAppear(2)
    }

    // MARK: History

    @MainActor private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackLabel("History", color: Track.chalkDim)
                .padding(.horizontal, 20)

            if app.recentResults.isEmpty {
                EmptyLine(
                    text: "Nothing here yet. Every race you finish leaves a photo finish behind, and they all end up on this shelf.",
                    actionTitle: "Race now",
                    action: { app.startStagedRace() }
                )
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(app.recentResults) { result in
                        Button {
                            Haptics.shared.play(.select)
                            app.postRace = result
                        } label: {
                            HStack(spacing: 14) {
                                PhotoFinishView(
                                    film: PhotoFinishFilm.build(from: result),
                                    develop: 1, showsChrome: false, columns: 120
                                )
                                .frame(width: 80, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Fmt.raceName(result.config.distanceMeters))
                                        .font(Bib.label(13))
                                        .labelTracking()
                                        .foregroundStyle(Track.chalk)
                                    Text(Fmt.clock(result.userTime))
                                        .font(Bib.mono(15, weight: .bold))
                                        .foregroundStyle(Track.chalkDim)
                                }
                                Spacer(minLength: 0)
                                if result.isPersonalRecord {
                                    Text("PR")
                                        .font(Bib.label(11))
                                        .labelTracking()
                                        .foregroundStyle(Track.base)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Track.signal))
                                }
                                Text(result.userWon ? "W" : "L")
                                    .font(Bib.numeral(22))
                                    .foregroundStyle(result.userWon ? Track.you : Track.them)
                            }
                            .padding(10)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Track.elevated.opacity(0.7))
                            }
                        }
                        .buttonStyle(.pressable(scale: 0.985, haptic: nil))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .staggeredAppear(3)
    }
}

// MARK: - Pace trend chart

private struct PaceTrendChart: View {
    let paces: [Double]
    let handicap: Double
    let unit: DistanceUnit

    @Environment(\.motion) private var motion
    @State private var drawn: Double = 0

    var body: some View {
        Canvas { ctx, size in
            guard paces.count > 1 else { return }
            let minPace = (paces + [handicap]).min() ?? handicap
            let maxPace = (paces + [handicap]).max() ?? handicap
            let span = max(maxPace - minPace, 12)

            func y(_ pace: Double) -> CGFloat {
                // Faster pace (lower number) sits higher.
                size.height - CGFloat((pace - minPace + 6) / (span + 12)) * size.height
            }

            // Lane surface.
            ctx.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12),
                with: .color(Track.you.opacity(0.05))
            )

            // Handicap reference — the chalk line.
            var reference = Path()
            reference.move(to: CGPoint(x: 0, y: y(handicap)))
            reference.addLine(to: CGPoint(x: size.width, y: y(handicap)))
            ctx.stroke(reference, with: .color(Track.chalk.opacity(0.3)),
                       style: .init(lineWidth: 1, dash: [4, 4]))

            let step = size.width / CGFloat(max(paces.count - 1, 1))
            let visible = Int(ceil(Double(paces.count) * drawn))

            var line = Path()
            for (i, pace) in paces.prefix(max(visible, 2)).enumerated() {
                let point = CGPoint(x: CGFloat(i) * step, y: y(pace))
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            ctx.stroke(line, with: .color(Track.you),
                       style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            for (i, pace) in paces.prefix(max(visible, 2)).enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: y(pace))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
                         with: .color(Track.you.opacity(0.22)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                         with: .color(Track.you))
            }
        }
        .onAppear {
            guard !motion.reduced else { drawn = 1; return }
            withAnimation(.spring(duration: 0.9, bounce: 0)) { drawn = 1 }
        }
        .accessibilityLabel("Pace trend over your last \(paces.count) races")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var app: AppState
    @Environment(\.dismiss) private var dismiss

    private var profile: RunnerProfile { app.profile }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Units", selection: Binding(
                        get: { profile.unit },
                        set: { profile.unit = $0; app.saveProfile(); Haptics.shared.play(.select) }
                    )) {
                        Text("Kilometres").tag(DistanceUnit.km)
                        Text("Miles").tag(DistanceUnit.mi)
                    }
                    Toggle("Haptics", isOn: Binding(
                        get: { Haptics.shared.enabled },
                        set: { Haptics.shared.enabled = $0; if $0 { Haptics.shared.play(.commit) } }
                    ))
                } header: {
                    Text("Racing")
                }

                Section {
                    Picker("How often", selection: Binding(
                        get: { profile.frequency },
                        set: {
                            profile.frequency = $0
                            app.saveProfile()
                            Notifications.scheduleRunReminders(for: profile)
                            Haptics.shared.play(.select)
                        }
                    )) {
                        ForEach(RaceFrequency.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("When you run", selection: Binding(
                        get: { profile.window },
                        set: {
                            profile.window = $0
                            app.saveProfile()
                            Notifications.scheduleRunReminders(for: profile)
                            Haptics.shared.play(.select)
                        }
                    )) {
                        ForEach(RunWindow.allCases) { Text("\($0.label) · \($0.clock)").tag($0) }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Two kinds of notification: someone challenges you, and one before your usual run. Nothing else.")
                }

                Section {
                    LabeledContent("Handicap", value: "\(Fmt.pace(profile.handicapPaceSecPerKm, unit: profile.unit))/\(profile.unit.short.lowercased())")
                    LabeledContent("Archetype", value: profile.archetype.name)
                    if let rival = profile.rivalMention {
                        LabeledContent("Rival", value: rival)
                    }
                } header: {
                    Text("Your numbers")
                } footer: {
                    Text("Your handicap comes from your recent races. Under fair scoring, you're racing that number — not the other person's.")
                }

                Section {
                    Toggle("Simulate movement", isOn: $app.useSimulatedMovement)
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Runs the movement simulator instead of GPS so a race can be demonstrated without leaving the room.")
                }

                Section {
                    LabeledContent("Plan", value: profile.isSubscribed ? "Full" : "Free")
                    if !profile.isSubscribed {
                        Text("Free gives you one race a week. Everything else — unlimited racing, the league, your card — is on the paid plan.")
                            .font(Prose.caption(14))
                            .foregroundStyle(Track.chalkDim)
                    }
                } header: {
                    Text("Account")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Track.base)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Track.you)
    }
}
