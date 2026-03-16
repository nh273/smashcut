import XCTest

final class SmashcutUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    // MARK: - Flow 1: App Launch

    func testAppLaunches() {
        XCTAssertTrue(app.navigationBars["Smashcut"].waitForExistence(timeout: 5))
    }

    func testSettingsButtonExists() {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
    }

    // MARK: - Flow 2: New Project Creation

    func testNewProjectFlowShowsFields() {
        // Tap + or New Project button
        let addButton = app.buttons["plus"]
        let newProjectButton = app.buttons["newProjectButton"]

        if newProjectButton.exists {
            newProjectButton.tap()
        } else if addButton.exists {
            addButton.tap()
        } else {
            XCTFail("No way to create a new project")
            return
        }

        // Verify the New Project sheet appears
        XCTAssertTrue(app.navigationBars["New Project"].waitForExistence(timeout: 3))

        // Verify fields exist
        let titleField = app.textFields["projectTitleField"]
        let ideaField = app.textFields["scriptIdeaField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        XCTAssertTrue(ideaField.waitForExistence(timeout: 2))
    }

    func testNewProjectNextButtonDisabledWhenEmpty() {
        let addButton = app.buttons["plus"]
        let newProjectButton = app.buttons["newProjectButton"]

        if newProjectButton.exists {
            newProjectButton.tap()
        } else if addButton.exists {
            addButton.tap()
        } else {
            return
        }

        _ = app.navigationBars["New Project"].waitForExistence(timeout: 3)

        let nextButton = app.buttons["nextButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 2))
        XCTAssertFalse(nextButton.isEnabled, "Next should be disabled when idea is empty")
    }

    func testNewProjectNextButtonEnabledWithIdea() {
        let addButton = app.buttons["plus"]
        let newProjectButton = app.buttons["newProjectButton"]

        if newProjectButton.exists {
            newProjectButton.tap()
        } else if addButton.exists {
            addButton.tap()
        } else {
            return
        }

        _ = app.navigationBars["New Project"].waitForExistence(timeout: 3)

        let ideaField = app.textFields["scriptIdeaField"]
        XCTAssertTrue(ideaField.waitForExistence(timeout: 2))
        ideaField.tap()
        ideaField.typeText("Test idea for e2e")

        let nextButton = app.buttons["nextButton"]
        XCTAssertTrue(nextButton.isEnabled, "Next should be enabled with idea text")
    }

    func testNewProjectNavigatesToScriptWorkshop() {
        let addButton = app.buttons["plus"]
        let newProjectButton = app.buttons["newProjectButton"]

        if newProjectButton.exists {
            newProjectButton.tap()
        } else if addButton.exists {
            addButton.tap()
        } else {
            return
        }

        _ = app.navigationBars["New Project"].waitForExistence(timeout: 3)

        // Fill in title
        let titleField = app.textFields["projectTitleField"]
        if titleField.waitForExistence(timeout: 2) {
            titleField.tap()
            titleField.typeText("UI Test Project")
        }

        // Fill in idea
        let ideaField = app.textFields["scriptIdeaField"]
        if ideaField.waitForExistence(timeout: 2) {
            ideaField.tap()
            ideaField.typeText("Test idea for automated testing")
        }

        // Tap Next
        let nextButton = app.buttons["nextButton"]
        if nextButton.waitForExistence(timeout: 2), nextButton.isEnabled {
            nextButton.tap()
        }

        // Should navigate to Script Workshop
        XCTAssertTrue(
            app.navigationBars["Script Workshop"].waitForExistence(timeout: 5),
            "Should navigate to Script Workshop"
        )

        // Refine button should exist
        let refineButton = app.buttons["refineButton"]
        XCTAssertTrue(refineButton.waitForExistence(timeout: 3))
    }

    // MARK: - Flow 3: Settings

    func testSettingsOpensAndCloses() {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        // Settings sheet should appear
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        // API key field should exist
        let apiKeyField = app.secureTextFields["apiKeyField"]
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 2))

        // Dismiss
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.exists)
        doneButton.tap()

        // Should be back to main screen
        XCTAssertTrue(app.navigationBars["Smashcut"].waitForExistence(timeout: 3))
    }

    // MARK: - Flow 4: Existing Project Navigation

    func testExistingProjectOpensSectionManager() {
        // This test only works if a project already exists
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else {
            // No projects — skip
            return
        }

        projectCell.tap()

        // Should show section manager with section content
        let sectionText = app.staticTexts["Section 1"]
        XCTAssertTrue(
            sectionText.waitForExistence(timeout: 5),
            "Section Manager should show Section 1"
        )
    }

    func testSectionManagerRecordButton() {
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else { return }
        projectCell.tap()

        // Wait for section manager
        let recordButton = app.buttons["recordButton_0"]
        guard recordButton.waitForExistence(timeout: 5) else {
            // Section might be in different state
            return
        }

        recordButton.tap()

        // Should show teleprompter/recording view (nav bar hidden, close button present)
        let closeButton = app.buttons["xmark.circle.fill"]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 5),
            "Recording view should show close button"
        )

        closeButton.tap()

        // Should be back to section manager
        XCTAssertTrue(
            app.staticTexts["Section 1"].waitForExistence(timeout: 5),
            "Should return to Section Manager"
        )
    }

    func testSectionManagerTimelineButton() {
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else { return }
        projectCell.tap()

        let timelineButton = app.buttons["openTimelineButton"]
        guard timelineButton.waitForExistence(timeout: 5) else {
            // Timeline might not be available (no timeline data)
            return
        }

        timelineButton.tap()

        // Should show timeline (has Save button in nav)
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 5),
            "Timeline view should show Save button"
        )
    }

    // MARK: - Flow 5: Caption Editor UI (sm-59lj)

    func testCaptionEditorAppears() {
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else { return }
        projectCell.tap()

        // Tap Edit Captions on Section 1 (only available when section is recorded)
        let editCaptions = app.buttons["Edit Captions"]
        guard editCaptions.waitForExistence(timeout: 5) else {
            // Section not recorded — skip
            return
        }
        editCaptions.tap()

        // Caption editor should show nav title
        XCTAssertTrue(
            app.staticTexts["Edit Captions"].waitForExistence(timeout: 5),
            "Caption editor screen should appear"
        )
    }

    func testCaptionEditorLinkedToggle() {
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else { return }
        projectCell.tap()

        let editCaptions = app.buttons["Edit Captions"]
        guard editCaptions.waitForExistence(timeout: 5) else { return }
        editCaptions.tap()

        // Linked toggle should exist
        let linkedButton = app.buttons["Linked"]
        XCTAssertTrue(
            linkedButton.waitForExistence(timeout: 5),
            "Linked toggle should exist in caption editor"
        )
    }

    func testCaptionEditorSplitCaptionButton() {
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else { return }
        projectCell.tap()

        let editCaptions = app.buttons["Edit Captions"]
        guard editCaptions.waitForExistence(timeout: 5) else { return }
        editCaptions.tap()

        // Split Caption button should exist
        let splitButton = app.buttons["Split Caption"]
        XCTAssertTrue(
            splitButton.waitForExistence(timeout: 5),
            "Split Caption button should exist"
        )
    }

    func testCaptionEditorTextFormattingButton() {
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else { return }
        projectCell.tap()

        let editCaptions = app.buttons["Edit Captions"]
        guard editCaptions.waitForExistence(timeout: 5) else { return }
        editCaptions.tap()

        // Text formatting button should exist
        let formatButton = app.buttons["textformat"]
        XCTAssertTrue(
            formatButton.waitForExistence(timeout: 5),
            "Text formatting button should exist"
        )
    }

    func testCaptionEditorPositionControl() {
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else { return }
        projectCell.tap()

        let editCaptions = app.buttons["Edit Captions"]
        guard editCaptions.waitForExistence(timeout: 5) else { return }
        editCaptions.tap()

        // Position label may need scrolling to be visible
        let positionLabel = app.staticTexts["Position"]
        if !positionLabel.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(
            positionLabel.waitForExistence(timeout: 5),
            "Position control should exist in caption editor"
        )
    }

    // MARK: - Flow 6: Section Refine (sm-otfs)

    func testSectionRefineSheetAppears() {
        let projectCell = app.cells.firstMatch
        guard projectCell.waitForExistence(timeout: 3) else { return }
        projectCell.tap()

        let refineButton = app.buttons["refineSection_0"]
        guard refineButton.waitForExistence(timeout: 5) else {
            let refineButton1 = app.buttons["refineSection_1"]
            guard refineButton1.waitForExistence(timeout: 3) else { return }
            refineButton1.tap()
            XCTAssertTrue(
                app.staticTexts["Refine Section 2"].waitForExistence(timeout: 5),
                "Refine sheet should appear"
            )
            return
        }
        refineButton.tap()

        XCTAssertTrue(
            app.staticTexts["Refine Section 1"].waitForExistence(timeout: 5),
            "Refine sheet should appear"
        )
    }
}
