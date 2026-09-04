import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

struct TeamStrictJSONTests {
    @Test func acceptsBoundedProtocolValuesAndDecodedEscapes() throws {
        let value = try TeamStrictJSON.object(Data(#"{"label":"\u4e2d\u6587","list":[true,false,null,{"value":9007199254740991}],"zero":0}"#.utf8))
        #expect(value["label"] as? String == "中文")
        #expect(try TeamAuthWire.time(value, "zero") == 0)
        let list = try #require(value["list"] as? [Any])
        #expect(list.count == 4 && list[2] is NSNull)
        let nested = try #require(list[3] as? [String: Any])
        #expect(try TeamAuthWire.time(nested, "value") == TeamAuthWire.maximumSafeTime)
    }
    @Test func rejectsDecodedDuplicatesAtAnyDepth() {
        for raw in [#"{"token":null,"token":1}"#, #"{"token":1,"\u0074oken":2}"#,
            #"{"keys":{"x":1,"\u0078":2}}"#, #"{"list":[{"id":1,"id":2}]}"#] {
            #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamStrictJSON.object(Data(raw.utf8)) }
        }
    }
    @Test func rejectsMalformedAndNoncanonicalNumericRepresentations() {
        for raw in [#"{"v":1e3}"#, #"{"v":1.0}"#, #"{"v":9007199254740990.5}"#,
            #"{"v":9007199254740992}"#, #"{"v":01}"#, #"{"v":-0}"#, #"{"v":+1}"#,
            #"{"v":1,}"#, #"{"v":[1,]}"#, #"{"v":"\uD800"}"#, #"{"v":true} trailing"#, "[]"] {
            #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamStrictJSON.object(Data(raw.utf8)) }
        }
        let bool = try? TeamStrictJSON.object(Data(#"{"v":true}"#.utf8))
        #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamAuthWire.time(bool!, "v") }
    }
    @Test func rejectsEncodingDepthNodeAndByteOverflow() {
        for data in [Data([0xef, 0xbb, 0xbf]) + Data("{}".utf8), Data([123, 34, 118, 34, 58, 34, 0xff, 34, 125]),
            Data(#"{"a":{"b":{"c":{"d":{}}}}}"#.utf8),
            Data(("{\"a\":[" + Array(repeating: "0", count: 2050).joined(separator: ",") + "]}").utf8)] {
            #expect(throws: TeamAuthHTTPError.invalidResponse) { try TeamStrictJSON.object(data) }
        }
        #expect(throws: TeamAuthHTTPError.responseTooLarge) { try TeamStrictJSON.object(Data(repeating: 32, count: 32_769)) }
    }
}
