import XCTest
@testable import Burrow

final class DiskMonitorTests: XCTestCase {

    private typealias Reading = DiskMonitorReport.Reading

    // MARK: - Settings defaults & persistence

    func testDefaultsAreOffAndEmpty() {
        let s = DiskMonitorSettings()
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.slackChannel, "")
        XCTAssertEqual(s.slackMentions, [])
        XCTAssertEqual(s.machineName, "")
        XCTAssertEqual(s.paths, ["/"])
    }

    func testSettingsRoundTripThroughDefaults() throws {
        let suite = "burrow-diskmonitor-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var s = DiskMonitorSettings()
        s.enabled = true
        s.thresholdPercent = 7.5
        s.slackChannel = "C0123ABCD"
        s.slackMentions = ["U01", "S02"]
        s.save(to: defaults)

        XCTAssertEqual(DiskMonitorSettings.load(from: defaults), s)
    }

    func testSettingsMissingAFieldStillLoad() throws {
        // Settings saved before a field existed must keep the user's values
        // instead of resetting everything to defaults.
        let older = #"{"enabled":true,"thresholdPercent":30,"intervalMinutes":60,"paths":["/"],"machineName":"","slackChannel":"C0123ABCD","slackMentions":[],"alertOnly":false,"includeTopFolders":true}"#
        let s = try JSONDecoder().decode(DiskMonitorSettings.self, from: Data(older.utf8))
        XCTAssertTrue(s.enabled)
        XCTAssertEqual(s.thresholdPercent, 30)
        XCTAssertFalse(s.alertOnly)
        XCTAssertTrue(s.showInMenuBar)
        XCTAssertEqual(s.percentDisplay, .used)

        let unknown = #"{"percentDisplay":"remaining","thresholdPercent":15}"#
        let u = try JSONDecoder().decode(DiskMonitorSettings.self, from: Data(unknown.utf8))
        XCTAssertEqual(u.percentDisplay, .used)
        XCTAssertEqual(u.thresholdPercent, 15)
    }

    func testDisplayNameFallsBackAndIsCapped() {
        var s = DiskMonitorSettings()
        XCTAssertEqual(s.displayName, DiskMonitorSettings.computerName)
        s.machineName = String(repeating: "x", count: 500)
        XCTAssertEqual(s.displayName.count, 80)
    }

    // MARK: - Menu bar

    func testMenuBarLook() {
        let roomy = Reading(path: "/", total: 100 * gb, free: 60 * gb, failed: false)
        let fuller = Reading(path: "/Volumes/B", total: 100 * gb, free: 26 * gb, failed: false)
        XCTAssertEqual(MenuBarFormat.look([roomy, fuller], threshold: 10).symbol, "internaldrive")
        XCTAssertEqual(MenuBarFormat.look([roomy, fuller], threshold: 10).title, "74%")
        XCTAssertEqual(MenuBarFormat.look([roomy, fuller], threshold: 30).symbol, "exclamationmark.triangle")
        XCTAssertEqual(MenuBarFormat.look([roomy, .unreadable("/X")], threshold: 10).title, "!")
        XCTAssertEqual(MenuBarFormat.look([], threshold: 10).title, "")
        XCTAssertEqual(MenuBarFormat.look([roomy, fuller], threshold: 10, display: .free).title, "26%")
        XCTAssertEqual(MenuBarFormat.look([roomy, .unreadable("/X")], threshold: 10, display: .free).title, "!")
    }

    func testMenuBarLines() {
        let r = Reading(path: "/", total: 494_400_000_000, free: 130_700_000_000, failed: false)
        XCTAssertEqual(MenuBarFormat.line(for: r), "/  —  73.6% used, 130.7 GB free of 494.4 GB")
        XCTAssertEqual(MenuBarFormat.line(for: .unreadable("/X")), "/X  —  couldn't be read")
        XCTAssertEqual(MenuBarFormat.line(for: r, display: .free), "/  —  26.4% free, 130.7 GB of 494.4 GB")
        // Not rounded up to a 5% threshold.
        let tight = Reading(path: "/", total: 1000 * gb, free: 48 * gb, failed: false)
        XCTAssertEqual(MenuBarFormat.usage(tight, .free), "4.8% free, 48.0 GB of 1000.0 GB")
        XCTAssertEqual(MenuBarFormat.schedule(last: nil, next: nil), "Not checked yet")
        let cal = Calendar.current
        let last = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 18, minute: 5))!
        let next = cal.date(byAdding: .hour, value: 1, to: last)!
        XCTAssertEqual(MenuBarFormat.schedule(last: last, next: next), "Last check 18:05 · next 19:05")
    }

    // MARK: - Validation

    func testThresholdPresetsGoFromOneToFifty() {
        XCTAssertEqual(DiskMonitorSettings.thresholdPresets, [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50])
    }

    func testLastScheduledRun() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        var s = DiskMonitorSettings()
        s.schedule = .daily
        s.dailyMinute = 5 * 60
        XCTAssertEqual(s.lastScheduledRun(atOrBefore: at(20, 9, 0), calendar: cal), at(20, 5, 0), "today's has come")
        XCTAssertEqual(s.lastScheduledRun(atOrBefore: at(20, 4, 0), calendar: cal), at(19, 5, 0), "not yet: yesterday's")
        XCTAssertEqual(s.lastScheduledRun(atOrBefore: at(20, 5, 0), calendar: cal), at(20, 5, 0))
    }

    func testParseChannel() throws {
        // Only links: a bare ID or #name is rejected so nothing is hand-typed.
        XCTAssertEqual(try DiskMonitorSettings.parseChannel("  "), "")
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("C0123ABCD"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("#ops"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("guide.slack.com/archives/C0123ABCD"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("http://guide.slack.com/archives/C0123ABCD"))
    }

    func testParseToken() throws {
        XCTAssertEqual(try DiskMonitorSettings.parseToken("  xoxb-123-456-AbC\n"), "xoxb-123-456-AbC")
        XCTAssertEqual(try DiskMonitorSettings.parseToken("xoxp-1-2"), "xoxp-1-2")
        // Half-pasted, other secrets, or text around the token.
        for bad in ["", "xoxb-", "xoxb", "8f2c1e0d9a", "Bearer xoxb-1-2", "xoxb-1 2"] {
            XCTAssertThrowsError(try DiskMonitorSettings.parseToken(bad), bad) { error in
                XCTAssertEqual(error as? DiskMonitorSettings.ValidationError, .token)
            }
        }
    }

    func testTokenCommitNeverHappensWhileTyping() {
        // "xoxb-1" is a valid token shape, so only a finished edit may save it.
        XCTAssertEqual(DiskMonitorSettings.tokenCommit(draft: "xoxb-1", finished: false), .none)
        XCTAssertEqual(DiskMonitorSettings.tokenCommit(draft: "xoxb-1", finished: true), .save("xoxb-1"))
        XCTAssertEqual(DiskMonitorSettings.tokenCommit(draft: " xoxb-1-2\n", finished: true), .save("xoxb-1-2"))
    }

    func testTokenCommitBlankNeverTouchesTheStoredToken() {
        for finished in [false, true] {
            XCTAssertEqual(DiskMonitorSettings.tokenCommit(draft: "", finished: finished), .none)
            XCTAssertEqual(DiskMonitorSettings.tokenCommit(draft: "  \n", finished: finished), .none)
        }
    }

    func testTokenCommitRejectsBadTokenOnlyWhenFinished() {
        XCTAssertEqual(DiskMonitorSettings.tokenCommit(draft: "xoxb-", finished: true), .invalid)
        XCTAssertEqual(DiskMonitorSettings.tokenCommit(draft: "8f2c1e0d9a", finished: true), .invalid)
        XCTAssertEqual(DiskMonitorSettings.tokenCommit(draft: "8f2c1e0d9a", finished: false), .none)
    }

    func testApplyChannelLink() throws {
        var s = DiskMonitorSettings()
        try s.applyChannelLink(" https://guide.slack.com/archives/C0123ABCD ")
        XCTAssertEqual(s.slackChannel, "C0123ABCD")
        XCTAssertEqual(s.slackChannelLink, "https://guide.slack.com/archives/C0123ABCD")

        // A rejected input changes nothing.
        XCTAssertThrowsError(try s.applyChannelLink("C0999"))
        XCTAssertEqual(s.slackChannel, "C0123ABCD")

        // Clearing the link turns Slack off.
        try s.applyChannelLink("")
        XCTAssertEqual(s.slackChannel, "")
        XCTAssertEqual(s.slackChannelLink, "")
    }

    func testParseChannelFromSlackLink() throws {
        XCTAssertEqual(try DiskMonitorSettings.parseChannel("https://guide.slack.com/archives/C0123ABCD"), "C0123ABCD")
        XCTAssertEqual(try DiskMonitorSettings.parseChannel(" https://guide.slack.com/archives/C0123ABCD/p1700000000000100 "), "C0123ABCD")
        XCTAssertEqual(try DiskMonitorSettings.parseChannel("https://app.slack.com/client/T0123/G0456EFGH"), "G0456EFGH")
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("https://evil.example.com/archives/C0123ABCD"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("https://guide.slack.com/team/U0123ABCD"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("https://guide.slack.com/archives/general"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("https://slack.com.evil.com/archives/C0123ABCD"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("https://evilslack.com/archives/C0123ABCD"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("https://user@evil.com/archives/C0123ABCD"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseChannel("https://guide.slack.com@evil.com/archives/C0123ABCD"))
        XCTAssertEqual(try DiskMonitorSettings.parseChannel("HTTPS://Guide.Slack.com:443/archives/C0123ABCD/?x=1#y"), "C0123ABCD")
    }

    func testParseMentions() throws {
        XCTAssertEqual(try DiskMonitorSettings.parseMentions(""), [])
        XCTAssertEqual(try DiskMonitorSettings.parseMentions("U0123ABCD, S0456EFGH ,W0789"),
                       ["U0123ABCD", "S0456EFGH", "W0789"])
        XCTAssertThrowsError(try DiskMonitorSettings.parseMentions("@alice"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseMentions("U0123, C0123"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseMentions("u0123abcd"))
        XCTAssertThrowsError(try DiskMonitorSettings.parseMentions("U1"))
    }

    func testIntervalPresetsGoUpToADay() {
        XCTAssertEqual(DiskMonitorSettings.intervalPresets, [15, 30, 60, 180, 360, 720, 1440])
        XCTAssertEqual(DiskMonitorSettings.intervalPresets, DiskMonitorSettings.intervalPresets.sorted())
    }

    func testNextRunForIntervalAndDailySchedules() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        var s = DiskMonitorSettings()
        s.intervalMinutes = 60
        XCTAssertEqual(s.nextRun(after: at(20, 10, 0), calendar: cal), at(20, 11, 0))

        s.schedule = .daily
        s.dailyMinute = 2 * 60   // 02:00
        XCTAssertEqual(s.nextRun(after: at(20, 1, 30), calendar: cal), at(20, 2, 0), "later today")
        XCTAssertEqual(s.nextRun(after: at(20, 10, 0), calendar: cal), at(21, 2, 0), "already passed: tomorrow")
        XCTAssertEqual(s.nextRun(after: at(20, 2, 0), calendar: cal), at(21, 2, 0), "exactly now: next day")
        s.dailyMinute = 23 * 60 + 59
        XCTAssertEqual(s.nextRun(after: at(20, 23, 0), calendar: cal), at(20, 23, 59))
    }

    func testDailyRunIsOncePerDayAcrossDST() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var s = DiskMonitorSettings()
        s.schedule = .daily

        // Fall back, 2026-11-01: 01:30 happens twice. After the first run,
        // the next one is the following day, not an hour later.
        s.dailyMinute = 90
        let firstRun = try XCTUnwrap(s.nextRun(after: cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!, calendar: cal))
        let next = s.nextRun(after: firstRun.addingTimeInterval(1), calendar: cal)
        XCTAssertEqual(cal.component(.day, from: next), 2)
        XCTAssertGreaterThan(next.timeIntervalSince(firstRun), 23 * 3600)

        // Spring forward, 2026-03-08: 02:30 doesn't exist → runs at 03:00.
        s.dailyMinute = 150
        let spring = s.nextRun(after: cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0))!, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.day, .hour, .minute], from: spring), DateComponents(day: 8, hour: 3, minute: 0))
    }

    func testResetKeepsMonitoringAndSlack() {
        var s = DiskMonitorSettings()
        s.enabled = true
        s.slackChannel = "C0123ABCD"
        s.slackChannelLink = "https://guide.slack.com/archives/C0123ABCD"
        s.slackMentions = ["U01"]
        s.thresholdPercent = 40
        s.schedule = .daily
        s.dailyMinute = 17 * 60
        s.intervalMinutes = 720
        s.paths = ["/", "/Volumes/B"]
        s.machineName = "Build Mac"
        s.percentDisplay = .free
        s.showInMenuBar = false
        s.alertOnly = false
        s.includeTopFolders = false

        let r = s.resetToDefaults()
        var expected = DiskMonitorSettings()
        expected.enabled = true
        expected.slackChannel = "C0123ABCD"
        expected.slackChannelLink = "https://guide.slack.com/archives/C0123ABCD"
        expected.slackMentions = ["U01"]
        expected.alertOnly = false            // Slack section: kept
        expected.includeTopFolders = false
        XCTAssertEqual(r, expected)
    }

    func testScheduleDecodesWithDefaults() throws {
        let older = #"{"enabled":true,"intervalMinutes":60}"#
        let s = try JSONDecoder().decode(DiskMonitorSettings.self, from: Data(older.utf8))
        XCTAssertEqual(s.schedule, .interval)
        XCTAssertEqual(s.dailyMinute, 5 * 60)   // 05:00
    }

    func testParsePathsDedupesAndFallsBack() {
        XCTAssertEqual(DiskMonitorSettings.parsePaths(" /, /Volumes/Data ,/, "), ["/", "/Volumes/Data"])
        XCTAssertEqual(DiskMonitorSettings.parsePaths(" , "), ["/"])
    }

    // MARK: - Report

    private let gb = Int64(1_000_000_000)

    func testAlertAtOrBelowThresholdOrOnFailure() {
        let ok = Reading(path: "/", total: 100 * gb, free: 50 * gb, failed: false)
        let atThreshold = Reading(path: "/", total: 100 * gb, free: 10 * gb, failed: false)
        XCTAssertFalse(DiskMonitorReport.isAlert([ok], threshold: 10))
        XCTAssertTrue(DiskMonitorReport.isAlert([atThreshold], threshold: 10))
        XCTAssertTrue(DiskMonitorReport.isAlert([ok, .unreadable("/Volumes/X")], threshold: 10))
        XCTAssertFalse(DiskMonitorReport.isAlert([], threshold: 10))
    }

    func testAlertMessageTagsMentionsInBodyAndListsFolders() throws {
        let low = Reading(path: "/", total: 500 * gb, free: 20 * gb, failed: false)
        let msg = DiskMonitorReport.message(
            host: "Build Mac", readings: [low], threshold: 7.5,
            topFolders: .init(folders: [.init(path: NSHomeDirectory() + "/Library", bytes: 40 * gb)]),
            mentions: ["U01", "S02"]
        )
        // Mentions in the top-level text, where Slack notifies for them.
        XCTAssertEqual(msg.text, ":warning: Low disk space - Build Mac\n<@U01> <!subteam^S02>")
        let attachment = try XCTUnwrap(msg.attachments.first)
        XCTAssertEqual(attachment.color, DiskMonitorReport.alertColor)
        XCTAssertEqual(attachment.blocks.count, 3)
        XCTAssertTrue(attachment.blocks[0].mrkdwn.contains("*20.0 GB* of 500.0 GB (4% free, threshold 7.5%, *below threshold*)"))
        XCTAssertTrue(attachment.blocks[1].mrkdwn.contains("40.0 GB  ~/Library"))
        XCTAssertFalse(attachment.blocks.contains { $0.mrkdwn.contains("<@U01>") })
    }

    func testOKMessageHasNoMentions() throws {
        let ok = Reading(path: "/", total: 500 * gb, free: 200 * gb, failed: false)
        let msg = DiskMonitorReport.message(host: "M", readings: [ok], threshold: 10,
                                            topFolders: nil, mentions: ["U01"])
        XCTAssertEqual(msg.text, ":file_folder: Disk report - M")
        let attachment = try XCTUnwrap(msg.attachments.first)
        XCTAssertEqual(attachment.color, DiskMonitorReport.okColor)
        XCTAssertEqual(attachment.blocks.count, 2)
    }

    func testThresholdShownTheSameEverywhere() {
        XCTAssertEqual(DiskMonitorReport.threshold(7.25), "7.25%")
        XCTAssertEqual(DiskMonitorReport.threshold(10), "10%")
        XCTAssertEqual(MenuBarFormat.percent(7.25), DiskMonitorReport.threshold(7.25))
        let low = Reading(path: "/", total: 100 * gb, free: 5 * gb, failed: false)
        let msg = DiskMonitorReport.message(host: "M", readings: [low], threshold: 7.25, topFolders: nil, mentions: [])
        XCTAssertTrue(msg.attachments[0].blocks[0].mrkdwn.contains("threshold 7.25%"))
    }

    func testScanSkipListsWithAndWithoutFullDiskAccess() {
        for name in ["Containers", "Mail", "Documents", "Desktop", "Downloads", "Photos Library.photoslibrary"] {
            XCTAssertTrue(DiskMonitorReport.protectedNames.contains(name), name)
        }
        // File Provider folders are skipped even with Full Disk Access.
        XCTAssertTrue(Set(DiskMonitorReport.cloudNames).isSubset(of: Set(DiskMonitorReport.protectedNames)))
        XCTAssertEqual(Set(DiskMonitorReport.cloudNames), ["Mobile Documents", "CloudStorage"])
    }

    func testPercentFormatIsLocaleFree() {
        XCTAssertEqual(DiskMonitorReport.percent(7.5), "7.5")
        XCTAssertEqual(DiskMonitorReport.percent(10), "10")
        XCTAssertEqual(DiskMonitorReport.percent(26.44), "26.4")
    }

    func testUnreadableAndEscapedText() throws {
        let msg = DiskMonitorReport.message(host: "<!channel> & co", readings: [.unreadable("/Volumes/<X>")],
                                            threshold: 10, topFolders: nil, mentions: [])
        let text = try XCTUnwrap(msg.attachments.first?.blocks.first?.mrkdwn)
        XCTAssertTrue(text.contains("Host: *&lt;!channel&gt; &amp; co*"))
        XCTAssertTrue(text.contains("`/Volumes/&lt;X&gt;`: *not measured*"))
        XCTAssertEqual(msg.text, ":warning: Low disk space - &lt;!channel&gt; &amp; co")
    }

    func testTopSectionWhenScanCouldNotRunOrIsEmpty() throws {
        let low = Reading(path: "/", total: 100 * gb, free: 1 * gb, failed: false)
        let timedOut = DiskMonitorReport.message(host: "M", readings: [low], threshold: 10,
                                                 topFolders: nil, includeTopSection: true, mentions: [])
        XCTAssertTrue(try XCTUnwrap(timedOut.attachments.first).blocks[1].mrkdwn.contains("couldn't be measured"))
        XCTAssertEqual(DiskMonitorReport.formatTop(.init(folders: [])), "*Top space consumers*\nNothing measurable found.")
    }

    func testTopSectionSaysWhenAppDataWasSkipped() {
        let limited = DiskMonitorReport.formatTop(.init(folders: [.init(path: "/x", bytes: gb)], limited: true))
        XCTAssertTrue(limited.contains("Full Disk Access"))
        XCTAssertFalse(DiskMonitorReport.formatTop(.init(folders: [.init(path: "/x", bytes: gb)])).contains("Full Disk Access"))
        XCTAssertTrue(DiskMonitorReport.protectedNames.contains("Containers"))
    }

    func testLooseFilesRowAndRanking() {
        // ~/Downloads: 45 GB total, one 1 GB subfolder → 44 GB of loose files.
        let loose = DiskMonitorReport.looseFiles(in: "/Users/a/Downloads", total: 45 * gb, children: [1 * gb])
        XCTAssertEqual(loose, [.init(path: "/Users/a/Downloads/*", bytes: 44 * gb)])
        XCTAssertEqual(DiskMonitorReport.looseFiles(in: "/x", total: 1 * gb, children: [1 * gb]), [])

        let ranked = DiskMonitorReport.rank(loose + [.init(path: "/Users/a/Downloads/sub", bytes: 1 * gb)], limit: 1)
        XCTAssertEqual(ranked.map(\.path), ["/Users/a/Downloads/*"])
        XCTAssertTrue(DiskMonitorReport.formatTop(.init(folders: loose)).contains("44.0 GB  /Users/a/Downloads/*"))
    }

    func testEveryMessageEndsWithBurrowSignature() throws {
        let ok = Reading(path: "/", total: 500 * gb, free: 200 * gb, failed: false)
        let report = DiskMonitorReport.message(host: "M", readings: [ok], threshold: 10,
                                               topFolders: nil, mentions: [], version: "1.2.3")
        let test = DiskMonitorReport.testMessage(host: "M", version: "1.2.3")
        let expected = SlackClient.Block.context("Sent from <https://github.com/guide-vinh/Burrow|Burrow> v1.2.3")
        XCTAssertEqual(report.attachments.first?.blocks.last, expected)
        XCTAssertEqual(test.attachments.first?.blocks.last, expected)
        XCTAssertEqual(test.text, ":white_check_mark: Slack test - M")
        XCTAssertFalse(try XCTUnwrap(test.attachments.first?.blocks.first).mrkdwn.contains(test.text))
    }

    func testContextBlockEncoding() throws {
        let data = try JSONEncoder().encode(SlackClient.Block.context("sig"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "context")
        let elements = try XCTUnwrap(json["elements"] as? [[String: String]])
        XCTAssertEqual(elements, [["type": "mrkdwn", "text": "sig"]])
        XCTAssertNil(json["text"])
    }

    func testSectionBlockEncoding() throws {
        let data = try JSONEncoder().encode(SlackClient.Block.section("hi"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "section")
        let text = try XCTUnwrap(json["text"] as? [String: String])
        XCTAssertEqual(text, ["type": "mrkdwn", "text": "hi"])
        XCTAssertNil(json["elements"])
    }

    func testExplainSlackErrors() {
        XCTAssertTrue(DiskMonitorViewModel.explain(SlackClient.SlackError.api("not_in_channel")).contains("/invite"))
        XCTAssertTrue(DiskMonitorViewModel.explain(SlackClient.SlackError.api("channel_not_found")).contains("link"))
        XCTAssertEqual(DiskMonitorViewModel.explain(SlackClient.SlackError.api("weird")), "Slack error: weird.")
    }

    // MARK: - Reading volumes & timeouts

    func testHungVolumeTimesOutAsUnreadableWithoutBlockingOthers() async {
        let gb = self.gb
        let hung = "/Volumes/Hung-\(UUID().uuidString)"
        let read: @Sendable (String) -> Reading = { path in
            if path == hung { Thread.sleep(forTimeInterval: 3) }
            return Reading(path: path, total: 100 * gb, free: 50 * gb, failed: false)
        }
        let start = Date()
        let readings = await DiskMonitorReport.readAll(["/", hung, "/Volumes/B"], timeout: 0.2, read: read)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.5)
        XCTAssertEqual(readings.map(\.path), ["/", hung, "/Volumes/B"])
        XCTAssertEqual(readings.map(\.failed), [false, true, false])

        // Still hung: reported at once, without blocking another thread.
        let again = Date()
        let second = await DiskMonitorReport.readAll([hung], timeout: 2, read: read)
        XCTAssertEqual(second.map(\.failed), [true])
        XCTAssertLessThan(Date().timeIntervalSince(again), 1)
    }

    func testWithDeadlineKeepsWhatWasDoneWhenTimeRunsOut() async {
        let start = Date()
        // Work that, when cancelled, still returns what it has (like a
        // terminated du returning the folders it finished).
        let result = await DiskMonitorReport.withDeadline(0.1) { () -> String in
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 10_000_000) }
            return "partial"
        }
        XCTAssertEqual(result, "partial")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let fast = await DiskMonitorReport.withDeadline(5) { "done" }
        XCTAssertEqual(fast, "done")
    }

    private func makeTree(_ layout: [String: Int]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-tree-\(UUID().uuidString)")
        for (relative, bytes) in layout {
            let file = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: file)
        }
        return root.standardizedFileURL
    }

    func testScanTreeMeasuresTwoLevelsInOneWalk() async throws {
        let root = try makeTree([
            "Big/a/file": 400_000, "Big/b/file": 200_000, "Big/loose": 100_000,
            "Small/x/file": 10_000, "top-loose": 50_000,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = await DiskUsageScanner.scanTree(root, depth: 2)
        XCTAssertTrue(tree.complete)
        for sub in ["", "/Big", "/Big/a", "/Big/b", "/Small", "/Small/x"] {
            XCTAssertNotNil(tree.sizes[root.path + sub], sub)
        }
        XCTAssertGreaterThan(tree.sizes[root.path + "/Big/a"] ?? 0, tree.sizes[root.path + "/Big/b"] ?? 0)

        let folders = DiskMonitorReport.assemble(tree.sizes, home: root.path, limit: 10, expand: 1)
        let paths = folders.map(\.path)
        XCTAssertEqual(Set(paths), Set([root.path + "/Big/a", root.path + "/Big/b", root.path + "/Big/*",
                                        root.path + "/Small", root.path + "/*"]))
    }

    func testScanTreeWithLargeOutputDoesNotBlock() async throws {
        // ~3000 folders at depth 2: more output than a pipe buffer holds,
        // which deadlocks if du's output is only read after it exits.
        var layout: [String: Int] = [:]
        for i in 0..<30 { for j in 0..<100 { layout["folder-with-a-long-name-\(i)/sub-\(j)-padding-padding/f"] = 1 } }
        let root = try makeTree(layout)
        defer { try? FileManager.default.removeItem(at: root) }

        let start = Date()
        let tree = await DiskMonitorReport.withDeadline(30) { await DiskUsageScanner.scanTree(root, depth: 2) }
        XCTAssertTrue(tree.complete)
        XCTAssertEqual(tree.sizes.count, 1 + 30 + 3000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 25)
    }

    func testScanTreeStoppedEarlyIsPartialAndQuick() async {
        // /System/Library takes many seconds to walk and needs no privacy
        // permission; a cancelled walk must return right away, marked partial.
        let start = Date()
        let task = Task { await DiskUsageScanner.scanTree(URL(fileURLWithPath: "/System/Library"), depth: 2) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let tree = await task.value
        XCTAssertFalse(tree.complete)
        XCTAssertFalse(tree.failed)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testScanTreeKillsAProcessThatIgnoresTerm() async throws {
        // Stands in for a du that won't stop on SIGTERM. It records its pid
        // so the test can check it was actually killed, not just abandoned.
        let pidFile = NSTemporaryDirectory() + "burrow-scantree-\(UUID().uuidString).pid"
        defer { try? FileManager.default.removeItem(atPath: pidFile) }
        let start = Date()
        let task = Task {
            await DiskUsageScanner.scanTree(URL(fileURLWithPath: "/"), depth: 1, killGrace: 0.3,
                                            command: (URL(fileURLWithPath: "/bin/sh"),
                                                      ["-c", "echo $$ > '\(pidFile)'; trap '' TERM; echo '4\t/a'; while :; do sleep 0.1; done"]))
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let tree = await task.value
        XCTAssertFalse(tree.complete)
        XCTAssertEqual(tree.sizes["/a"], 4 * 1024, "output read before the stop is kept")
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)

        let pid = try XCTUnwrap(Int32(String(contentsOfFile: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1, "SIGKILL ended the process that ignored SIGTERM")
    }

    func testScanTreeGivesUpOnAProcessThatNeverLetsGo() async {
        // The shell is killed, but a child keeps the pipe open, so EOF never
        // comes — like a du stuck in uninterruptible I/O. The scan must
        // still return after the grace periods.
        let start = Date()
        let task = Task {
            await DiskUsageScanner.scanTree(URL(fileURLWithPath: "/"), depth: 1, killGrace: 0.3,
                                            command: (URL(fileURLWithPath: "/bin/sh"),
                                                      ["-c", "trap '' TERM; echo '8\t/b'; sleep 5"]))
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let tree = await task.value
        XCTAssertFalse(tree.complete)
        XCTAssertEqual(tree.sizes["/b"], 8 * 1024)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testParseSizesSkipsBrokenLines() {
        let sizes = DiskUsageScanner.parseSizes("10\t/a\n20\t/a/b\nnot a line\n\t/c\n")
        XCTAssertEqual(sizes, ["/a": Int64(10 * 1024), "/a/b": Int64(20 * 1024)])
    }

    func testAssembleFromAStoppedWalk() {
        let home = "/Users/a"
        // Stopped mid-walk: neither ~ nor ~/Library got a total, but some of
        // Library's subfolders and all of ~/projects did.
        let sizes: [String: Int64] = [
            "/Users/a/projects": 30 * gb, "/Users/a/projects/app": 25 * gb,
            "/Users/a/Library/Caches": 12 * gb, "/Users/a/Library/Developer": 40 * gb,
            "/Users/a/Pictures": 2 * gb,
        ]
        let folders = DiskMonitorReport.assemble(sizes, home: home, limit: 10, expand: 1)
        let byPath = Dictionary(uniqueKeysWithValues: folders.map { ($0.path, $0.bytes) })
        XCTAssertEqual(byPath["/Users/a/Library/Developer"], 40 * gb)   // unfinished parent → its children
        XCTAssertEqual(byPath["/Users/a/Library/Caches"], 12 * gb)
        XCTAssertEqual(byPath["/Users/a/projects/app"], 25 * gb)         // biggest finished → expanded
        XCTAssertEqual(byPath["/Users/a/projects/*"], 5 * gb)
        XCTAssertEqual(byPath["/Users/a/Pictures"], 2 * gb)
        XCTAssertNil(byPath["/Users/a/*"], "no home total, so no loose-files row")
        XCTAssertNil(byPath["/Users/a/Library"])
    }

    func testRankingIsStableOnTies() {
        let a = DiskMonitorReport.Folder(path: "/b", bytes: gb)
        let b = DiskMonitorReport.Folder(path: "/a", bytes: gb)
        XCTAssertEqual(DiskMonitorReport.rank([a, b], limit: 2).map(\.path), ["/a", "/b"])
        XCTAssertEqual(DiskMonitorReport.rank([b, a], limit: 2).map(\.path), ["/a", "/b"])
    }

    func testPartialListIsLabelled() {
        let text = DiskMonitorReport.formatTop(.init(folders: [.init(path: "/x", bytes: gb)], stoppedAfter: 300))
        XCTAssertTrue(text.contains("Scan stopped after 5 min"))
        // Stopped early (killed, cancelled): no claim about a time limit.
        let early = DiskMonitorReport.formatTop(.init(folders: [], stoppedAfter: 12))
        XCTAssertTrue(early.contains("Scan stopped before it finished"))
        XCTAssertFalse(DiskMonitorReport.formatTop(.init(folders: [.init(path: "/x", bytes: gb)])).contains("Scan stopped"))
    }

    // MARK: - check()

    private final class Spy {
        var posts: [(SlackClient.Message, String, String)] = []
        var notifications = 0
        var deliver = true
        var denied = false
        var notifyDelay: UInt64 = 0
        var notifyStarted = false
        var authorizeHangs = false
        var authorizeDelay: UInt64 = 0
        var granted = true
        var scans = 0
        var free: [String: Int64] = [:]
        var postDelay: UInt64 = 0
        var scanDelay: UInt64 = 0
        var partialScan = false
        var readDelay: UInt64 = 0
        var reads = 0
        var now = Date()
    }

    /// Polls until `condition` holds (or 5 s pass) instead of sleeping a
    /// fixed time, so slow machines don't make these tests flaky.
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// For "nothing more happens" assertions, after the expected work is done.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    @MainActor
    private func makeVM(_ spy: Spy, token: String? = "xoxb-test",
                        configure: (inout DiskMonitorSettings) -> Void) throws -> (DiskMonitorViewModel, () -> Void) {
        let suite = "burrow-diskmonitor-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let kc = Keychain(service: "fun.burrow.tests.\(UUID().uuidString)")
        if let token { kc.write(token, for: "bot-token") }

        var s = DiskMonitorSettings()
        s.slackChannel = "C0123ABCD"
        configure(&s)
        s.save(to: defaults)

        var deps = DiskMonitorViewModel.Dependencies()
        let total = 100 * gb
        deps.readAll = { paths in
            spy.reads += 1
            if spy.readDelay > 0 { try? await Task.sleep(nanoseconds: spy.readDelay) }
            return paths.map { Reading(path: $0, total: total, free: spy.free[$0] ?? 50 * total / 100, failed: false) }
        }
        deps.scanTopFolders = {
            spy.scans += 1
            if spy.scanDelay > 0 { try? await Task.sleep(nanoseconds: spy.scanDelay) }
            return .init(folders: [], stoppedAfter: spy.partialScan ? 300 : nil)
        }
        deps.post = { msg, token, channel in
            if spy.postDelay > 0 { try await Task.sleep(nanoseconds: spy.postDelay) }
            spy.posts.append((msg, token, channel))
        }
        deps.authorize = {
            if spy.authorizeHangs { try? await Task.sleep(nanoseconds: 60_000_000_000) }
            if spy.authorizeDelay > 0 { try? await Task.sleep(nanoseconds: spy.authorizeDelay) }
            return spy.granted
        }
        deps.notificationsDenied = { spy.denied }
        deps.notify = { _, _ in
            spy.notifyStarted = true
            if spy.notifyDelay > 0 { try? await Task.sleep(nanoseconds: spy.notifyDelay) }
            spy.notifications += 1
            return spy.deliver
        }
        deps.now = { spy.now }

        // Stored `enabled` doesn't start a timer: only start() or toggling does.
        let vm = DiskMonitorViewModel(defaults: defaults, keychain: kc, dependencies: deps,
                                      recheckDelay: 10_000_000, timerSlice: 0.02)
        return (vm, { kc.delete("bot-token"); defaults.removePersistentDomain(forName: suite) })
    }

    @MainActor
    func testAlertOnlySkipsHealthyDiskAndPostsLowOne() async throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { _ in }
        defer { cleanup() }

        await vm.check()
        XCTAssertTrue(spy.posts.isEmpty)
        XCTAssertEqual(spy.notifications, 0)

        spy.free["/"] = 5 * gb
        await vm.check()
        XCTAssertEqual(spy.posts.count, 1)
        XCTAssertEqual(spy.posts.first?.1, "xoxb-test")
        XCTAssertEqual(spy.posts.first?.2, "C0123ABCD")
        XCTAssertEqual(spy.scans, 1)
        XCTAssertEqual(vm.slackStatus, "Report sent to Slack.")
    }

    @MainActor
    func testNotifiesOnlyWhenAlertingSetGrows() async throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { $0.paths = ["/", "/Volumes/B"] }
        defer { cleanup() }

        spy.free["/"] = 5 * gb
        await vm.check()
        await vm.check()
        XCTAssertEqual(spy.notifications, 1)

        spy.free["/Volumes/B"] = 1 * gb
        await vm.check()
        XCTAssertEqual(spy.notifications, 2)

        spy.free = [:]
        await vm.check()
        spy.free["/"] = 5 * gb
        await vm.check()
        XCTAssertEqual(spy.notifications, 3)
    }

    @MainActor
    func testUndeliveredNotificationIsRetriedAndDenialShown() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.deliver = false   // e.g. permission not granted yet
        spy.denied = true
        let (vm, cleanup) = try makeVM(spy) { _ in }
        defer { cleanup() }

        await vm.check()
        XCTAssertTrue(vm.notificationsDenied)

        spy.deliver = true
        spy.denied = false
        await vm.check()
        await vm.check()
        XCTAssertEqual(spy.notifications, 2)   // retried once, then quiet
        await vm.refreshNotificationStatus()
        XCTAssertFalse(vm.notificationsDenied)
    }

    @MainActor
    func testGrantingPermissionDeliversTheHeldBackAlertRightAway() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.deliver = false            // not authorized while the prompt is open
        spy.authorizeDelay = 300_000_000
        let (vm, cleanup) = try makeVM(spy) { $0.intervalMinutes = 360 }
        defer { cleanup() }

        vm.settings.enabled = true
        await waitUntil { spy.notifications == 1 }
        spy.deliver = true             // the user clicks Allow…
        await waitUntil { spy.notifications == 2 }   // …and it's shown now, not in 6 h

        XCTAssertEqual(spy.notifications, 2)
        vm.settings.enabled = false
    }

    @MainActor
    func testFailedPermissionRequestIsNotShownAsDenied() async throws {
        let spy = Spy()
        spy.granted = false            // request failed (e.g. unsigned build)…
        spy.denied = false             // …but the user never turned them off
        let (vm, cleanup) = try makeVM(spy) { _ in }
        defer { cleanup() }

        vm.settings.enabled = true
        await settle()
        XCTAssertFalse(vm.notificationsDenied)
        vm.settings.enabled = false
    }

    @MainActor
    func testUnansweredPermissionPromptDoesNotStopMonitoring() async throws {
        let spy = Spy()
        spy.authorizeHangs = true   // the user never answers the prompt
        let (vm, cleanup) = try makeVM(spy) { $0.alertOnly = false }
        defer { cleanup() }

        vm.settings.enabled = true
        await waitUntil { spy.posts.count == 1 }
        XCTAssertEqual(spy.posts.count, 1)
        XCTAssertNotNil(vm.nextCheck)
        vm.settings.enabled = false
    }

    @MainActor
    func testTopFoldersCacheReusedThenRefreshed() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        let (vm, cleanup) = try makeVM(spy) { $0.paths = ["/", "/Volumes/B"] }
        defer { cleanup() }

        await vm.check()
        await vm.check()
        XCTAssertEqual(spy.scans, 1)            // fresh: reused

        spy.free["/Volumes/B"] = 1 * gb
        await vm.check()
        XCTAssertEqual(spy.scans, 2)            // a new disk turned low

        spy.now = spy.now.addingTimeInterval(2 * 3600)
        await vm.check()
        XCTAssertEqual(spy.scans, 3)            // older than an hour
        XCTAssertEqual(spy.posts.count, 4)
    }

    @MainActor
    func testPartialTopFoldersAreNotCached() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.partialScan = true
        let (vm, cleanup) = try makeVM(spy) { _ in }
        defer { cleanup() }

        await vm.check()
        await vm.check()
        XCTAssertEqual(spy.scans, 2, "a partial list should be retried, not reused")
    }

    @MainActor
    func testReportEveryCheckWithoutTopFoldersWhenNotAlertOnly() async throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { $0.alertOnly = false }
        defer { cleanup() }

        await vm.check()
        await vm.check()
        XCTAssertEqual(spy.posts.count, 2)
        XCTAssertEqual(spy.scans, 0)
        XCTAssertEqual(spy.posts.first?.0.attachments.first?.color, DiskMonitorReport.okColor)
    }

    @MainActor
    func testChangingThresholdRechecksWithNewValue() async throws {
        let spy = Spy()
        spy.free["/"] = 26 * gb
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true; $0.alertOnly = false }
        defer { cleanup() }

        vm.settings.thresholdPercent = 20
        vm.settings.thresholdPercent = 30   // debounced: one report, with 30
        await waitUntil { spy.posts.count >= 1 }
        await settle()

        XCTAssertEqual(spy.posts.count, 1)
        let attachment = try XCTUnwrap(spy.posts.first?.0.attachments.first)
        XCTAssertEqual(attachment.color, DiskMonitorReport.alertColor)
        XCTAssertTrue(attachment.blocks[0].mrkdwn.contains("threshold 30%"))
        XCTAssertEqual(spy.notifications, 1)
    }

    @MainActor
    func testRecheckDuringRunningCheckRunsAfterwards() async throws {
        let spy = Spy()
        spy.free["/"] = 26 * gb
        spy.postDelay = 300_000_000   // a slow Slack post keeps the first check busy
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true; $0.alertOnly = false }
        defer { cleanup() }

        let first = Task { await vm.check() }
        await waitUntil { vm.isChecking }
        XCTAssertTrue(vm.isChecking)
        vm.settings.thresholdPercent = 30   // must not be dropped while busy
        await first.value
        await waitUntil { spy.posts.count == 2 }

        XCTAssertEqual(spy.posts.count, 2)
        XCTAssertTrue(try XCTUnwrap(spy.posts.last?.0.attachments.first).blocks[0].mrkdwn.contains("threshold 30%"))
    }

    @MainActor
    func testDisablingDuringScanPostsNothing() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.scanDelay = 300_000_000
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true }
        defer { cleanup() }

        let running = Task { await vm.check() }
        await waitUntil { spy.scans == 1 }
        vm.settings.enabled = false   // mid-scan
        await running.value
        await settle()

        XCTAssertTrue(spy.posts.isEmpty)
        XCTAssertTrue(vm.lastReadings.isEmpty, "a stale check must not restore state reset by disable")
    }

    @MainActor
    func testDisablingDuringVolumeReadPostsNothing() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.readDelay = 300_000_000
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true }
        defer { cleanup() }

        let running = Task { await vm.check() }
        await waitUntil { spy.reads == 1 }
        vm.settings.enabled = false   // mid-read
        await running.value
        await settle()

        XCTAssertTrue(spy.posts.isEmpty)
        XCTAssertEqual(spy.notifications, 0)
        XCTAssertTrue(vm.lastReadings.isEmpty, "a stale read must not restore state reset by disable")
    }

    @MainActor
    func testStaleScanDoesNotRefillTheCache() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.scanDelay = 300_000_000
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true }
        defer { cleanup() }

        let running = Task { await vm.check() }
        await waitUntil { spy.scans == 1 }
        vm.settings.enabled = false   // reset while scanning
        await running.value
        vm.settings.enabled = true    // new timer: its check must scan again
        await waitUntil { spy.scans == 2 }

        XCTAssertEqual(spy.scans, 2)
        vm.settings.enabled = false
    }

    @MainActor
    func testTimerCountsWallClockTime() async throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { $0.alertOnly = false; $0.intervalMinutes = 60 }
        defer { cleanup() }

        vm.settings.enabled = true
        await waitUntil { spy.posts.count == 1 }
        // The Mac slept 61 minutes: Task.sleep didn't count it, the wall
        // clock did. The next slice must notice the check is due.
        spy.now = spy.now.addingTimeInterval(61 * 60)
        await waitUntil { spy.posts.count == 2 }

        XCTAssertEqual(spy.posts.count, 2)
        vm.settings.enabled = false
    }

    @MainActor
    func testDailyScheduleWaitsForItsTime() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        let (vm, cleanup) = try makeVM(spy) { $0.schedule = .daily; $0.alertOnly = false }
        defer { cleanup() }

        vm.settings.enabled = true
        await waitUntil { vm.nextCheck != nil }
        await settle()
        XCTAssertTrue(spy.posts.isEmpty, "enabling a daily schedule must not check right away")

        vm.settings.thresholdPercent = 30   // no immediate recheck either
        await settle()
        XCTAssertTrue(spy.posts.isEmpty)

        // The daily time arrives (by wall clock): one check.
        spy.now = try XCTUnwrap(vm.nextCheck).addingTimeInterval(1)
        await waitUntil { spy.posts.count == 1 }
        XCTAssertEqual(spy.posts.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(vm.nextCheck), spy.now, "next run moves to the following day")
        vm.settings.enabled = false
    }

    @MainActor
    func testMissedDailyRunIsCaughtUpAtLaunch() async throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true; $0.schedule = .daily; $0.alertOnly = false }
        defer { cleanup(); vm.settings.enabled = false }
        // Last daily run two days ago: today's (or yesterday's) was missed.
        vm.setLastDailyRunForTesting(spy.now.addingTimeInterval(-2 * 24 * 3600))

        vm.start()
        await waitUntil { spy.posts.count == 1 }
        XCTAssertEqual(spy.posts.count, 1)
    }

    @MainActor
    func testNoCatchUpAtLaunchWhenNothingWasMissedButReadingsShow() async throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true; $0.schedule = .daily; $0.alertOnly = false }
        defer { cleanup(); vm.settings.enabled = false }
        vm.setLastDailyRunForTesting(spy.now)

        vm.start()
        await waitUntil { !vm.lastReadings.isEmpty }
        await settle()
        XCTAssertTrue(spy.posts.isEmpty)
        XCTAssertEqual(spy.notifications, 0)
        XCTAssertFalse(vm.lastReadings.isEmpty, "the tab still gets numbers")
        XCTAssertNil(vm.lastChecked, "a read-only refresh isn't a check")
    }

    @MainActor
    func testDailyEditsRefreshReadingsOnly() async throws {
        let spy = Spy()
        spy.free["/Volumes/B"] = 1 * gb
        let (vm, cleanup) = try makeVM(spy) { $0.schedule = .daily; $0.alertOnly = false }
        defer { cleanup() }

        vm.settings.enabled = true
        await waitUntil { vm.nextCheck != nil }
        vm.settings.paths = ["/", "/Volumes/B"]
        await waitUntil { vm.lastReadings.map(\.path) == ["/", "/Volumes/B"] }
        await settle()
        XCTAssertEqual(vm.lastReadings.map(\.path), ["/", "/Volumes/B"])
        XCTAssertTrue(spy.posts.isEmpty)
        XCTAssertEqual(spy.notifications, 0)
        vm.settings.enabled = false
    }

    @MainActor
    func testMissedDailyCheckRunsOnWake() async throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { $0.schedule = .daily; $0.alertOnly = false }
        defer { cleanup() }

        vm.settings.enabled = true
        await waitUntil { vm.nextCheck != nil }
        let due = try XCTUnwrap(vm.nextCheck)
        vm.handleWake(now: due.addingTimeInterval(3600))   // asleep at the daily time
        await waitUntil { spy.posts.count == 1 }
        XCTAssertEqual(spy.posts.count, 1)
        vm.settings.enabled = false
    }

    @MainActor
    func testQueuedCheckIsDroppedWhenDisabled() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.scanDelay = 300_000_000
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true }
        defer { cleanup() }

        let running = Task { await vm.check() }
        await waitUntil { spy.scans == 1 }
        await vm.check()              // queued behind the running one
        vm.settings.enabled = false
        await running.value
        await settle()

        XCTAssertEqual(spy.scans, 1)
        XCTAssertTrue(spy.posts.isEmpty)
    }

    @MainActor
    func testRescheduleDuringRecheckStillReports() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.scanDelay = 300_000_000
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true }
        defer { cleanup() }

        vm.settings.thresholdPercent = 15             // recheck starts after 10 ms
        await waitUntil { spy.scans == 1 }           // …and is now scanning
        vm.settings.intervalMinutes = 30              // reschedule mid-check
        await waitUntil { spy.posts.count == 1 }
        await settle()

        // The interrupted check is superseded, not lost: one report arrives.
        XCTAssertEqual(spy.posts.count, 1)
        XCTAssertTrue(try XCTUnwrap(spy.posts.first?.0.attachments.first).blocks[0].mrkdwn.contains("threshold 15%"))
        vm.settings.enabled = false
    }

    @MainActor
    func testNotificationDeliveredBeforeRescheduleIsNotRepeated() async throws {
        let spy = Spy()
        spy.free["/"] = 5 * gb
        spy.notifyDelay = 300_000_000
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true }
        defer { cleanup() }

        let running = Task { await vm.check() }
        await waitUntil { spy.notifyStarted }            // inside notify
        vm.settings.intervalMinutes = 30                 // reschedule while notifying
        await running.value
        await waitUntil { spy.notifications >= 1 && !vm.isChecking }
        await settle()
        await vm.check()

        XCTAssertEqual(spy.notifications, 1, "the delivered alert must not be shown again")
        vm.settings.enabled = false
    }

    @MainActor
    func testDisableAndReenableDropsThePendingRecheck() async throws {
        let spy = Spy()
        spy.free["/"] = 26 * gb
        let (vm, cleanup) = try makeVM(spy) { $0.enabled = true; $0.alertOnly = false }
        defer { cleanup() }

        vm.settings.thresholdPercent = 30   // recheck pending for 10 ms
        vm.settings.enabled = false         // cancels it…
        vm.settings.enabled = true          // …and the new timer checks once
        await waitUntil { spy.posts.count >= 1 }
        await settle()

        XCTAssertEqual(spy.posts.count, 1)
        vm.settings.enabled = false
    }

    @MainActor
    func testOverdueCheckRunsOnWake() async throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { $0.alertOnly = false }
        defer { cleanup() }

        vm.settings.enabled = true   // timer: one check now, next in 60 min
        await waitUntil { spy.posts.count == 1 }
        XCTAssertEqual(spy.posts.count, 1)

        vm.handleWake(now: Date().addingTimeInterval(30 * 60))   // not due yet
        await settle()
        XCTAssertEqual(spy.posts.count, 1)

        vm.handleWake(now: Date().addingTimeInterval(2 * 3600))  // overdue after sleep
        await waitUntil { spy.posts.count == 2 }
        XCTAssertEqual(spy.posts.count, 2)
        vm.settings.enabled = false
    }

    @MainActor
    func testNoSlackWithoutTokenOrChannel() async throws {
        let spy = Spy()
        spy.free["/"] = 1 * gb
        let (noToken, c1) = try makeVM(spy, token: nil) { _ in }
        defer { c1() }
        await noToken.check()
        let (noChannel, c2) = try makeVM(spy) { $0.slackChannel = "" }
        defer { c2() }
        await noChannel.check()
        XCTAssertTrue(spy.posts.isEmpty)
        XCTAssertEqual(spy.notifications, 2)
        // Nothing would be sent, so the home folder isn't walked either.
        XCTAssertEqual(spy.scans, 0)
    }

    @MainActor
    func testRemovingTokenDuringScanPostsNothing() async throws {
        let spy = Spy()
        spy.free["/"] = 1 * gb
        spy.scanDelay = 300_000_000
        let (vm, cleanup) = try makeVM(spy) { _ in }
        defer { cleanup() }

        let running = Task { await vm.check() }
        await waitUntil { spy.scans == 1 }
        vm.removeSlackToken()
        await running.value

        XCTAssertEqual(spy.scans, 1)
        XCTAssertTrue(spy.posts.isEmpty)
    }

    @MainActor
    func testBlankTokenNeverDeletesTheStoredOne() throws {
        let spy = Spy()
        let (vm, cleanup) = try makeVM(spy) { _ in }
        defer { cleanup() }

        vm.refreshSlackToken()
        XCTAssertTrue(vm.hasSlackToken)
        vm.saveSlackToken("   ")
        vm.refreshSlackToken()
        XCTAssertTrue(vm.hasSlackToken)
        vm.removeSlackToken()
        XCTAssertFalse(vm.hasSlackToken)
    }

    // MARK: - Keychain

    func testKeychainWriteReadDelete() {
        let kc = Keychain(service: "fun.burrow.tests.\(UUID().uuidString)")
        defer { kc.delete("token") }
        XCTAssertNil(kc.read("token"))
        XCTAssertTrue(kc.write("xoxb-1", for: "token"))
        XCTAssertEqual(kc.read("token"), "xoxb-1")
        XCTAssertTrue(kc.write("xoxb-2", for: "token"))
        XCTAssertEqual(kc.read("token"), "xoxb-2")
        XCTAssertTrue(kc.write("", for: "token"))
        XCTAssertNil(kc.read("token"))
    }
}
