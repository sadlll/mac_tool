import MacToolCore
import XCTest

final class RetryBackoffPolicyTests: XCTestCase {
    func testExponentialBackoffCapsAtMaxDelay() {
        let policy = RetryBackoffPolicy(baseDelay: 30, maxDelay: 1800)

        XCTAssertEqual(policy.delay(forFailureCount: 0), 0)
        XCTAssertEqual(policy.delay(forFailureCount: 1), 30)
        XCTAssertEqual(policy.delay(forFailureCount: 2), 60)
        XCTAssertEqual(policy.delay(forFailureCount: 3), 120)
        XCTAssertEqual(policy.delay(forFailureCount: 6), 960)
        XCTAssertEqual(policy.delay(forFailureCount: 7), 1800)
        XCTAssertEqual(policy.delay(forFailureCount: 20), 1800)
    }
}
