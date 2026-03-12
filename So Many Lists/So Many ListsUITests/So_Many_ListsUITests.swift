//
//  So_Many_ListsUITests.swift
//  So Many ListsUITests
//
//  Created by Kevin Flathers on 3/12/26.
//

import XCTest

final class So_Many_ListsUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testCanOpenCreateFlow() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["So Many Lists"].exists)
        app.buttons["Create"].tap()
        XCTAssertTrue(app.navigationBars["Create List"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
