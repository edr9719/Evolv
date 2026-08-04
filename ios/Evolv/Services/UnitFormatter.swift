import Foundation

/// Centralized unit conversion + formatting.
/// Internal storage is always kg / cm. Display converts based on the user's profile preferences.
enum UnitFormatter {

    // MARK: - Mass

    static func displayMass(_ kg: Double, unit: MassUnit, fractionDigits: Int = 1) -> String {
        let value = unit == .kg ? kg : kg * 2.2046226218
        return "\(format(value, digits: fractionDigits)) \(unit.label)"
    }

    static func displayMassNumber(_ kg: Double, unit: MassUnit) -> Double {
        unit == .kg ? kg : kg * 2.2046226218
    }

    static func toKg(_ value: Double, unit: MassUnit) -> Double {
        unit == .kg ? value : value / 2.2046226218
    }

    static func signedMass(_ kg: Double, unit: MassUnit, fractionDigits: Int = 1) -> String {
        let v = displayMassNumber(kg, unit: unit)
        let sign = v > 0 ? "+" : ""
        return "\(sign)\(format(v, digits: fractionDigits)) \(unit.label)"
    }

    // MARK: - Length

    static func displayLength(_ cm: Double, unit: LengthUnit, fractionDigits: Int = 1) -> String {
        let value = unit == .cm ? cm : cm / 2.54
        return "\(format(value, digits: fractionDigits)) \(unit.label)"
    }

    static func displayLengthNumber(_ cm: Double, unit: LengthUnit) -> Double {
        unit == .cm ? cm : cm / 2.54
    }

    static func toCm(_ value: Double, unit: LengthUnit) -> Double {
        unit == .cm ? value : value * 2.54
    }

    static func signedLength(_ cm: Double, unit: LengthUnit, fractionDigits: Int = 1) -> String {
        let v = displayLengthNumber(cm, unit: unit)
        let sign = v > 0 ? "+" : ""
        return "\(sign)\(format(v, digits: fractionDigits)) \(unit.label)"
    }

    // MARK: - Height (special — cm <-> ft/in)

    static func displayHeight(_ cm: Double, unit: LengthUnit) -> String {
        if unit == .cm { return "\(Int(cm.rounded())) cm" }
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
        return "\(feet)′ \(inches)″"
    }

    // MARK: - Sensible step/range conversions for editors

    static func massRange(unit: MassUnit) -> ClosedRange<Double> {
        unit == .kg ? 35...200 : 77...440
    }
    static func massStep(unit: MassUnit) -> Double {
        unit == .kg ? 0.1 : 0.2
    }
    static func bodyPartRange(unit: LengthUnit) -> ClosedRange<Double> {
        unit == .cm ? 20...160 : 8...64
    }
    static func bodyPartStep(unit: LengthUnit) -> Double {
        unit == .cm ? 0.5 : 0.25
    }

    // MARK: - Helpers

    private static func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
