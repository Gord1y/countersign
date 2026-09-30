import Dispatch
import Foundation
import notify
import os

public enum QueuePlace: Sendable, Equatable {
  case head
  case nextInLine
  case behind
  case absent

  public init(of ticket: Ticket, among live: [Ticket]) {
    switch live.firstIndex(where: { $0.fileName == ticket.fileName }) {
    case 0: self = .head
    case 1: self = .nextInLine
    case .some: self = .behind
    case nil: self = .absent
    }
  }

  static func successor(of ticket: Ticket, among live: [Ticket]) -> Ticket? {
    guard let index = live.firstIndex(where: { $0.fileName == ticket.fileName }) else {
      return nil
    }
    return live.dropFirst(index + 1).first
  }

  static func predecessor(of ticket: Ticket, among live: [Ticket]) -> Ticket? {
    guard let index = live.firstIndex(where: { $0.fileName == ticket.fileName }), index > 0 else {
      return nil
    }
    return live[index - 1]
  }
}

public enum QueueTurn: Sendable {
  case display(DisplayLease)
  case nextInLine
  case abandoned
}

extension TicketQueue {
  public func place(of ticket: Ticket) -> QueuePlace {
    QueuePlace(of: ticket, among: liveTickets())
  }

  public func nextInLine(after ticket: Ticket) -> Ticket? {
    QueuePlace.successor(of: ticket, among: liveTickets())
  }

  public func ticketAhead(of ticket: Ticket) -> Ticket? {
    QueuePlace.predecessor(of: ticket, among: liveTickets())
  }

  public func waitForTurn(
    _ ticket: Ticket,
    pollInterval: TimeInterval,
    shouldAbandon: () -> Bool
  ) -> QueueTurn {
    while !shouldAbandon() {
      if let lease = acquireDisplayIfHead(ticket) {
        return .display(lease)
      }
      if place(of: ticket) == .nextInLine {
        return .nextInLine
      }
      Thread.sleep(forTimeInterval: pollInterval)
    }
    return .abandoned
  }
}

public struct QueueHandoff: Sendable, Equatable {
  public static let freshness: TimeInterval = 1
  public static let readyTimeout: TimeInterval = 0.15
  public static let preparingReadyTimeout: TimeInterval = 0.6

  public let receivedAt: TimeInterval
  public let displayID: UInt32?

  public init(receivedAt: TimeInterval, state: UInt64) {
    self.receivedAt = receivedAt
    self.displayID = Self.displayID(state: state)
  }

  public static func state(displayID: UInt32?) -> UInt64 {
    UInt64(displayID ?? 0)
  }

  public static func displayID(state: UInt64) -> UInt32? {
    state == 0 || state > UInt64(UInt32.max) ? nil : UInt32(state)
  }

  public static func readyTimeout(successorPreparing: Bool) -> TimeInterval {
    successorPreparing ? preparingReadyTimeout : readyTimeout
  }

  public func isFresh(at now: TimeInterval) -> Bool {
    now >= receivedAt && now - receivedAt <= Self.freshness
  }
}

public enum PreparedPanelReuse {
  public enum RebuildReason: String, Sendable, Equatable {
    case notPrepared = "not prepared"
    case screensChanged = "screens changed"
    case displayChanged = "display changed"
    case fileChanged = "file changed"
  }

  public enum Decision: Sendable, Equatable {
    case reuse
    case rebuild(RebuildReason)
  }

  public static func decide(
    preparedDisplayID: UInt32?,
    targetDisplayID: UInt32?,
    screensChanged: Bool,
    fileContextChanged: () -> Bool
  ) -> Decision {
    guard let preparedDisplayID else {
      return .rebuild(.notPrepared)
    }
    guard !screensChanged else {
      return .rebuild(.screensChanged)
    }
    guard targetDisplayID == preparedDisplayID else {
      return .rebuild(.displayChanged)
    }
    guard !fileContextChanged() else {
      return .rebuild(.fileChanged)
    }
    return .reuse
  }
}

public struct QueueHandoffReply: Sendable, Equatable {
  public let elapsed: Duration?
  public let waitedForPreparation: Bool
}

public struct QueueHandoffChannel: Sendable, Equatable {
  public let requestName: String
  public let readyName: String
  public let preparingName: String
  public let displayName: String

  public init(ticket: Ticket) {
    let stem = ticket.id
    requestName = "Countersign.handoff.\(stem)"
    readyName = "Countersign.ready.\(stem)"
    preparingName = "Countersign.preparing.\(stem)"
    displayName = "Countersign.display.\(stem)"
  }

  public func publishPreparation() -> QueueHandoffPreparation? {
    NotifyRegistration(name: preparingName).map(QueueHandoffPreparation.init(registration:))
  }

  public func isPreparing() -> Bool {
    guard let registration = NotifyRegistration(name: preparingName) else { return false }
    defer { registration.cancel() }
    return (registration.state() ?? 0) != 0
  }

  public func publishShownDisplay() -> QueueShownDisplay? {
    NotifyRegistration(name: displayName).map(QueueShownDisplay.init(registration:))
  }

