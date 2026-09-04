import XCTest

final class PinbookUITests: XCTestCase {
    @MainActor
    func testFirstRunLanguageSelectionUpdatesIntroductionAndRTLImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-PinbookFixture", "empty", "-PinbookOnboarding", "show",
        ]
        app.launch()
        let languageControl = app.buttons["onboarding-language-menu"]
        XCTAssertTrue(languageControl.waitForExistence(timeout: 5))
        languageControl.tap()
        app.buttons["language-ar"].tap()
        XCTAssertTrue(app.navigationBars["اللغة"].waitForExistence(timeout: 5))
        app.buttons["language-done"].tap()
        XCTAssertTrue(app.staticTexts["مرحبًا بك في Pinbook"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(languageControl.frame.midX, app.buttons["onboarding-skip"].frame.midX)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook live first-run Arabic selection and RTL"
        evidence.lifetime = .keepAlways
        add(evidence)

        languageControl.tap()
        app.buttons["language-zh-Hans"].tap()
        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 5))
        app.buttons["language-done"].tap()
        XCTAssertTrue(app.staticTexts["欢迎使用 Pinbook"].waitForExistence(timeout: 5))
        XCTAssertLessThan(languageControl.frame.midX, app.buttons["onboarding-skip"].frame.midX)
    }

    @MainActor
    func testSettingsLanguagePersistsAndSystemDefaultRestoresPhoneLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-PinbookFixture", "empty", "-PinbookTab", "options",
        ]
        app.launch()
        app.buttons["options-language"].tap()
        app.buttons["language-zh-Hans"].tap()
        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["-PinbookPreserveLanguage"]
        app.launch()
        XCTAssertTrue(app.buttons["options-language"].waitForExistence(timeout: 5))
        app.buttons["options-language"].tap()
        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 5))
        app.buttons["language-system"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["language-system"].isSelected)
    }

    @MainActor
    func testWorldCurrencyPickerIsSearchableAndShowsSymbols() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PinbookFixture", "populated",
            "-PinbookTab", "options",
            "-PinbookTheme", "light",
        ]
        app.launch()

        let booksLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Books & currencies")).firstMatch
        XCTAssertTrue(booksLink.waitForExistence(timeout: 5))
        booksLink.tap()

        let currencyLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Choose currencies")).firstMatch
        XCTAssertTrue(currencyLink.waitForExistence(timeout: 5))
        currencyLink.tap()
        XCTAssertTrue(app.navigationBars["Favorite currencies"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["currency-AED"].exists)

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook searchable world currency picker with symbols"
        evidence.lifetime = .keepAlways
        add(evidence)

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("USD")
        XCTAssertTrue(app.descendants(matching: .any)["currency-USD"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSimplifiedChineseFirstRunIntroductionIsLocalized() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-PinbookFixture", "empty",
            "-PinbookOnboarding", "show",
            "-PinbookTheme", "light",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["欢迎使用 Pinbook"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["记住每一笔支出"].exists)
        XCTAssertTrue(app.buttons["继续"].exists)

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook Simplified Chinese first-run introduction"
        evidence.lifetime = .keepAlways
        add(evidence)

        app.buttons["继续"].tap()
        XCTAssertTrue(app.staticTexts["选择你的货币"].waitForExistence(timeout: 5))
        app.buttons["继续"].tap()
        XCTAssertTrue(app.staticTexts["清楚掌握剩余金额"].waitForExistence(timeout: 5))
        app.buttons["继续"].tap()
        XCTAssertTrue(app.staticTexts["默认保护隐私"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["全新开始"].exists)
    }

    @MainActor
    func testNightInkLightAppearancePickerStaysReadableAndDescriptive() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PinbookFixture", "populated",
            "-PinbookTab", "options",
            "-PinbookSkin", "nightInk",
            "-PinbookTheme", "light",
        ]
        app.launch()

        let appearanceLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Appearance")).firstMatch
        XCTAssertTrue(appearanceLink.waitForExistence(timeout: 5))
        appearanceLink.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Deep navy designed for low light"].exists)
        XCTAssertTrue(app.staticTexts["Warm paper with calm jade glass"].exists)

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook Night Ink light-mode descriptive skin picker"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

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
        XCTAssertTrue(nativeFilesPickerIsPresented(in: app, covering: "Export backup"))
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
        XCTAssertTrue(nativeFilesPickerIsPresented(in: app, covering: "Import and preview"))
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
    private func nativeFilesPickerIsPresented(in app: XCUIApplication, covering buttonLabel: String) -> Bool {
        if nativeFilesPicker(in: app).waitForExistence(timeout: 3) { return true }
        return !app.buttons[buttonLabel].isHittable
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
