import Testing

@testable import ApprovalCore

@Suite struct KeyRouterTests {
  private func route(
    _ kind: KeyKind, _ modifiers: KeyModifiers = [], editing: Bool = false,
    markedText: Bool = false, repeating: Bool = false, armed: Bool = true
  ) -> KeyRoute {
    KeyRouter.route(
      kind, modifiers: modifiers, isEditingText: editing, hasMarkedText: markedText,
      isRepeat: repeating, isArmed: armed)
  }

  private static let allKinds: [KeyKind] = [
    .escape, .returnKey, .delete(usedByView: true), .delete(usedByView: false),
    .navigation(usedByView: true), .navigation(usedByView: false), .other,
  ]

  @Test func markedTextPassesEveryKeyThrough() {
    for kind in Self.allKinds {
      #expect(route(kind, editing: true, markedText: true) == .passThrough)
      #expect(route(kind, [.shift], editing: true, markedText: true, armed: false) == .passThrough)
    }
  }

  @Test func escapeDismissesOnceArmedInEveryState() {
    #expect(route(.escape) == .dismiss)
    #expect(route(.escape, editing: true) == .dismiss)
    #expect(route(.escape, [.command]) == .dismiss)
    #expect(route(.escape, [.shift]) == .dismiss)
  }

  @Test func escapeIsSwallowedDuringTheLock() {
    #expect(route(.escape, armed: false) == .swallow)
    #expect(route(.escape, editing: true, armed: false) == .swallow)
  }

  @Test func returnIsPrimaryOnceArmed() {
    #expect(route(.returnKey) == .primary)
    #expect(route(.returnKey, editing: true) == .primary)
  }

  @Test func commandReturnIsAlternateOnceArmed() {
    #expect(route(.returnKey, [.command]) == .alternate)
    #expect(route(.returnKey, [.command], editing: true) == .alternate)
  }

  @Test func returnAndCommandReturnAreSwallowedDuringTheLock() {
    #expect(route(.returnKey, armed: false) == .swallow)
    #expect(route(.returnKey, [.command], armed: false) == .swallow)
    #expect(route(.returnKey, editing: true, armed: false) == .swallow)
  }

  @Test func shiftOrOptionReturnInAFieldInsertsANewline() {
    #expect(route(.returnKey, [.shift], editing: true) == .insertNewline)
    #expect(route(.returnKey, [.option], editing: true) == .insertNewline)
    #expect(route(.returnKey, [.shift], editing: true, armed: false) == .swallow)
    #expect(route(.returnKey, [.option], editing: true, armed: false) == .swallow)
  }

  @Test func shiftOrOptionReturnOutsideAFieldStepsAside() {
    #expect(route(.returnKey, [.shift]) == .stepAside)
    #expect(route(.returnKey, [.option]) == .stepAside)
    #expect(route(.returnKey, [.shift, .option]) == .stepAside)
    #expect(route(.returnKey, [.shift], armed: false) == .stepAside)
  }

  @Test func otherReturnShortcutsPassThroughOnceArmed() {
    #expect(route(.returnKey, [.control]) == .passThrough)
    #expect(route(.returnKey, [.command, .shift]) == .passThrough)
    #expect(route(.returnKey, [.shift, .option], editing: true) == .passThrough)
  }

  @Test func otherReturnShortcutsAreSwallowedDuringTheLock() {
    #expect(route(.returnKey, [.control], armed: false) == .swallow)
    #expect(route(.returnKey, [.command, .shift], armed: false) == .swallow)
    #expect(route(.returnKey, [.shift, .option], editing: true, armed: false) == .swallow)
  }

  @Test func aNavigationKeyTheViewUsesNavigatesOnceArmed() {
    #expect(route(.navigation(usedByView: true)) == .navigate)
    #expect(route(.navigation(usedByView: true), [.shift]) == .navigate)
  }

  @Test func aNavigationKeyTheViewUsesIsSwallowedDuringTheLock() {
    #expect(route(.navigation(usedByView: true), armed: false) == .swallow)
    #expect(route(.navigation(usedByView: true), [.shift], armed: false) == .swallow)
  }

