import Foundation
import MacToolCore
import XCTest

final class CursorUsageParserTests: XCTestCase {
    func testRejectsPlanWithoutUsableQuota() {
        let responses = [
            #"{"planUsage":{}}"#,
            #"{"planUsage":{"limit":1000}}"#,
            #"{"planUsage":{"includedSpend":250,"limit":0}}"#,
            #"{"planUsage":{"includedSpend":-100,"limit":1000}}"#,
        ]

        for response in responses {
            XCTAssertThrowsError(try CursorUsageParser().parse(data: Data(response.utf8)), response) { error in
                guard case .unsupportedFormat = error as? ProviderError else {
                    return XCTFail("期望返回 ProviderError.unsupportedFormat")
                }
            }
        }
    }

    func testApiOnlyUsagePopulatesSecondaryWindow() throws {
        let response = #"{"planUsage":{"apiPercentUsed":0}}"#
        let snapshot = try CursorUsageParser().parse(data: Data(response.utf8))

        XCTAssertNil(snapshot.primaryWindow)
        XCTAssertEqual(snapshot.secondaryWindow?.id, "monthly_api")
        XCTAssertEqual(snapshot.secondaryWindow?.usedPercentage, 0)
    }

    func testPrimaryUsagePrefersTotalOverSpendAndAuto() throws {
        let response = #"{"planUsage":{"totalPercentUsed":0,"includedSpend":250,"limit":1000,"autoPercentUsed":10}}"#
        let snapshot = try CursorUsageParser().parse(data: Data(response.utf8))

        XCTAssertEqual(snapshot.primaryWindow?.usedPercentage, 0)
    }

    func testPrimaryUsagePrefersSpendOverAuto() throws {
        let response = #"{"planUsage":{"includedSpend":250,"limit":1000,"autoPercentUsed":10}}"#
        let snapshot = try CursorUsageParser().parse(data: Data(response.utf8))

        XCTAssertEqual(snapshot.primaryWindow?.usedPercentage, 25)
    }

    func testPrimaryUsageFallsBackToAutoWhenSpendIsInvalid() throws {
        let response = #"{"planUsage":{"includedSpend":-100,"limit":1000,"autoPercentUsed":10}}"#
        let snapshot = try CursorUsageParser().parse(data: Data(response.utf8))

        XCTAssertEqual(snapshot.primaryWindow?.usedPercentage, 10)
        XCTAssertNil(snapshot.billingSummary)
    }
}
