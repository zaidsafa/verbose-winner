import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import PinbookCore
#else
@testable import Pinbook
#endif

private let publicChallenge = String(repeating: "A", count: 43)
private let publicNonce = String(repeating: "B", count: 42) + "A"
private let publicToken = Data("synthetic.header.signature".utf8)

private func begin(_ flow: TeamNativeSignInFlow, provider: TeamNativeSignInProvider = .apple,
                   now: Int64 = 1_000, expiresAt: Int64 = 121_000) async throws -> TeamNativeSignInContext {
    try await flow.begin(provider: provider, providerID: "public-ios-profile",
        challengeID: publicChallenge, nonce: publicNonce, expiresAt: expiresAt, now: now)
}

@Test func nativeSignInPreservesRawNonceAndConsumesExactlyOnce() async throws {
    let flow = TeamNativeSignInFlow()
    let context = try await begin(flow)
    #expect(context.nonce == publicNonce)
    #expect(context.state.utf8.count == 43)
    #expect(context.state != publicNonce)
    #expect(!String(reflecting: context).contains(publicNonce))
    #expect(Mirror(reflecting: context).children.isEmpty)
    let result = try await flow.acceptApple(attemptID: context.id, returnedState: context.state,
        identityToken: publicToken, now: 2_000)
    #expect(result.idToken == String(decoding: publicToken, as: UTF8.self))
    #expect(result.challengeID == publicChallenge)
    #expect(!String(reflecting: result).contains("synthetic"))
    #expect(Mirror(reflecting: result).children.isEmpty)
    await #expect(throws: TeamNativeSignInError.expired) {
        try await flow.acceptApple(attemptID: context.id, returnedState: context.state,
            identityToken: publicToken, now: 2_000)
    }
}

@Test func nativeSignInRefusesOverlapAndOldCancellationCannotEraseNewFlow() async throws {
    let flow = TeamNativeSignInFlow()
    let old = try await begin(flow)
    await #expect(throws: TeamNativeSignInError.busy) { try await begin(flow) }
    await flow.cancel(attemptID: old.id)
    let current = try await begin(flow)
    #expect(current.state != old.state)
    await flow.cancel(attemptID: old.id)
    await #expect(throws: TeamNativeSignInError.expired) {
        try await flow.acceptApple(attemptID: old.id, returnedState: old.state,
            identityToken: publicToken, now: 2_000)
    }
    _ = try await flow.acceptApple(attemptID: current.id, returnedState: current.state,
        identityToken: publicToken, now: 2_000)
}

@Test func nativeSignInInvalidStateAndWrongProviderConsumeTheirAttempt() async throws {
    let flow = TeamNativeSignInFlow()
    for state in [nil, "wrong", publicNonce] {
        let context = try await begin(flow)
        await #expect(throws: TeamNativeSignInError.invalidCallback) {
            try await flow.acceptApple(attemptID: context.id, returnedState: state,
                identityToken: publicToken, now: 1_000)
        }
        await #expect(throws: TeamNativeSignInError.expired) {
            try await flow.acceptApple(attemptID: context.id, returnedState: context.state,
                identityToken: publicToken, now: 1_000)
        }
    }
    let apple = try await begin(flow)
    await #expect(throws: TeamNativeSignInError.invalidCallback) {
        try await flow.acceptGoogleSDK(attemptID: apple.id, identityToken: publicToken, now: 1_000)
    }
    let google = try await begin(flow, provider: .google)
    _ = try await flow.acceptGoogleSDK(attemptID: google.id, identityToken: publicToken, now: 1_000)
}

@Test func nativeSignInRejectsExpiredAndRollbackCallbacks() async throws {
    let flow = TeamNativeSignInFlow()
    let expired = try await begin(flow)
    await #expect(throws: TeamNativeSignInError.expired) {
        try await flow.acceptApple(attemptID: expired.id, returnedState: expired.state,
            identityToken: publicToken, now: 121_000)
    }
    let current = try await begin(flow, now: 121_000, expiresAt: 241_000)
    await #expect(throws: TeamNativeSignInError.expired) {
        try await flow.acceptApple(attemptID: current.id, returnedState: current.state,
            identityToken: publicToken, now: 120_999)
    }
    await #expect(throws: TeamNativeSignInError.expired) {
        try await flow.acceptApple(attemptID: current.id, returnedState: current.state,
            identityToken: publicToken, now: 121_000)
    }
}

@Test func nativeSignInRejectsMalformedChallengesAndTokens() async throws {
    let flow = TeamNativeSignInFlow()
    for nonce in ["", publicNonce + "=", String(repeating: "B", count: 43), " " + publicNonce, String(repeating: "é", count: 43)] {
        await #expect(throws: TeamNativeSignInError.invalidChallenge) {
            try await flow.begin(provider: .apple, providerID: "public-ios-profile",
                challengeID: publicChallenge, nonce: nonce, expiresAt: 121_000, now: 1_000)
        }
    }
    for expiry: Int64 in [0, 1_000, 121_001, Int64.max] {
        await #expect(throws: TeamNativeSignInError.invalidChallenge) { try await begin(flow, expiresAt: expiry) }
    }
    for text in ["", ".a.b", "a..b", "a.b.", "a.b", "a.b.c.d", "a.é.c", "a.b. c", String(repeating: "a", count: 16_385)] {
        let context = try await begin(flow)
        await #expect(throws: TeamNativeSignInError.invalidCallback) {
            try await flow.acceptApple(attemptID: context.id, returnedState: context.state,
                identityToken: Data(text.utf8), now: 1_000)
        }
    }
}

@Test func nativeSignInCancellationCannotLeaveAReusableAttempt() async throws {
    let flow = TeamNativeSignInFlow()
    let cancelledBegin = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        await #expect(throws: CancellationError.self) { try await begin(flow) }
    }
    await cancelledBegin.value
    let context = try await begin(flow)
    let cancelledCallback = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        await #expect(throws: CancellationError.self) {
            try await flow.acceptApple(attemptID: context.id, returnedState: context.state,
                identityToken: publicToken, now: 1_000)
        }
    }
    await cancelledCallback.value
    await #expect(throws: TeamNativeSignInError.expired) {
        try await flow.acceptApple(attemptID: context.id, returnedState: context.state,
            identityToken: publicToken, now: 1_000)
    }
    _ = try await begin(flow)
}

#if canImport(AuthenticationServices)
@MainActor @Test func nativeAppleRequestUsesExactStateNonceAndNoProfileScopes() async throws {
    let flow = TeamNativeSignInFlow()
    let context = try await begin(flow)
    let request = try context.makeAppleRequest()
    #expect(request.nonce == publicNonce)
    #expect(request.state == context.state)
    #expect(request.requestedScopes?.isEmpty == true)
    await flow.cancel(attemptID: context.id)
    let google = try await begin(flow, provider: .google)
    #expect(throws: TeamNativeSignInError.invalidCallback) { try google.makeAppleRequest() }
}
#endif