  @Test func aNavigationKeyTheViewDoesNotUseStepsAside() {
    #expect(route(.navigation(usedByView: false)) == .stepAside)
    #expect(route(.navigation(usedByView: false), [.shift]) == .stepAside)
    #expect(route(.navigation(usedByView: false), armed: false) == .stepAside)
  }

  @Test func anOptionNavigationKeyStepsAsideEvenWhenTheViewUsesIt() {
    #expect(route(.navigation(usedByView: true), [.option]) == .stepAside)
    #expect(route(.navigation(usedByView: true), [.option, .shift], armed: false) == .stepAside)
  }

  @Test func navigationKeysGoToAFieldBeingEdited() {
    #expect(route(.navigation(usedByView: true), editing: true) == .passThrough)
    #expect(route(.navigation(usedByView: false), [.option], editing: true) == .passThrough)
    #expect(route(.navigation(usedByView: true), editing: true, armed: false) == .passThrough)
  }

  @Test func commandAndControlNavigationKeysPassThrough() {
    #expect(route(.navigation(usedByView: true), [.command]) == .passThrough)
    #expect(route(.navigation(usedByView: false), [.control]) == .passThrough)
    #expect(route(.navigation(usedByView: true), [.command], armed: false) == .passThrough)
  }

  @Test func aPlainUnusedKeyStepsAside() {
    #expect(route(.other) == .stepAside)
    #expect(route(.other, [.shift]) == .stepAside)
    #expect(route(.other, [.option]) == .stepAside)
    #expect(route(.other, [.shift, .option]) == .stepAside)
  }

  @Test func aPlainUnusedKeyStepsAsideDuringTheLock() {
    #expect(route(.other, armed: false) == .stepAside)
    #expect(route(.other, [.shift], armed: false) == .stepAside)
  }

  @Test func commandAndControlShortcutsPassThrough() {
    #expect(route(.other, [.command]) == .passThrough)
    #expect(route(.other, [.control]) == .passThrough)
    #expect(route(.other, [.command, .shift]) == .passThrough)
    #expect(route(.other, [.control, .option]) == .passThrough)
    #expect(route(.other, [.command], armed: false) == .passThrough)
  }

  @Test func everyOtherKeyGoesToAFieldBeingEdited() {
    #expect(route(.other, editing: true) == .passThrough)
    #expect(route(.other, [.shift], editing: true) == .passThrough)
    #expect(route(.other, [.option], editing: true, armed: false) == .passThrough)
  }

  @Test func escapeRepeatSwallowsInsteadOfDismissing() {
    #expect(route(.escape, repeating: true) == .swallow)
    #expect(route(.escape, editing: true, repeating: true) == .swallow)
    #expect(route(.escape, [.command], repeating: true) == .swallow)
    #expect(route(.escape, [.shift], repeating: true) == .swallow)
    #expect(route(.escape, repeating: true, armed: false) == .swallow)
    #expect(route(.escape, editing: true, repeating: true, armed: false) == .swallow)
  }

  @Test func returnRepeatSwallowsInsteadOfActing() {
    #expect(route(.returnKey, repeating: true) == .swallow)
    #expect(route(.returnKey, [.command], repeating: true) == .swallow)
    #expect(route(.returnKey, editing: true, repeating: true) == .swallow)
    #expect(route(.returnKey, [.command], editing: true, repeating: true) == .swallow)
    #expect(route(.returnKey, repeating: true, armed: false) == .swallow)
    #expect(route(.returnKey, [.command], repeating: true, armed: false) == .swallow)
  }

  @Test func shiftOrOptionReturnRepeatOutsideAFieldStaysSwallowed() {
    #expect(route(.returnKey, [.shift], repeating: true) == .swallow)
    #expect(route(.returnKey, [.option], repeating: true) == .swallow)
    #expect(route(.returnKey, [.shift, .option], repeating: true) == .swallow)
    #expect(route(.returnKey, [.shift], repeating: true, armed: false) == .swallow)
  }

  @Test func shiftOrOptionReturnRepeatInAFieldStillInsertsANewline() {
    #expect(route(.returnKey, [.shift], editing: true, repeating: true) == .insertNewline)
    #expect(route(.returnKey, [.option], editing: true, repeating: true) == .insertNewline)
    #expect(route(.returnKey, [.shift], editing: true, repeating: true, armed: false) == .swallow)
    #expect(route(.returnKey, [.option], editing: true, repeating: true, armed: false) == .swallow)
  }

