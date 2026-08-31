@testable import CursorBarAdapters
import XCTest

final class CursorProcessAdapterTests: XCTestCase {
    func testEscalateRemainingPIDsSendsSIGKILLAndSkipsPidOne() {
        var sent: [(pid_t, Int32)] = []
        let count = CursorProcessAdapter.escalateRemainingPIDs([1, 20774, 9]) { pid, signal in
            sent.append((pid, signal))
            return 0
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(sent.map(\.0), [20774, 9])
        XCTAssertTrue(sent.allSatisfy { $0.1 == SIGKILL })
    }

    func testEscalateRemainingPIDsCountsOnlySuccessfulKills() {
        let count = CursorProcessAdapter.escalateRemainingPIDs([4, 5]) { pid, _ in
            pid == 4 ? 0 : -1
        }
        XCTAssertEqual(count, 1)
    }
}
