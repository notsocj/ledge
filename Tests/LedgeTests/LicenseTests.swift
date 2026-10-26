import Foundation
import Testing
@testable import Ledge

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

@Test func readsPolarRepliesAndChecksTheProduct() throws {
    let activated = """
    {"id": "f90ec370-fd83-46a5-8bbd-44a241e78665", "license_key_id": "k1", "label": "Mac", "meta": {},
     "license_key": {"id": "k1", "organization_id": "o1", "benefit_id": "b-ledge", "key": "LEDGE-1", "status": "granted",
                     "limit_activations": 2, "usage": 0, "validations": 0, "customer": {"email": "a@b.c"}}}
    """
    let reply = try #require(License.decode(Data(activated.utf8)))
    #expect(reply.id == "f90ec370-fd83-46a5-8bbd-44a241e78665")
    #expect(reply.licenseKey?.benefitId == "b-ledge")
    #expect(License.isOurs(benefit: reply.licenseKey?.benefitId, expected: "b-ledge"))
    #expect(!License.isOurs(benefit: reply.licenseKey?.benefitId, expected: "b-other"))
    #expect(License.isOurs(benefit: nil, expected: nil)) // one product: any key in the organization

    let limit = try #require(License.decode(Data(#"{"error": "NotPermitted", "detail": "License key activation limit reached"}"#.utf8)))
    #expect(License.problem(status: 403, reply: limit).hasPrefix("This key is already on two Macs"))
    let revoked = try #require(License.decode(Data(#"{"error": "NotPermitted", "detail": "License key is revoked"}"#.utf8)))
    #expect(License.problem(status: 403, reply: revoked) == "License key is revoked")
    #expect(License.problem(status: 404, reply: nil).hasPrefix("That key wasn't found"))

    // Field errors send `detail` as a list; the rest of the reply still reads.
    let invalid = try #require(License.decode(Data(#"{"detail": [{"loc": ["body", "key"], "msg": "Field required", "type": "missing"}]}"#.utf8)))
    #expect(invalid.detail == nil)
    #expect(License.problem(status: 422, reply: invalid).hasPrefix("That key didn't work"))
}