  public func shownDisplayID() -> UInt32? {
    guard let registration = NotifyRegistration(name: displayName) else { return nil }
    defer { registration.cancel() }
    return registration.state().flatMap(QueueHandoff.displayID(state:))
  }

  public func listen(
    on queue: DispatchQueue, onRequest: @escaping @Sendable (UInt64) -> Void
  ) -> QueueHandoffListener? {
    var token: Int32 = 0
    let status = notify_register_dispatch(requestName, &token, queue) { token in
      var state: UInt64 = 0
      _ = notify_get_state(token, &state)
      onRequest(state)
    }
    guard status == NOTIFY_STATUS_OK else { return nil }
    return QueueHandoffListener(token: token)
  }

  public func signalReady() {
    _ = notify_post(readyName)
  }

  public func request(state: UInt64, timeout: TimeInterval) -> Duration? {
    request(state: state, timeout: { _ in timeout }, isPreparing: { false }).elapsed
  }

  public func request(state: UInt64) -> QueueHandoffReply {
    request(
      state: state, timeout: QueueHandoff.readyTimeout(successorPreparing:),
      isPreparing: isPreparing)
  }

  func request(
    state: UInt64, timeout: (Bool) -> TimeInterval, isPreparing: () -> Bool
  ) -> QueueHandoffReply {
    let noReply = QueueHandoffReply(elapsed: nil, waitedForPreparation: false)
    let ready = DispatchSemaphore(value: 0)
    var readyToken: Int32 = 0
    let readyQueue = DispatchQueue(label: "Countersign.QueueHandoff")
    let readyStatus = notify_register_dispatch(readyName, &readyToken, readyQueue) { _ in
      ready.signal()
    }
    guard readyStatus == NOTIFY_STATUS_OK else { return noReply }
    defer { _ = notify_cancel(readyToken) }

    var requestToken: Int32 = 0
    guard notify_register_check(requestName, &requestToken) == NOTIFY_STATUS_OK else {
      return noReply
    }
    defer { _ = notify_cancel(requestToken) }
    guard notify_set_state(requestToken, state) == NOTIFY_STATUS_OK else { return noReply }

    let clock = ContinuousClock()
    let start = clock.now
    let postedAt = DispatchTime.now()
    guard notify_post(requestName) == NOTIFY_STATUS_OK else { return noReply }
    let preparingAtPost = isPreparing()
    if ready.wait(timeout: postedAt + timeout(preparingAtPost)) == .success {
      return QueueHandoffReply(elapsed: clock.now - start, waitedForPreparation: preparingAtPost)
    }
    guard !preparingAtPost, isPreparing() else {
      return QueueHandoffReply(elapsed: nil, waitedForPreparation: preparingAtPost)
    }
    guard ready.wait(timeout: postedAt + timeout(true)) == .success else {
      return QueueHandoffReply(elapsed: nil, waitedForPreparation: true)
    }
    return QueueHandoffReply(elapsed: clock.now - start, waitedForPreparation: true)
  }
}

public final class QueueHandoffPreparation: Sendable {
  private let registration: NotifyRegistration

  init(registration: NotifyRegistration) {
    self.registration = registration
  }

  public func begin() {
    registration.setState(1)
  }

  public func end() {
    registration.setState(0)
  }

  public func cancel() {
    registration.cancel()
  }
}

public final class QueueShownDisplay: Sendable {
  private let registration: NotifyRegistration

  init(registration: NotifyRegistration) {
    self.registration = registration
  }

  public func publish(displayID: UInt32?) {
    registration.setState(QueueHandoff.state(displayID: displayID))
  }

  public func clear() {
    registration.setState(0)
  }

  public func cancel() {
    registration.cancel()
  }
}

final class NotifyRegistration: Sendable {
  private let token: OSAllocatedUnfairLock<Int32?>

  init?(name: String) {
    var registered: Int32 = 0
    guard notify_register_check(name, &registered) == NOTIFY_STATUS_OK else { return nil }
    token = OSAllocatedUnfairLock(initialState: registered)
  }

  func setState(_ state: UInt64) {
    token.withLock { current in
      guard let current else { return }
      _ = notify_set_state(current, state)
    }
  }

  func state() -> UInt64? {
    token.withLock { current -> UInt64? in
      guard let current else { return nil }
      var state: UInt64 = 0
      guard notify_get_state(current, &state) == NOTIFY_STATUS_OK else { return nil }
      return state
    }
  }

  func cancel() {
    let taken = token.withLock { current -> Int32? in
      let taken = current
      current = nil
      return taken
    }
    guard let taken else { return }
    _ = notify_cancel(taken)
  }

  deinit {
    cancel()
  }
}

public final class QueueHandoffListener: Sendable {
  private let token: OSAllocatedUnfairLock<Int32?>

  init(token: Int32) {
    self.token = OSAllocatedUnfairLock(initialState: token)
  }

  public func cancel() {
    let taken = token.withLock { current -> Int32? in
      let taken = current
      current = nil
      return taken
    }
    guard let taken else { return }
    _ = notify_cancel(taken)
  }

  deinit {
    cancel()
  }
}
