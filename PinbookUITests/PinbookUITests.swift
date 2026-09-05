import XCTest

final class PinbookUITests: XCTestCase {
    @MainActor
    func testChineseInvitationWorkflowRequiresThreeSeparateConsents() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationWorkflow", "-PinbookLanguage", "zh-Hans"]
        app.launch()
        let accountReview = app.buttons["invitation-account-review"]
        XCTAssertTrue(accountReview.waitForExistence(timeout: 10)); accountReview.tap()
        let accountConsent = app.switches.matching(identifier: "invitation-account-consent").firstMatch
        XCTAssertTrue(accountConsent.waitForExistence(timeout: 5)); reveal(accountConsent, in: app); accountConsent.switches.firstMatch.tap()
        let access = app.buttons["invitation-account-access"]; reveal(access, in: app); access.tap()
        let accountContinue = app.buttons["invitation-account-continue"]
        XCTAssertTrue(accountContinue.waitForExistence(timeout: 5)); accountContinue.tap()
        let deviceConsent = app.switches.matching(identifier: "device-registration-consent").firstMatch
        XCTAssertTrue(deviceConsent.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["device-registration-register"].isEnabled)
        reveal(deviceConsent, in: app)
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Chinese separate device registration consent"
        screen.lifetime = .keepAlways; add(screen)
        deviceConsent.switches.firstMatch.tap()
        let register = app.buttons["device-registration-register"]; reveal(register, in: app); register.tap()
        let deviceContinue = app.buttons["device-registration-continue"]
        XCTAssertTrue(deviceContinue.waitForExistence(timeout: 5)); deviceContinue.tap()
        let membershipReview = app.buttons["membership-review"]
        XCTAssertTrue(membershipReview.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["membership-join"].exists)
        membershipReview.tap()
        let membershipConsent = app.switches.matching(identifier: "membership-consent").firstMatch
        XCTAssertTrue(membershipConsent.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["membership-join"].isEnabled)
        reveal(membershipConsent, in: app); membershipConsent.switches.firstMatch.tap()
        let join = app.buttons["membership-join"]; reveal(join, in: app); join.tap()
        XCTAssertTrue(app.buttons["membership-done"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testArabicExistingAccountStillRequiresSeparateDeviceAndMembershipConsent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationWorkflow",
            "-PinbookInvitationWorkflowScenario", "existing", "-PinbookLanguage", "ar", "-PinbookTheme", "dark"]
        app.launch()
        let accountReview = app.buttons["invitation-account-review"]
        XCTAssertTrue(accountReview.waitForExistence(timeout: 10)); accountReview.tap()
        XCTAssertFalse(app.switches["invitation-account-consent"].exists)
        let access = app.buttons["invitation-account-access"]; reveal(access, in: app); access.tap()
        let next = app.buttons["invitation-account-continue"]; XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        let consent = app.switches.matching(identifier: "device-registration-consent").firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons["device-registration-register"].label, "سجّل هذا الجهاز")
        reveal(consent, in: app)
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Arabic device registration with fresh consent"
        screen.lifetime = .keepAlways; add(screen)
        consent.switches.firstMatch.tap()
        let register = app.buttons["device-registration-register"]; reveal(register, in: app); register.tap()
        let deviceContinue = app.buttons["device-registration-continue"]; XCTAssertTrue(deviceContinue.waitForExistence(timeout: 5)); deviceContinue.tap()
        let review = app.buttons["membership-review"]; XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
        XCTAssertTrue(app.switches.matching(identifier: "membership-consent").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["membership-join"].isEnabled)
    }
    @MainActor
    func testDeviceRetryRequiresNewConsentForEveryAttempt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationWorkflow",
            "-PinbookInvitationWorkflowScenario", "retry", "-PinbookLanguage", "en"]
        app.launch(); advanceToDevice(app)
        for expected in ["An earlier registration is still pending. Wait until the time shown, then continue.",
                         "The previous attempt was not found. Confirm again to retry with the same device."] {
            let consent = app.switches.matching(identifier: "device-registration-consent").firstMatch
            XCTAssertTrue(consent.waitForExistence(timeout: 5)); reveal(consent, in: app); consent.switches.firstMatch.tap()
            let action = app.buttons["device-registration-register"]; reveal(action, in: app); action.tap()
            let status = app.staticTexts["device-registration-status"]
            XCTAssertTrue(status.waitForExistence(timeout: 5)); XCTAssertEqual(status.label, expected)
            XCTAssertFalse(app.buttons["device-registration-register"].isEnabled)
        }
        let consent = app.switches.matching(identifier: "device-registration-consent").firstMatch
        reveal(consent, in: app); consent.switches.firstMatch.tap()
        let action = app.buttons["device-registration-register"]; reveal(action, in: app); action.tap()
        XCTAssertTrue(app.buttons["device-registration-continue"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testUncertainDeviceRegistrationCannotAdvanceOrReplayAutomatically() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationWorkflow",
            "-PinbookInvitationWorkflowScenario", "uncertain", "-PinbookLanguage", "en"]
        app.launch(); advanceToDevice(app)
        let consent = app.switches.matching(identifier: "device-registration-consent").firstMatch
        reveal(consent, in: app); consent.switches.firstMatch.tap()
        let action = app.buttons["device-registration-register"]; reveal(action, in: app); action.tap()
        XCTAssertTrue(app.staticTexts["Registration could not be confirmed. Continue to check the previous attempt before trying again."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["device-registration-continue"].exists)
        XCTAssertFalse(app.buttons["device-registration-register"].isEnabled)
    }
    @MainActor
    func testBackgroundDuringDeviceConsentClosesWholeWorkflow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationWorkflow", "-PinbookLanguage", "en"]
        app.launch(); advanceToDevice(app)
        let consent = app.switches.matching(identifier: "device-registration-consent").firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 5)); reveal(consent, in: app); consent.switches.firstMatch.tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Team setup closed. Open the invitation again to continue."].waitForExistence(timeout: 5))
        XCTAssertFalse(consent.exists); XCTAssertFalse(app.staticTexts["device-registration-account"].exists)
        XCTAssertFalse(app.buttons["device-registration-register"].exists)
    }
    @MainActor private func advanceToDevice(_ app: XCUIApplication) {
        let review = app.buttons["invitation-account-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        let consent = app.switches.matching(identifier: "invitation-account-consent").firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 5)); reveal(consent, in: app); consent.switches.firstMatch.tap()
        let access = app.buttons["invitation-account-access"]; reveal(access, in: app); access.tap()
        let next = app.buttons["invitation-account-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        XCTAssertTrue(app.switches.matching(identifier: "device-registration-consent").firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
    }
    @MainActor
    func testInvitationNewAccountUsesChineseCopyAndSeparateUncheckedConsent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationAccount", "-PinbookLanguage", "zh-Hans"]
        app.launch()
        let review = app.buttons["invitation-account-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["invitation-account-access"].exists)
        review.tap()
        let access = app.buttons["invitation-account-access"]
        XCTAssertTrue(access.waitForExistence(timeout: 5)); XCTAssertFalse(access.isEnabled)
        XCTAssertEqual(access.label, "继续登录")
        XCTAssertEqual(app.staticTexts["invitation-account-privacy"].label, "登录不会注册此设备，也不会让您加入团队。")
        XCTAssertFalse(app.staticTexts["invitation-account-identity"].exists)
        let consent = app.switches.matching(identifier: "invitation-account-consent").firstMatch
        for _ in 0..<4 where !consent.isHittable { app.swipeUp() }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Chinese invitation account preflight with unchecked consent"
        before.lifetime = .keepAlways; add(before)
        consent.switches.firstMatch.tap()
        XCTAssertTrue(access.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        for _ in 0..<4 where !access.isHittable { app.swipeUp() }
        access.tap()
        XCTAssertTrue(app.buttons["invitation-account-done"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["invitation-account-identity"].label, "public-test-account")
        XCTAssertFalse(app.buttons["membership-join"].exists)
    }
    @MainActor
    func testInvitationExistingAccountIsExplicitAndUsesArabicLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationAccount",
            "-PinbookInvitationAccountScenario", "existing", "-PinbookLanguage", "ar", "-PinbookTheme", "dark"]
        app.launch()
        let review = app.buttons["invitation-account-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        let access = app.buttons["invitation-account-access"]
        XCTAssertTrue(access.waitForExistence(timeout: 5)); XCTAssertTrue(access.isEnabled)
        XCTAssertEqual(access.label, "المتابعة بهذا الحساب")
        XCTAssertEqual(app.staticTexts["invitation-account-identity"].label, "public-test-account")
        XCTAssertFalse(app.switches["invitation-account-consent"].exists)
        XCTAssertFalse(app.buttons["invitation-account-done"].exists)
        for _ in 0..<4 where !access.isHittable { app.swipeUp() }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Arabic existing invitation account explicit continuation"
        before.lifetime = .keepAlways; add(before)
        access.tap()
        XCTAssertTrue(app.buttons["invitation-account-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["membership-join"].exists)
    }
    @MainActor
    func testInvitationAccountUncertaintyDoesNotOfferSignInReplay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationAccount",
            "-PinbookInvitationAccountScenario", "uncertain", "-PinbookLanguage", "en"]
        app.launch()
        let review = app.buttons["invitation-account-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        let consent = app.switches.matching(identifier: "invitation-account-consent").firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        for _ in 0..<4 where !consent.isHittable { app.swipeUp() }
        consent.switches.firstMatch.tap()
        let access = app.buttons["invitation-account-access"]
        for _ in 0..<4 where !access.isHittable { app.swipeUp() }
        access.tap()
        XCTAssertTrue(app.staticTexts["Account access could not be confirmed. Close this screen before signing in again."].waitForExistence(timeout: 5))
        XCTAssertFalse(access.exists); XCTAssertFalse(review.exists)
        XCTAssertFalse(app.buttons["invitation-account-done"].exists)
    }
    @MainActor
    func testInvitationBackgroundClearsAccountConsentWithoutResuming() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamInvitationAccount", "-PinbookLanguage", "en"]
        app.launch()
        let review = app.buttons["invitation-account-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        let consent = app.switches.matching(identifier: "invitation-account-consent").firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        for _ in 0..<4 where !consent.isHittable { app.swipeUp() }
        consent.switches.firstMatch.tap()
        XCTAssertTrue(app.buttons["invitation-account-access"].isEnabled)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Account screen closed. Open the invitation again to continue."].waitForExistence(timeout: 5))
        XCTAssertFalse(consent.exists); XCTAssertFalse(app.buttons["invitation-account-access"].exists)
        XCTAssertFalse(app.staticTexts["invitation-account-team"].exists)
    }
    @MainActor
    func testPendingRetryUsesChineseWarningAndRequiresNewConsent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamMembership",
            "-PinbookMembershipScenario", "retry-pending", "-PinbookLanguage", "zh-Hans"]
        app.launch()
        let check = app.buttons["membership-review"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        XCTAssertEqual(check.label, "检查上次加入尝试")
        XCTAssertFalse(app.buttons["membership-join"].exists)
        check.tap()
        let retry = app.buttons["membership-join"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(retry.label, "重试加入")
        XCTAssertFalse(retry.isEnabled)
        XCTAssertEqual(app.staticTexts["membership-status"].label,
            "上次加入尝试仍在等待处理。请再次确认，以使用同一邀请重试。")
        let consent = app.switches.matching(identifier: "membership-consent").firstMatch
        for _ in 0..<4 where !consent.isHittable { app.swipeUp() }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Chinese pending retry with fresh unchecked consent"
        before.lifetime = .keepAlways; add(before)
        consent.switches.firstMatch.tap()
        XCTAssertTrue(retry.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
        retry.tap()
        XCTAssertTrue(app.buttons["membership-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["membership-join"].exists)
    }

    @MainActor
    func testPreviousJoinConfirmationDoesNotOfferAnotherJoin() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamMembership",
            "-PinbookMembershipScenario", "retry-joined", "-PinbookLanguage", "en"]
        app.launch()
        let check = app.buttons["membership-review"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        XCTAssertEqual(check.label, "Check previous join")
        check.tap()
        XCTAssertTrue(app.buttons["membership-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["membership-join"].exists)
        XCTAssertFalse(app.switches["membership-consent"].exists)
        XCTAssertFalse(app.buttons["membership-review"].exists)
    }

    @MainActor
    func testRetryBackgroundClearsConsentAndCannotResumeJoin() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamMembership",
            "-PinbookMembershipScenario", "retry-pending", "-PinbookLanguage", "en"]
        app.launch()
        let check = app.buttons["membership-review"]
        XCTAssertTrue(check.waitForExistence(timeout: 10)); check.tap()
        let consent = app.switches.matching(identifier: "membership-consent").firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        for _ in 0..<4 where !consent.isHittable { app.swipeUp() }
        consent.switches.firstMatch.tap()
        XCTAssertTrue(app.buttons["membership-join"].isEnabled)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Membership screen closed. Open it again to continue."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["membership-account"].exists)
        XCTAssertFalse(app.buttons["membership-join"].exists)
        XCTAssertFalse(app.switches["membership-consent"].exists)
    }

    @MainActor
    func testProminentButtonPaletteRemainsVisibleAcrossSkins() throws {
        let app = XCUIApplication()
        for skin in ["paperGlass", "cleanLedger", "softPastel", "editorial", "nightInk"] {
            for appearance in ["light", "dark"] {
                app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamMembership",
                    "-PinbookSkin", skin, "-PinbookTheme", appearance, "-PinbookLanguage", "en"]
                app.launch()
                let review = app.buttons["membership-review"]
                XCTAssertTrue(review.waitForExistence(timeout: 10))
                XCTAssertTrue(review.isEnabled)
                XCTAssertTrue(review.isHittable)
                let evidence = XCTAttachment(screenshot: app.screenshot())
                evidence.name = "Prominent button palette \(skin) \(appearance)"
                evidence.lifetime = .keepAlways
                add(evidence)
                app.terminate()
            }
        }
        // Attachments require visual inspection; hit-testing alone is not a
        // contrast assertion. Numeric accent/label tests cover all ten palettes.
    }

    @MainActor
    func testMembershipRequiresUncheckedConsentAndUsesChineseCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamMembership", "-PinbookLanguage", "zh-Hans"]
        app.launch()
        let review = app.buttons["membership-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertEqual(review.label, "查看邀请")
        XCTAssertFalse(app.buttons["membership-join"].exists)
        review.tap()
        let join = app.buttons["membership-join"]
        XCTAssertTrue(join.waitForExistence(timeout: 5))
        XCTAssertFalse(join.isEnabled)
        XCTAssertEqual(app.staticTexts["membership-role"].label, "成员")
        let consent = app.switches.matching(identifier: "membership-consent").firstMatch
        for _ in 0..<4 where !consent.isHittable { app.swipeUp() }
        consent.switches.firstMatch.tap()
        XCTAssertTrue(join.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        for _ in 0..<4 where !join.isHittable { app.swipeUp() }
        join.tap()
        XCTAssertTrue(app.buttons["membership-done"].waitForExistence(timeout: 5))
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Chinese membership confirmation"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func testUnknownMembershipOffersCheckNotAnotherJoin() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamMembership", "-PinbookMembershipScenario", "uncertain", "-PinbookLanguage", "en"]
        app.launch()
        let review = app.buttons["membership-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        let consent = app.switches.matching(identifier: "membership-consent").firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        for _ in 0..<4 where !consent.isHittable { app.swipeUp() }
        consent.switches.firstMatch.tap()
        let join = app.buttons["membership-join"]
        for _ in 0..<4 where !join.isHittable { app.swipeUp() }
        join.tap()
        let check = app.buttons["membership-check"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["membership-join"].exists)
        XCTAssertFalse(app.buttons["membership-review"].exists)
        for _ in 0..<4 where !check.isHittable { app.swipeUp() }
        check.tap()
        XCTAssertTrue(app.buttons["membership-done"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMembershipBackgroundClearsDetailsAndConsent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamMembership", "-PinbookLanguage", "en"]
        app.launch()
        let review = app.buttons["membership-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        XCTAssertTrue(app.staticTexts["membership-account"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Membership screen closed. Open it again to continue."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["membership-account"].exists)
        XCTAssertFalse(app.switches["membership-consent"].exists)
        XCTAssertFalse(app.buttons["membership-join"].exists)
    }

    @MainActor
    func testRecoveryKeySetupRequiresConsentAndClearsOnBackground() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamKeySetup", "-PinbookLanguage", "en"]
        app.launch()
        let create = app.buttons["key-setup-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        XCTAssertFalse(create.isEnabled)
        XCTAssertTrue(app.staticTexts["Anyone with this key and your archive can read your notes. Save the key separately. Pinbook cannot recover a lost key."].exists)
        // SwiftUI exposes the labeled row as a Switch containing the actual
        // native switch. Tap that control, not the center of the multiline label.
        let consent = app.switches.matching(identifier: "key-setup-consent").firstMatch
        consent.switches.firstMatch.tap()
        XCTAssertTrue(create.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        create.tap()
        XCTAssertTrue(app.buttons["key-setup-export"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["key-setup-finish"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Pinbook recovery key setup before file export"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(create.isEnabled)
        XCTAssertFalse(app.secureTextFields["key-setup-confirmation"].exists)
    }

    @MainActor
    func testReceivedNotePreviewRequiresConfirmationBeforeRestore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamRecoveryPreview", "-PinbookLanguage", "en"]
        app.launch()
        let apply = app.buttons["team-restore-preview-apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["team-fixture-restored"].exists)
        apply.tap()
        // UIKit supplies the dialog's Cancel action and drops its SwiftUI identifier.
        // This fixture explicitly selects English; the presented hierarchy has one Cancel.
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertFalse(app.staticTexts["team-fixture-restored"].exists)
        apply.tap()
        let confirm = app.buttons.matching(identifier: "team-restore-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["team-fixture-restored"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["team-fixture-error"].exists)
    }

    @MainActor
    func testReceivedNotePreviewUsesChineseCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PinbookFixture", "empty", "-PinbookTeamRecoveryPreview", "-PinbookLanguage", "zh-Hans"]
        app.launch()
        let apply = app.buttons["team-restore-preview-apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        XCTAssertNotEqual(apply.label, "Apply restore")
        XCTAssertTrue(app.staticTexts["团队"].exists)
        XCTAssertTrue(app.staticTexts["绝不会覆盖原有笔记。任何冲突都会阻止整个恢复操作。不会恢复团队访问权限或送达回执。"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Pinbook Chinese received-note recovery preview"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTraditionalChineseUrduAndSystemSelectionAcrossIntroductionPages() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-PinbookFixture", "empty", "-PinbookOnboarding", "show",
            "-PinbookTheme", "light",
        ]
        app.launch()
        let languageControl = app.buttons["onboarding-language-menu"]
        XCTAssertTrue(languageControl.waitForExistence(timeout: 5))
        languageControl.tap()
        app.buttons["language-zh-Hant"].tap()
        XCTAssertTrue(app.navigationBars["語言"].waitForExistence(timeout: 5))
        app.buttons["language-done"].tap()
        XCTAssertTrue(app.staticTexts["歡迎使用 Pinbook"].waitForExistence(timeout: 5))
        let chineseEvidence = XCTAttachment(screenshot: app.screenshot())
        chineseEvidence.name = "Pinbook Traditional Chinese introduction"
        chineseEvidence.lifetime = .keepAlways
        add(chineseEvidence)
        app.buttons["繼續"].tap()
        XCTAssertTrue(app.staticTexts["選擇您的幣別"].waitForExistence(timeout: 5))
        languageControl.tap()
        let urdu = app.buttons["language-ur"]
        for _ in 0..<5 where !urdu.isHittable { app.swipeUp() }
        XCTAssertTrue(urdu.isHittable)
        urdu.tap()
        XCTAssertTrue(app.navigationBars["زبان"].waitForExistence(timeout: 5))
        app.buttons["language-done"].tap()
        // The language change must keep the user's current introduction page.
        XCTAssertTrue(app.staticTexts["اپنی کرنسیاں منتخب کریں"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(languageControl.frame.midX, app.buttons["onboarding-skip"].frame.midX)
        app.buttons["جاری رکھیں"].tap()
        XCTAssertTrue(app.staticTexts["دیکھیں کتنی رقم باقی ہے"].waitForExistence(timeout: 5))
        app.buttons["جاری رکھیں"].tap()
        XCTAssertTrue(app.staticTexts["بنیادی طور پر نجی"].waitForExistence(timeout: 5))
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook Urdu final introduction page RTL"
        evidence.lifetime = .keepAlways
        add(evidence)
        languageControl.tap()
        let system = app.buttons["language-system"]
        for _ in 0..<5 where !system.isHittable { app.swipeDown() }
        system.tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 5))
        app.buttons["language-done"].tap()
        XCTAssertTrue(app.staticTexts["Private by default"].waitForExistence(timeout: 5))
        XCTAssertLessThan(languageControl.frame.midX, app.buttons["onboarding-skip"].frame.midX)
    }

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
        dismissNativeFilesPicker(in: app, revealing: "Export backup")
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
        dismissNativeFilesPicker(in: app, revealing: "Import and preview")
        app.terminate()
    }

    @MainActor
    private func dismissNativeFilesPicker(in app: XCUIApplication, revealing buttonLabel: String) {
        // The native provider can be rendered by another process and absent from
        // our AX tree. Dismiss its visible sheet using the standard pull-down
        // gesture. Killing the host with this sheet still open left later tests
        // dimmed/noninteractive on iOS26.5; verify dismissal before terminating.
        let header = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        header.press(forDuration: 0.1, thenDragTo: bottom)
        XCTAssertTrue(app.buttons[buttonLabel].wait(for: \.isHittable, toEqual: true, timeout: 5))
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
    func testPrivateGoogleDriveSyncExplainsNarrowScopeBeforeConnecting() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PinbookFixture", "populated",
            "-PinbookTab", "options",
            "-PinbookSkin", "paperGlass",
            "-PinbookTheme", "light",
        ]
        app.launch()

        let backupLink = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "Backup & Recovery"
        )).firstMatch
        XCTAssertTrue(backupLink.waitForExistence(timeout: 5))
        backupLink.tap()
        XCTAssertTrue(app.navigationBars["Backup & Recovery"].waitForExistence(timeout: 5))

        let connect = app.buttons["Connect Google Drive"]
        scrollToHittable(connect, in: app)
        XCTAssertTrue(connect.isHittable)
        XCTAssertTrue(app.staticTexts["Not connected"].exists)
        connect.tap()

        let scopeExplanation = app.staticTexts[
            "Pinbook will request access only to its private app data folder. It cannot read your other Google Drive files."
        ]
        XCTAssertTrue(scopeExplanation.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Connect"].exists)

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Pinbook private Google Drive scope confirmation"
        evidence.lifetime = .keepAlways
        add(evidence)
        app.terminate()
    }

    @MainActor
    func testSimplifiedChinesePrivateDriveScopeIsLocalized() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PinbookFixture", "populated",
            "-PinbookTab", "options",
            "-PinbookLanguage", "zh-Hans",
        ]
        app.launch()

        let backupLink = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "备份与恢复"
        )).firstMatch
        XCTAssertTrue(backupLink.waitForExistence(timeout: 5))
        backupLink.tap()
        XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 5))

        let connect = app.buttons["连接 Google 云端硬盘"]
        scrollToHittable(connect, in: app)
        XCTAssertTrue(connect.isHittable)
        XCTAssertTrue(app.staticTexts["未连接"].exists)
        connect.tap()
        XCTAssertTrue(app.staticTexts[
            "Pinbook 只会请求访问其私密应用数据文件夹，无法读取您在 Google 云端硬盘中的其他文件。"
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["连接"].exists)
        app.terminate()
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