  @Test func otherReturnShortcutRepeatStillPassesThrough() {
    #expect(route(.returnKey, [.control], repeating: true) == .passThrough)
    #expect(route(.returnKey, [.command, .shift], repeating: true) == .passThrough)
    #expect(route(.returnKey, [.shift, .option], editing: true, repeating: true) == .passThrough)
    #expect(route(.returnKey, [.control], repeating: true, armed: false) == .swallow)
  }

  @Test func markedTextWinsOverARepeatedReturnOrEscape() {
    #expect(route(.escape, editing: true, markedText: true, repeating: true) == .passThrough)
    #expect(route(.returnKey, editing: true, markedText: true, repeating: true) == .passThrough)
    #expect(
      route(.returnKey, [.shift], editing: true, markedText: true, repeating: true)
        == .passThrough)
  }

  @Test func navigationAndOtherKeysIgnoreTheRepeatFlag() {
    for repeating in [false, true] {
      #expect(route(.navigation(usedByView: true), repeating: repeating) == .navigate)
      #expect(route(.navigation(usedByView: true), repeating: repeating, armed: false) == .swallow)
      #expect(route(.navigation(usedByView: false), repeating: repeating) == .stepAside)
      #expect(
        route(.navigation(usedByView: true), [.option], repeating: repeating) == .stepAside)
      #expect(route(.other, repeating: repeating) == .stepAside)
      #expect(route(.other, [.command], repeating: repeating) == .passThrough)
      #expect(route(.other, editing: true, repeating: repeating) == .passThrough)
    }
  }

  @Test func aBareDeleteTheViewUsesIsTheSecondaryActionOnceArmed() {
    #expect(route(.delete(usedByView: true)) == .secondary)
  }

  @Test func aBareDeleteTheViewUsesIsSwallowedDuringTheLock() {
    #expect(route(.delete(usedByView: true), armed: false) == .swallow)
  }

  @Test func aDeleteEditingTextPassesThroughToDeleteACharacter() {
    #expect(route(.delete(usedByView: true), editing: true) == .passThrough)
    #expect(route(.delete(usedByView: false), editing: true) == .passThrough)
    #expect(route(.delete(usedByView: true), editing: true, armed: false) == .passThrough)
    #expect(route(.delete(usedByView: true), [.shift], editing: true) == .passThrough)
  }

  @Test func deleteWithMarkedTextPassesThrough() {
    #expect(route(.delete(usedByView: true), editing: true, markedText: true) == .passThrough)
    #expect(
      route(.delete(usedByView: true), [.shift], editing: true, markedText: true, armed: false)
        == .passThrough)
  }

  @Test func aDeleteWithAnyModifierRoutesLikeAnUnusedKey() {
    #expect(route(.delete(usedByView: true), [.shift]) == .stepAside)
    #expect(route(.delete(usedByView: true), [.option]) == .stepAside)
    #expect(route(.delete(usedByView: true), [.shift, .option]) == .stepAside)
    #expect(route(.delete(usedByView: true), [.command]) == .passThrough)
    #expect(route(.delete(usedByView: true), [.control]) == .passThrough)
    #expect(route(.delete(usedByView: true), [.command, .shift]) == .passThrough)
  }

  @Test func aDeleteTheViewDoesNotUseStepsAside() {
    #expect(route(.delete(usedByView: false)) == .stepAside)
    #expect(route(.delete(usedByView: false), armed: false) == .stepAside)
    #expect(route(.delete(usedByView: false), [.command]) == .passThrough)
  }

  @Test func deleteRepeatSwallowsInsteadOfActing() {
    #expect(route(.delete(usedByView: true), repeating: true) == .swallow)
    #expect(route(.delete(usedByView: true), repeating: true, armed: false) == .swallow)
  }

  @Test func deleteRepeatOnAnUnusedOrModifiedKeyIgnoresTheRepeatFlag() {
    for repeating in [false, true] {
      #expect(route(.delete(usedByView: false), repeating: repeating) == .stepAside)
      #expect(route(.delete(usedByView: true), [.shift], repeating: repeating) == .stepAside)
      #expect(route(.delete(usedByView: true), [.command], repeating: repeating) == .passThrough)
    }
  }

  private func routeWithDropdown(
    _ kind: KeyKind, _ modifiers: KeyModifiers = [], editing: Bool = false,
    markedText: Bool = false, repeating: Bool = false, armed: Bool = true
  ) -> KeyRoute {
    KeyRouter.route(
      kind, modifiers: modifiers, isEditingText: editing, hasMarkedText: markedText,
      isRepeat: repeating, isArmed: armed, isDropdownOpen: true)
  }

  @Test func escapeClosesAnOpenDropdownInsteadOfDismissing() {
    #expect(routeWithDropdown(.escape) == .closeDropdown)
    #expect(routeWithDropdown(.escape, editing: true) == .closeDropdown)
    #expect(routeWithDropdown(.escape, repeating: true) == .closeDropdown)
    #expect(routeWithDropdown(.escape, armed: false) == .closeDropdown)
  }

  @Test func aBareReturnPicksInAnOpenDropdownOnceArmed() {
    #expect(routeWithDropdown(.returnKey) == .primary)
    #expect(routeWithDropdown(.returnKey, editing: true) == .primary)
    #expect(routeWithDropdown(.returnKey, armed: false) == .swallow)
    #expect(routeWithDropdown(.returnKey, repeating: true) == .swallow)
  }

  @Test func aModifiedReturnIsSwallowedByAnOpenDropdown() {
    #expect(routeWithDropdown(.returnKey, [.shift], editing: true) == .swallow)
    #expect(routeWithDropdown(.returnKey, [.control]) == .swallow)
  }

  @Test func commandReturnClosesAnOpenDropdown() {
    #expect(routeWithDropdown(.returnKey, [.command]) == .closeDropdown)
    #expect(routeWithDropdown(.returnKey, [.command], armed: false) == .closeDropdown)
    #expect(routeWithDropdown(.returnKey, [.command], repeating: true) == .closeDropdown)
  }

  @Test func keysTheDropdownUsesNavigateItEvenWhileAFieldIsEdited() {
    #expect(routeWithDropdown(.navigation(usedByView: true)) == .navigate)
    #expect(routeWithDropdown(.navigation(usedByView: true), [.shift]) == .navigate)
    #expect(routeWithDropdown(.navigation(usedByView: true), editing: true) == .navigate)
    #expect(routeWithDropdown(.navigation(usedByView: true), armed: false) == .swallow)
  }

  @Test func keysTheDropdownDoesNotUseRouteAsUnusedKeys() {
    #expect(routeWithDropdown(.navigation(usedByView: false)) == .stepAside)
    #expect(routeWithDropdown(.navigation(usedByView: true), [.option]) == .stepAside)
    #expect(routeWithDropdown(.navigation(usedByView: true), [.command]) == .passThrough)
    #expect(routeWithDropdown(.navigation(usedByView: false), editing: true) == .passThrough)
    #expect(routeWithDropdown(.other) == .stepAside)
    #expect(routeWithDropdown(.other, [.command]) == .passThrough)
  }

  @Test func deleteNeverActsOnTheViewBehindAnOpenDropdown() {
    #expect(routeWithDropdown(.delete(usedByView: true)) == .stepAside)
    #expect(routeWithDropdown(.delete(usedByView: true), editing: true) == .passThrough)
    #expect(routeWithDropdown(.delete(usedByView: true), [.command]) == .passThrough)
  }

  @Test func markedTextWinsOverAnOpenDropdown() {
    #expect(routeWithDropdown(.escape, editing: true, markedText: true) == .passThrough)
    #expect(routeWithDropdown(.returnKey, editing: true, markedText: true) == .passThrough)
  }

  @Test func modifiersAreIndependentFlags() {
    let modifiers: KeyModifiers = [.command, .shift]
    #expect(modifiers.contains(.command))
    #expect(modifiers.contains(.shift))
    #expect(!modifiers.contains(.control))
    #expect(!modifiers.contains(.option))
    #expect(Set([KeyModifiers.command, .control, .option, .shift]).count == 4)
  }
}
