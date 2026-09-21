import Foundation
import SlimBladeCore

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect<T: Equatable>(
    _ actual: @autoclosure () -> T,
    _ expected: T,
    _ label: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let value = actual()
    guard value == expected else {
        throw TestFailure(description: "\(file):\(line): \(label): expected \(expected), got \(value)")
    }
}

private let tests: [(String, () throws -> Void)] = [
    ("parser rejects short reports", {
        try expect(SlimBladeReportParser.pressedButtons(in: [0, 0, 0, 0]), nil, "short report")
    }),
    ("parser reads only byte-four upper bits", {
        try expect(SlimBladeReportParser.pressedButtons(in: [9, 9, 9, 9, 0x03, 0xff]), [.upperLeft, .upperRight], "both")
        try expect(SlimBladeReportParser.pressedButtons(in: [0, 0, 0, 0, 0xfc]), [], "unrelated bits")
    }),
    ("edges are emitted once", {
        var state = ButtonBridgeState<String>()
        state.attach("one", hasNativeButtons: false)
        try expect(state.process([0, 0, 0, 0, 1], from: "one"), [.down(.upperLeft)], "first down")
        try expect(state.process([0, 0, 0, 0, 1], from: "one"), [], "held")
        try expect(state.process([0, 0, 0, 0, 0], from: "one"), [.up(.upperLeft)], "up")
    }),
    ("native mode suppresses raw bridge", {
        var state = ButtonBridgeState<Int>()
        state.attach(1, hasNativeButtons: true)
        try expect(state.process([0, 0, 0, 0, 3], from: 1), [], "native event")
        try expect(state.nativeDeviceCount, 1, "native count")
    }),
    ("multiple devices are coalesced", {
        var state = ButtonBridgeState<Int>()
        state.attach(1, hasNativeButtons: false)
        state.attach(2, hasNativeButtons: false)
        try expect(state.process([0, 0, 0, 0, 1], from: 1), [.down(.upperLeft)], "device one down")
        try expect(state.process([0, 0, 0, 0, 1], from: 2), [], "device two held")
        try expect(state.detach(1), [], "one detach")
        try expect(state.detach(2), [.up(.upperLeft)], "last detach")
    }),
    ("disable and reset release held buttons", {
        var state = ButtonBridgeState<String>()
        state.attach("one", hasNativeButtons: false)
        _ = state.process([0, 0, 0, 0, 3], from: "one")
        try expect(state.setEnabled(false), [.up(.upperLeft), .up(.upperRight)], "disable")
        try expect(state.process([0, 0, 0, 0, 3], from: "one"), [], "disabled input")
        try expect(state.setEnabled(true), [], "enable")
        try expect(state.process([0, 0, 0, 0, 2], from: "one"), [.down(.upperRight)], "down after enable")
        try expect(state.resetPressedState(), [.up(.upperRight)], "reset")
    }),
]

var failureCount = 0
for (name, test) in tests {
    do {
        try test()
        print("PASS: \(name)")
    } catch {
        failureCount += 1
        print("FAIL: \(name)\n  \(error)")
    }
}
print("\(tests.count - failureCount)/\(tests.count) tests passed")
if failureCount > 0 { exit(1) }
