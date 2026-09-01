import XCTest

final class PinbookUITests: XCTestCase {
    @MainActor
    func testNativeFilesPickersOpenWithoutSaving() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PinbookFixture", "populated",
            "-PinbookTab", "options",
            "-PinbookSkin", "paperGlass",
            "-PinbookTheme", "dark",
        ]
        app.launch()

        let backupLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Backup & Recovery")).firstMatch
        XCTAssertTrue(backupLink.waitForExistence(timeout: 5))
        backupLink.tap()
        XCTAssertTrue(app.navigationBars["Backup & Recovery"].waitForExistence(timeout: 5))

        app.buttons["Export backup"].tap()
        XCTAssertTrue(nativeFilesPicker(in: app).waitForExistence(timeout: 8))
        let exportEvidence = XCTAttachment(screenshot: app.screenshot())
        exportEvidence.name = "Pinbook native Files export picker"
        exportEvidence.lifetime = .keepAlways
        add(exportEvidence)
        app.terminate()

        app.launch()
        XCTAssertTrue(backupLink.waitForExistence(timeout: 5))
        backupLink.tap()
        XCTAssertTrue(app.navigationBars["Backup & Recovery"].waitForExistence(timeout: 5))
        app.buttons["Import and preview"].tap()
        XCTAssertTrue(nativeFilesPicker(in: app).waitForExistence(timeout: 8))
        let importEvidence = XCTAttachment(screenshot: app.screenshot())
        importEvidence.name = "Pinbook native Files import picker"
        importEvidence.lifetime = .keepAlways
        add(importEvidence)
        app.terminate()
    }

    @MainActor
    private func nativeFilesPicker(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label == %@ OR label == %@",
            "Browse View (Picker)",
            "Save",
            "Recents"
        )).firstMatch
    }

    @MainActor
    func testBackupRecoveryCenterKeepsPrivacyGuidanceReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PinbookFixture", "populated",
            "-PinbookTab", "options",
            "-PinbookSkin", "paperGlass",
            "-PinbookTheme", "dark",
        ]
        app.launch()

        let backupLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Backup & Recovery")).firstMatch
        XCTAssertTrue(backupLink.waitForExistence(timeout: 5))
        backupLink.tap()
        XCTAssertTrue(app.navigationBars["Backup & Recovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export backup"].exists)
        XCTAssertTrue(app.buttons["Import and preview"].exists)

        let privacyFooter = app.descendants(matching: .any)["backup-history-privacy-footer"]
        scrollToHittable(privacyFooter, in: app)
        assertClearsTabBar(privacyFooter, in: app)

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook dark local backup and recovery center"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func testArabicBackupRecoveryCenterUsesRTLLocalizedCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(ar)",
            "-AppleLocale", "ar_SA",
            "-PinbookFixture", "populated",
            "-PinbookTab", "options",
            "-PinbookSkin", "paperGlass",
            "-PinbookTheme", "light",
        ]
        app.launch()

        let backupLink = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@",
            "النسخ الاحتياطي والاستعادة"
        )).firstMatch
        XCTAssertTrue(backupLink.waitForExistence(timeout: 5))
        backupLink.tap()
        XCTAssertTrue(app.navigationBars["النسخ الاحتياطي والاستعادة"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["تصدير نسخة احتياطية"].exists)
        XCTAssertTrue(app.buttons["استيراد ومعاينة"].exists)

        let privacyFooter = app.descendants(matching: .any)["backup-history-privacy-footer"]
        scrollToHittable(privacyFooter, in: app)
        assertClearsTabBar(privacyFooter, in: app)

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook Arabic RTL local backup and recovery center"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func testFinalBooksAndStatementContentClearsTheTabBar() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PinbookFixture", "populated",
            "-PinbookTab", "options",
            "-PinbookSkin", "paperGlass",
            "-PinbookTheme", "dark",
        ]
        app.launch()

        let booksLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Books & currencies")).firstMatch
        XCTAssertTrue(booksLink.waitForExistence(timeout: 5))
        booksLink.tap()
        let finalBookRow = app.descendants(matching: .any)["books-currencies-final-row"]
        scrollToHittable(finalBookRow, in: app)
        assertClearsTabBar(finalBookRow, in: app)

        app.navigationBars.buttons["Options"].tap()
        let statementsLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Statements")).firstMatch
        XCTAssertTrue(statementsLink.waitForExistence(timeout: 5))
        statementsLink.tap()
        let preparePDF = app.buttons["Prepare PDF"]
        XCTAssertTrue(preparePDF.waitForExistence(timeout: 5))
        preparePDF.tap()

        let finalStatementHelp = app.descendants(matching: .any)["statements-final-help"]
        scrollToHittable(finalStatementHelp, in: app)
        assertClearsTabBar(finalStatementHelp, in: app)

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook dark statements with reachable final help"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.exists {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func assertClearsTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        for _ in 0..<4 where element.frame.maxY > tabBar.frame.minY {
            app.swipeUp()
        }
        XCTAssertLessThanOrEqual(element.frame.maxY, tabBar.frame.minY)
    }
}
