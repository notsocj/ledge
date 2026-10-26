import Foundation
import Testing
@testable import Kestrel

@Test func trialCountsDownSevenDaysThenEnds() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400
    #expect(License.state(trialStart: start, now: start, licensed: false) == .trial(daysLeft: 7))
    #expect(License.state(trialStart: start, now: start + day * 0.5, licensed: false) == .trial(daysLeft: 7))
    #expect(License.state(trialStart: start, now: start + day * 6.5, licensed: false) == .trial(daysLeft: 1))
    #expect(License.state(trialStart: start, now: start + day * 7, licensed: false) == .expired)
    #expect(License.state(trialStart: start, now: start - day * 3, licensed: false) == .trial(daysLeft: 7)) // clock set back
    #expect(License.state(trialStart: start, now: start + day * 30, licensed: true) == .licensed)
}

@Test func readsLemonSqueezyResponsesAndChecksTheProduct() throws {
    let activated = """
    {"activated": true, "error": null,
     "license_key": {"id": 1, "status": "active", "key": "abc", "activation_limit": 2, "activation_usage": 1},
     "instance": {"id": "f90ec370-fd83-46a5-8bbd-44a241e78665", "name": "Mac"},
     "meta": {"store_id": 11, "order_id": 2, "product_id": 44, "product_name": "Kestrel", "customer_email": "a@b.c"}}
    """
    let response = try #require(License.decode(Data(activated.utf8)))
    #expect(response.activated == true)
    #expect(response.instance?.id == "f90ec370-fd83-46a5-8bbd-44a241e78665")
    #expect(License.isOurs(response.meta, store: 11, product: 44))
    #expect(!License.isOurs(response.meta, store: 11, product: 45))
    #expect(License.isOurs(response.meta, store: 0, product: 0)) // unconfigured: any store
    #expect(!License.isOurs(nil, store: 0, product: 0))

    let limit = #"{"activated": false, "error": "This license key has reached the activation limit.", "license_key": {"id": 1}, "meta": null}"#
    let refused = try #require(License.decode(Data(limit.utf8)))
    #expect(refused.activated == false)
    #expect(refused.error == "This license key has reached the activation limit.")

    let invalid = try #require(License.decode(Data(#"{"valid": false, "error": "license_key not found.", "license_key": null, "instance": null, "meta": null}"#.utf8)))
    #expect(invalid.valid == false)
}
