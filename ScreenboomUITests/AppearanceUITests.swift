import XCTest

final class AppearanceUITests: ScreenboomUITestCase {

    // MARK: - Helpers

    /// Wait for the appearance tab content to render (via section card ID).
    @MainActor
    private func waitForAppearanceTab(_ app: XCUIApplication) {
        XCTAssertTrue(
            element("appearance_background_section", in: app).waitForExistence(timeout: 5),
            "Appearance background section should be present")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Section Structure
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testAppearanceTabShowsAllSections() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        // All 4 section cards (IDs are on SBGlassCard containers)
        XCTAssertTrue(element("appearance_background_section", in: app).exists,
            "Background section should be present")
        XCTAssertTrue(element("appearance_frame_section", in: app).exists,
            "Frame section should be present")
        XCTAssertTrue(element("appearance_layout_section", in: app).exists,
            "Layout section should be present")

        // Shadow might need scroll
        let shadowSection = element("appearance_shadow_section", in: app)
        if !shadowSection.exists {
            // Scroll the controls panel to reveal shadow section
            element("appearance_background_section", in: app).swipeUp()
        }
        XCTAssertTrue(shadowSection.waitForExistence(timeout: 3),
            "Shadow section should be present (may need scroll)")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Background Types
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testBackgroundTypeOptions() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        // All 5 background type buttons (SBOptionSwatch renders as Button)
        XCTAssertTrue(app.buttons["Solid"].exists, "Solid option should exist")
        XCTAssertTrue(app.buttons["Gradient"].exists, "Gradient option should exist")
        XCTAssertTrue(app.buttons["Mesh"].exists, "Mesh option should exist")
        XCTAssertTrue(app.buttons["Wallpaper"].exists, "Wallpaper option should exist")
        XCTAssertTrue(app.buttons["Image"].exists, "Image option should exist")
    }

    @MainActor
    func testSolidBackgroundShowsColorPicker() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        app.buttons["Solid"].tap()

