public struct KeyModifiers: OptionSet, Sendable, Hashable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let command = KeyModifiers(rawValue: 1 << 0)
  public static let control = KeyModifiers(rawValue: 1 << 1)
  public static let option = KeyModifiers(rawValue: 1 << 2)
  public static let shift = KeyModifiers(rawValue: 1 << 3)
}

public enum KeyKind: Sendable, Equatable {
  case escape
  case returnKey
  case delete(usedByView: Bool)
  case navigation(usedByView: Bool)
  case other
}

public enum KeyRoute: Sendable, Equatable {
  case passThrough
  case swallow
  case dismiss
  case primary
  case alternate
  case secondary
  case navigate
  case insertNewline
  case stepAside
  case closeDropdown
}

public enum KeyRouter {
  public static func route(
    _ kind: KeyKind, modifiers: KeyModifiers, isEditingText: Bool, hasMarkedText: Bool,
    isRepeat: Bool, isArmed: Bool, isDropdownOpen: Bool = false
  ) -> KeyRoute {
    guard !hasMarkedText else { return .passThrough }
    if isDropdownOpen {
      return routeInDropdown(
        kind, modifiers: modifiers, isEditingText: isEditingText, isRepeat: isRepeat,
        isArmed: isArmed)
    }
    let isShortcut = !modifiers.isDisjoint(with: [.command, .control])
    switch kind {
    case .escape:
      return repeatGuarded(isArmed ? .dismiss : .swallow, isRepeat: isRepeat)
    case .returnKey:
      let route = routeReturn(
        modifiers: modifiers, isShortcut: isShortcut, isEditingText: isEditingText,
        isArmed: isArmed)
      return repeatGuarded(route, isRepeat: isRepeat)
    case .delete(let usedByView):
      return routeDelete(
        usedByView: usedByView, modifiers: modifiers, isShortcut: isShortcut,
        isEditingText: isEditingText, isArmed: isArmed, isRepeat: isRepeat)
    case .navigation(let usedByView):
      guard !isEditingText, !isShortcut else { return .passThrough }
      guard usedByView, !modifiers.contains(.option) else { return .stepAside }
      return isArmed ? .navigate : .swallow
    case .other:
      guard !isEditingText, !isShortcut else { return .passThrough }
      return .stepAside
    }
  }

  private static func repeatGuarded(_ route: KeyRoute, isRepeat: Bool) -> KeyRoute {
    guard isRepeat else { return route }
    switch route {
    case .dismiss, .primary, .alternate, .secondary, .stepAside:
      return .swallow
    case .passThrough, .swallow, .navigate, .insertNewline, .closeDropdown:
      return route
    }
  }

  private static func routeInDropdown(
    _ kind: KeyKind, modifiers: KeyModifiers, isEditingText: Bool, isRepeat: Bool,
    isArmed: Bool
  ) -> KeyRoute {
    let routeClosed = { (closedKind: KeyKind) in
      route(
        closedKind, modifiers: modifiers, isEditingText: isEditingText, hasMarkedText: false,
        isRepeat: isRepeat, isArmed: isArmed)
    }
    switch kind {
    case .escape:
      return .closeDropdown
    case .returnKey:
      if modifiers == .command { return .closeDropdown }
      guard modifiers.isEmpty else { return .swallow }
      return repeatGuarded(isArmed ? .primary : .swallow, isRepeat: isRepeat)
    case .navigation(let usedByDropdown):
      guard usedByDropdown, modifiers.isDisjoint(with: [.command, .control, .option]) else {
        return routeClosed(.navigation(usedByView: false))
      }
      return isArmed ? .navigate : .swallow
    case .delete:
      return routeClosed(.delete(usedByView: false))
    case .other:
      return routeClosed(.other)
    }
  }

  private static func routeDelete(
    usedByView: Bool, modifiers: KeyModifiers, isShortcut: Bool, isEditingText: Bool,
    isArmed: Bool, isRepeat: Bool
  ) -> KeyRoute {
    guard !isEditingText else { return .passThrough }
    guard modifiers.isEmpty, usedByView else {
      guard !isShortcut else { return .passThrough }
      return .stepAside
    }
    return repeatGuarded(isArmed ? .secondary : .swallow, isRepeat: isRepeat)
  }

  private static func routeReturn(
    modifiers: KeyModifiers, isShortcut: Bool, isEditingText: Bool, isArmed: Bool
  ) -> KeyRoute {
    if modifiers.isEmpty {
      return isArmed ? .primary : .swallow
    }
    if modifiers == .command {
      return isArmed ? .alternate : .swallow
    }
    if isEditingText, modifiers == .shift || modifiers == .option {
      return isArmed ? .insertNewline : .swallow
    }
    if isEditingText || isShortcut {
      return isArmed ? .passThrough : .swallow
    }
    return .stepAside
  }
}
