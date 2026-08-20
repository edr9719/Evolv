import XCTest

final class EvolvPilotFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testUnenrolledHelpTestRequiresEnrollmentBeforeCapture() {
        launch(scenario: "unenrolled")
        openHelpTest()

        XCTAssertTrue(element("validation.pilot.enrollment-required").waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["validation.official.start"].exists)

        let join = element("validation.pilot.join-required")
        if !join.isHittable { app.swipeUp() }
        XCTAssertTrue(join.waitForExistence(timeout: 2))
        join.tap()
        XCTAssertTrue(element("pilot.enrollment.explanation").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["pilot.enrollment.continue"].exists)
    }

    func testEnrolledParticipantCanReachOfficialTestStart() {
        launch(scenario: "enrolled")
        openHelpTest()

        XCTAssertTrue(app.buttons["validation.official.start"].waitForExistence(timeout: 3))
        XCTAssertFalse(element("validation.pilot.enrollment-required").exists)
    }

    func testPilotDataSharingNavigationIsReachable() {
        launch(scenario: "unenrolled")
        openSettings()
        app.staticTexts["Privacy & Data"].tap()
        XCTAssertTrue(app.navigationBars["Privacy & Data"].waitForExistence(timeout: 3))

        app.staticTexts["Pilot data sharing"].tap()
        XCTAssertTrue(app.navigationBars["Pilot data sharing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Join with an invite"].exists)
    }

    func testCompletedLocalSessionOffersRetrospectiveEnrollment() {
        launch(scenario: "completed-local")
        openHelpTest()

        XCTAssertTrue(app.buttons["pilot.retrospective.join"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Joining does not upload this test. Sharing requires a separate confirmation after enrollment."].exists)

        app.buttons["pilot.retrospective.join"].tap()
        XCTAssertTrue(element("pilot.enrollment.explanation").waitForExistence(timeout: 3))
    }

    func testInvitationIsValidatedBeforeSharingChoiceWithoutBeingJoined() {
        launch(scenario: "unenrolled", inviteValidation: "valid")
        openHelpTest()
        element("validation.pilot.join-required").tap()
        advanceToInvitation()

        let code = element("pilot.enrollment.invite-code")
        code.tap()
        code.typeText("ABCDE12345ABCDE12345")
        element("pilot.enrollment.validate-invitation").tap()

        XCTAssertTrue(element("pilot.enrollment.sharing-choice").waitForExistence(timeout: 3))
        XCTAssertTrue(element("pilot.enrollment.join").exists)
    }

    func testUsedInvitationShowsActionableMessageAndDoesNotAdvance() {
        assertInvitationFailure(fixture: "used", message: "This invitation has already been used.")
    }

    func testInvalidInvitationShowsActionableMessageAndDoesNotAdvance() {
        assertInvitationFailure(fixture: "invalid", message: "This invitation isn't valid. Check the code and try again.")
    }

    func testClosedPilotShowsActionableMessageAndDoesNotAdvance() {
        assertInvitationFailure(fixture: "closed", message: "This pilot is currently closed.")
    }

    func testOfflineInvitationCheckShowsActionableMessageAndDoesNotAdvance() {
        assertInvitationFailure(fixture: "offline", message: "You're offline. Check your connection and try again.")
    }

    private func assertInvitationFailure(fixture: String, message: String) {
        launch(scenario: "unenrolled", inviteValidation: fixture)
        openHelpTest()
        element("validation.pilot.join-required").tap()
        advanceToInvitation()

        let code = element("pilot.enrollment.invite-code")
        code.tap()
        code.typeText("ABCDE12345ABCDE12345")
        element("pilot.enrollment.validate-invitation").tap()

        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 3))
        XCTAssertFalse(element("pilot.enrollment.sharing-choice").exists)
    }

    private func launch(scenario: String, inviteValidation: String? = nil) {
        app.launchEnvironment["EVOLV_UI_TEST_SCENARIO"] = scenario
        app.launchEnvironment["EVOLV_ALLOW_NETWORK"] = "0"
        if let inviteValidation {
            app.launchEnvironment["EVOLV_UI_TEST_INVITE_VALIDATION"] = inviteValidation
        }
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
    }

    private func advanceToInvitation() {
        element("pilot.enrollment.continue").tap()
        let consent = element("pilot.enrollment.adult-consent")
        XCTAssertTrue(consent.waitForExistence(timeout: 2))
        consent.tap()
        app.buttons["Continue to invitation"].tap()
        XCTAssertTrue(element("pilot.enrollment.invite-code").waitForExistence(timeout: 2))
    }

    private func openSettings() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    private func openHelpTest() {
        openSettings()
        app.staticTexts["Help test Evolv"].tap()
        XCTAssertTrue(app.navigationBars["Help test Evolv"].waitForExistence(timeout: 3))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