        // Solid shows "Color" label + ColorPicker
        XCTAssertTrue(app.staticTexts["Color"].waitForExistence(timeout: 2),
            "Color label should appear for Solid background")
    }

    @MainActor
    func testGradientBackgroundShowsPresetsAndPickers() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        app.buttons["Gradient"].tap()

        // Start/End color labels
        XCTAssertTrue(app.staticTexts["Start"].waitForExistence(timeout: 2),
            "Start color label should appear")
        XCTAssertTrue(app.staticTexts["End"].exists,
            "End color label should appear")

        // Preset chips
        XCTAssertTrue(app.buttons["Dark"].exists, "Dark preset should exist")
        XCTAssertTrue(app.buttons["Light"].exists, "Light preset should exist")
        XCTAssertTrue(app.buttons["Ocean"].exists, "Ocean preset should exist")
    }

    @MainActor
    func testMeshBackgroundShowsColorGrid() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        app.buttons["Mesh"].tap()

        // Mesh shows 4 corner labels: TL, TR, BL, BR
        XCTAssertTrue(app.staticTexts["TL"].waitForExistence(timeout: 2), "TL corner label")
        XCTAssertTrue(app.staticTexts["TR"].exists, "TR corner label")
        XCTAssertTrue(app.staticTexts["BL"].exists, "BL corner label")
        XCTAssertTrue(app.staticTexts["BR"].exists, "BR corner label")
    }

    @MainActor
    func testWallpaperBackgroundShowsPresets() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        app.buttons["Wallpaper"].tap()

        // Wallpaper preset buttons (10 presets defined in BackgroundModels.swift)
        XCTAssertTrue(app.buttons["Sunset"].waitForExistence(timeout: 3), "Sunset preset")
        XCTAssertTrue(app.buttons["Aurora"].exists, "Aurora preset")
        XCTAssertTrue(app.buttons["Midnight"].exists, "Midnight preset")
        XCTAssertTrue(app.buttons["Lavender"].exists, "Lavender preset")
        XCTAssertTrue(app.buttons["Forest"].exists, "Forest preset")
        XCTAssertTrue(app.buttons["Ocean Deep"].exists, "Ocean Deep preset")
        XCTAssertTrue(app.buttons["Rose Gold"].exists, "Rose Gold preset")
        XCTAssertTrue(app.buttons["Slate"].exists, "Slate preset")
        XCTAssertTrue(app.buttons["Neon City"].exists, "Neon City preset")
        XCTAssertTrue(app.buttons["Ember"].exists, "Ember preset")
    }

    @MainActor
    func testImageBackgroundSwatchExists() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        // Verify the Image swatch exists.
        // NOTE: Tapping the Image swatch when background is NOT already .image
        // triggers importBackgroundImage() → NSOpenPanel immediately, which blocks XCUI.
        // The "Import Image" button only appears when background IS already .image type.
        // A dedicated harness mode with pre-set .image background would be needed to test
        // the import button in isolation.
        XCTAssertTrue(app.buttons["Image"].exists,
            "Image background type swatch should exist")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Frame Styles
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testFrameStyleOptions() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        // 5 frame style buttons
        XCTAssertTrue(app.buttons["None"].exists, "None frame option")
        XCTAssertTrue(app.buttons["Border"].exists, "Border frame option")
        XCTAssertTrue(app.buttons["Glow"].exists, "Glow frame option")
        XCTAssertTrue(app.buttons["Browser"].exists, "Browser frame option")
        XCTAssertTrue(app.buttons["Window"].exists, "Window frame option")
    }

    @MainActor
    func testBorderFrameShowsWidthAndColor() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        app.buttons["Border"].tap()

        XCTAssertTrue(app.staticTexts["Width"].waitForExistence(timeout: 2),
            "Width slider label should appear for Border frame")
        XCTAssertTrue(app.staticTexts["Color"].exists,
            "Color label should appear for Border frame")
    }

    @MainActor
    func testGlowFrameShowsRadiusAndColor() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        app.buttons["Glow"].tap()

        XCTAssertTrue(app.staticTexts["Radius"].waitForExistence(timeout: 2),
            "Radius slider should appear for Glow frame")
        XCTAssertTrue(app.staticTexts["Color"].exists,
            "Color label should appear for Glow frame")
    }

    @MainActor
    func testBrowserFrameShowsDescription() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        app.buttons["Browser"].tap()

        XCTAssertTrue(
            app.staticTexts["Browser chrome with traffic lights"].waitForExistence(timeout: 2),
            "Browser chrome description should appear")
    }

    @MainActor
    func testWindowFrameShowsDescription() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        app.buttons["Window"].tap()

        XCTAssertTrue(
            app.staticTexts["macOS window bar with traffic lights"].waitForExistence(timeout: 2),
            "macOS window description should appear")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Layout Section
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testLayoutSectionShowsSliders() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        XCTAssertTrue(app.staticTexts["Padding"].exists, "Padding slider label")
        XCTAssertTrue(app.staticTexts["Corner Radius"].exists, "Corner Radius slider label")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Shadow Section
    // ─────────────────────────────────────────────────────────────────

    @MainActor
    func testShadowSectionShowsSliders() throws {
        let app = launchApp(mode: "editor")
        waitForEditor(app)
        waitForAppearanceTab(app)

        // Shadow section may need scroll
        let shadowSection = element("appearance_shadow_section", in: app)
        if !shadowSection.exists {
            element("appearance_background_section", in: app).swipeUp()
        }
        XCTAssertTrue(shadowSection.waitForExistence(timeout: 3), "Shadow section should exist")

        // Verify labels within shadow section
        // Note: "Radius" also appears in Glow frame. To disambiguate, we check
        // for "Opacity" which is unique to the shadow section.
        XCTAssertTrue(app.staticTexts["Opacity"].exists, "Shadow opacity slider label")
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Multi-Segment Backgrounds (Tier 3)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testPerSegmentBackgroundPicker — when multi-segment backgrounds ship
    // Each segment would have its own background type/color

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Future: Aspect Ratio Presets (Tier 3)
    // ─────────────────────────────────────────────────────────────────

    // TODO: testAspectRatioPresets — 16:9, 9:16, 4:3, 1:1, custom
    // Would appear in Layout section or as a new section
}
