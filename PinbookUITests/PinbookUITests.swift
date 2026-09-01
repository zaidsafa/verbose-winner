import XCTest

final class PinbookUITests: XCTestCase {
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
