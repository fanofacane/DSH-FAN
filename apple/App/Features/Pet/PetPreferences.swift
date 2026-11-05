// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/pets/{pet_prefs,pet_state}.dart.
import Foundation
import SwiftUI

enum PetSize: String, CaseIterable {
    case small, medium, large

    var height: CGFloat {
        switch self {
        case .small: 22
        case .medium: 30
        case .large: 40
        }
    }

    var label: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Standard")
        case .large: String(localized: "Large")
        }
    }
}

enum PetOutsideDisplay: String, CaseIterable {
    case whileActive, always
    var label: String {
        switch self {
        case .whileActive: String(localized: "When active")
        case .always: String(localized: "Always")
        }
    }
}

struct PetPreferences: Equatable {
    static let none = "none"
    var packID: String
    var size: PetSize
    var quiet: Bool
    var position: CGFloat
    var hiddenUntil: Date?
    var outside = false
    var outsideDisplay = PetOutsideDisplay.whileActive

    init(defaults: UserDefaults, defaultPack: String?) {
        packID = defaults.string(forKey: "pet.pack")
            ?? ((defaults.object(forKey: "pet.enabled") as? Bool ?? true) ? defaultPack ?? Self.none : Self.none)
        size = defaults.string(forKey: "pet.size").flatMap(PetSize.init(rawValue:))
            ?? PetSize.allCases.min { abs($0.height - defaults.double(forKey: "pet.bodyHeight")) < abs($1.height - defaults.double(forKey: "pet.bodyHeight")) }
            ?? .medium
        if defaults.object(forKey: "pet.size") == nil && defaults.object(forKey: "pet.bodyHeight") == nil { size = .medium }
        quiet = defaults.bool(forKey: "pet.quiet")
        let stored = defaults.object(forKey: "pet.position") as? Double ?? 0.25
        position = stored.isFinite ? min(1, max(0, stored)) : 0.25
        hiddenUntil = defaults.object(forKey: "pet.hiddenUntil") as? Date
        outside = defaults.bool(forKey: "pet.outside")
        outsideDisplay = defaults.string(forKey: "pet.outsideDisplay").flatMap(PetOutsideDisplay.init(rawValue:)) ?? .whileActive
    }

    func save(to defaults: UserDefaults) {
        defaults.set(packID, forKey: "pet.pack")
        defaults.set(size.rawValue, forKey: "pet.size")
        defaults.set(quiet, forKey: "pet.quiet")
        defaults.set(Double(position), forKey: "pet.position")
        defaults.set(hiddenUntil, forKey: "pet.hiddenUntil")
        defaults.set(outside, forKey: "pet.outside")
        defaults.set(outsideDisplay.rawValue, forKey: "pet.outsideDisplay")
    }
}
