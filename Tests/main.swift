import AppKit
import Foundation
import ServiceManagement

let mock = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/fake-codex.sh").path
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { fputs("FAIL: \(name)\n", stderr); exit(1) }
    print("PASS: \(name)")
}
func scenario(_ name: String) { setenv("CODEX_TEST_SCENARIO", name, 1) }
func failure(_ name: String, contains expected: String) {
    scenario(name)
    do { _ = try readUsage(executable: mock, timeout: 0.3); check(false, name + " must fail") }
    catch { check(error.localizedDescription.contains(expected), name + " reports " + expected) }
}

do { _ = try readUsage(executable: "/nonexistent/CodexUsageBar-test-codex", timeout: 1); check(false, "missing Codex must fail") }
catch { check(error.localizedDescription.contains("无法启动"), "missing executable is reported") }
scenario("success")
let success = try readUsage(executable: mock, timeout: 2)
check(success.count == 2 && success[0].remaining == 70 && success[1].remaining == 25, "multiple quota windows")
failure("loggedout", contains: "登录")
failure("reversed", contains: "登录")
failure("apikey", contains: "ChatGPT")
failure("network", contains: "网络")
failure("empty", contains: "没有可显示")
failure("timeout", contains: "超时")
scenario("success")
let recovered = try readUsage(executable: mock, timeout: 2)
check(recovered.count == 2, "recovery after failure")
check(!needsAttention(message: nil, lastUpdate: nil, now: Date(timeIntervalSince1970: 1100)), "initial loading is not a failure")
check(!needsAttention(message: nil, lastUpdate: Date(timeIntervalSince1970: 1000), now: Date(timeIntervalSince1970: 1100)), "fresh data has normal icon")
check(needsAttention(message: "error", lastUpdate: Date(timeIntervalSince1970: 1000), now: Date(timeIntervalSince1970: 1001)), "failure has warning icon")
check(needsAttention(message: nil, lastUpdate: Date(timeIntervalSince1970: 1000), now: Date(timeIntervalSince1970: 1151)), "stale data has warning icon")
var state: SMAppService.Status = .notRegistered
var registrations = 0
let login = LoginItemController(status: { state }, register: { registrations += 1; state = .enabled }, unregister: { state = .notRegistered })
check(registrations == 0 && !login.isOn, "login startup remains disabled initially")
login.setEnabled(true)
check(registrations == 1 && login.isOn, "login startup enables only on request")
login.setEnabled(false)
check(!login.isOn, "login startup can be disabled")
state = .requiresApproval
login.refreshStatus()
check(login.requiresApproval && login.isOn, "pending system approval is visible")
let failingLogin = LoginItemController(status: { .notRegistered }, register: { throw Failure("test failure") }, unregister: {})
failingLogin.setEnabled(true)
check(!failingLogin.isOn && failingLogin.errorMessage != nil, "login registration failure remains off and visible")
var response: Result<[Window], Error> = .success(success)
let store = UsageStore(fetch: { try response.get() })
func refreshAndWait() {
    store.refresh()
    let deadline = Date().addingTimeInterval(3)
    while store.loading && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    check(!store.loading, "refresh completes")
}
refreshAndWait()
check(store.windows.count == 2 && store.message == nil && store.lastUpdate != nil, "successful refresh updates visible data")
let lastSuccess = store.lastUpdate
response = .failure(Failure("网络异常"))
refreshAndWait()
check(store.windows.count == 2 && store.message == "网络异常" && store.lastUpdate == lastSuccess, "failed refresh keeps last successful data and marks error")
response = .success([success[0]])
refreshAndWait()
check(store.windows.count == 1 && store.message == nil, "successful retry clears error and replaces old data")

print("All behavior tests passed")
