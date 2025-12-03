// ============================================================
// QueryActions.swift
// ARO Runtime - Data Pipeline Action Implementations (ARO-0018)
// ============================================================

import Foundation
import AROParser

// MARK: - Map Action

/// Maps a collection to a different type by extracting matching fields
///
/// The Map action transforms a collection to a target type defined in OpenAPI.
/// Fields with matching names are automatically copied from source to target.
///
/// ## Example
/// ```aro
/// <Map> the <summaries: List<UserSummary>> from the <users>.
/// ```
public struct MapAction: ActionImplementation {
    public static let role: ActionRole = .own
    public static let verbs: Set<String> = ["map"]
    public static let validPrepositions: Set<Preposition> = [.from, .to]

    public init() {}

    public func execute(
        result: ResultDescriptor,
        object: ObjectDescriptor,
        context: ExecutionContext
    ) async throws -> any Sendable {
        try validatePreposition(object.preposition)

        // Get source collection
        guard let source = context.resolveAny(object.base) else {
            throw ActionError.undefinedVariable(object.base)
        }

        // Handle array mapping
        if let array = source as? [any Sendable] {
            // If there's a field specifier, extract that field from each item
            if let field = result.specifiers.first {
                return array.compactMap { item -> (any Sendable)? in
                    if let dict = item as? [String: any Sendable] {
                        return dict[field]
                    }
                    return nil
                }
            }

            // Map entire objects - filter fields based on target type
            // For now, pass through the entire objects
            // OpenAPI type filtering would be done by a type-aware runtime
            return array
        }

        // Handle dictionary - extract field
        if let dict = source as? [String: any Sendable] {
            if let field = result.specifiers.first {
                if let value = dict[field] {
                    return value
                }
                throw ActionError.undefinedVariable(field)
            }
            return dict
        }

        return source
    }
}

// MARK: - Reduce Action

/// Reduces a collection to a single value using an aggregation function
///
/// The Reduce action applies aggregation functions (sum, avg, count, min, max)
/// to a collection and returns a single value.
///
/// ## Example
/// ```aro
/// <Reduce> the <total: Float> from the <orders> with sum(<amount>).
/// <Reduce> the <count: Integer> from the <users> with count().
/// ```
public struct ReduceAction: ActionImplementation {
    public static let role: ActionRole = .own
    public static let verbs: Set<String> = ["reduce", "aggregate"]
    public static let validPrepositions: Set<Preposition> = [.from, .with]

    public init() {}

    public func execute(
        result: ResultDescriptor,
        object: ObjectDescriptor,
        context: ExecutionContext
    ) async throws -> any Sendable {
        try validatePreposition(object.preposition)

        // Get source collection
        guard let source = context.resolveAny(object.base) else {
            throw ActionError.undefinedVariable(object.base)
        }

        // Get aggregation function from specifiers or expression
        let aggregateFunc = result.specifiers.first?.lowercased() ?? "count"

        // Get field to aggregate (if specified)
        let field = result.specifiers.count > 1 ? result.specifiers[1] : nil

        // Handle array aggregation
        guard let array = source as? [any Sendable] else {
            // Single value - return as-is for count=1, value for others
            switch aggregateFunc {
            case "count":
                return 1
            default:
                return source
            }
        }

        // Extract numeric values from array
        let values: [Double] = array.compactMap { item -> Double? in
            if let field = field, let dict = item as? [String: any Sendable] {
                return asDouble(dict[field])
            }
            return asDouble(item)
        }

        // Apply aggregation function
        switch aggregateFunc {
        case "count":
            return array.count

        case "sum":
            return values.reduce(0, +)

        case "avg", "average":
            guard !values.isEmpty else { return 0.0 }
            return values.reduce(0, +) / Double(values.count)

        case "min":
            return values.min() ?? 0.0

        case "max":
            return values.max() ?? 0.0

        case "first":
            return array.first ?? ([] as [any Sendable])

        case "last":
            return array.last ?? ([] as [any Sendable])

        default:
            return array.count
        }
    }

    private func asDouble(_ value: Any?) -> Double? {
        guard let value = value else { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let f = value as? Float { return Double(f) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

// MARK: - Enhanced Filter with Predicates

/// Filters a collection using predicates
///
/// This enhanced filter supports comparison operators for filtering.
///
/// ## Example
/// ```aro
/// <Filter> the <active: List<User>> from the <users> where <status> is "active".
/// ```
public struct PredicateFilterAction: ActionImplementation {
    public static let role: ActionRole = .own
    public static let verbs: Set<String> = ["filter-where"]
    public static let validPrepositions: Set<Preposition> = [.from]

    public init() {}

    public func execute(
        result: ResultDescriptor,
        object: ObjectDescriptor,
        context: ExecutionContext
    ) async throws -> any Sendable {
        try validatePreposition(object.preposition)

        // Get source collection
        guard let source = context.resolveAny(object.base) else {
            throw ActionError.undefinedVariable(object.base)
        }

        // Get predicate from specifiers: [field, operator, value]
        guard result.specifiers.count >= 3 else {
            // No predicate - return all
            return source
        }

        let field = result.specifiers[0]
        let op = result.specifiers[1]
        let expectedValue = result.specifiers[2]

        // Handle array filtering with predicate
        guard let array = source as? [any Sendable] else {
            return source
        }

        return array.filter { item in
            guard let dict = item as? [String: any Sendable],
                  let actualValue = dict[field] else {
                return false
            }
            return matchesPredicate(actual: actualValue, op: op, expected: expectedValue)
        }
    }

    private func matchesPredicate(actual: Any, op: String, expected: String) -> Bool {
        let actualStr = String(describing: actual)

        switch op.lowercased() {
        case "is", "==", "equals":
            return actualStr == expected

        case "is-not", "!=", "not-equals":
            return actualStr != expected

        case ">", "gt":
            if let actualNum = Double(actualStr), let expectedNum = Double(expected) {
                return actualNum > expectedNum
            }
            return actualStr > expected

        case ">=", "gte":
            if let actualNum = Double(actualStr), let expectedNum = Double(expected) {
                return actualNum >= expectedNum
            }
            return actualStr >= expected

        case "<", "lt":
            if let actualNum = Double(actualStr), let expectedNum = Double(expected) {
                return actualNum < expectedNum
            }
            return actualStr < expected

        case "<=", "lte":
            if let actualNum = Double(actualStr), let expectedNum = Double(expected) {
                return actualNum <= expectedNum
            }
            return actualStr <= expected

        case "contains":
            return actualStr.contains(expected)

        case "starts-with":
            return actualStr.hasPrefix(expected)

        case "ends-with":
            return actualStr.hasSuffix(expected)

        case "in":
            // Expected should be comma-separated values
            let values = expected.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            return values.contains(actualStr)

        default:
            return actualStr == expected
        }
    }
}

// MARK: - Aggregation Helpers

/// Helper functions for collection aggregations
public enum Aggregations {
    /// Count items in a collection
    public static func count(_ collection: Any) -> Int {
        if let array = collection as? [Any] {
            return array.count
        }
        if let dict = collection as? [String: Any] {
            return dict.count
        }
        return 1
    }

    /// Sum numeric values in a collection
    public static func sum(_ collection: Any, field: String? = nil) -> Double {
        guard let array = collection as? [Any] else { return 0 }

        return array.compactMap { item -> Double? in
            if let field = field, let dict = item as? [String: Any] {
                return asDouble(dict[field])
            }
            return asDouble(item)
        }.reduce(0, +)
    }

    /// Average numeric values in a collection
    public static func avg(_ collection: Any, field: String? = nil) -> Double {
        guard let array = collection as? [Any], !array.isEmpty else { return 0 }

        let values = array.compactMap { item -> Double? in
            if let field = field, let dict = item as? [String: Any] {
                return asDouble(dict[field])
            }
            return asDouble(item)
        }

        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Minimum value in a collection
    public static func min(_ collection: Any, field: String? = nil) -> Double? {
        guard let array = collection as? [Any] else { return nil }

        let values = array.compactMap { item -> Double? in
            if let field = field, let dict = item as? [String: Any] {
                return asDouble(dict[field])
            }
            return asDouble(item)
        }

        return values.min()
    }

    /// Maximum value in a collection
    public static func max(_ collection: Any, field: String? = nil) -> Double? {
        guard let array = collection as? [Any] else { return nil }

        let values = array.compactMap { item -> Double? in
            if let field = field, let dict = item as? [String: Any] {
                return asDouble(dict[field])
            }
            return asDouble(item)
        }

        return values.max()
    }

    private static func asDouble(_ value: Any?) -> Double? {
        guard let value = value else { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let f = value as? Float { return Double(f) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}

// MARK: - Collection Extensions

extension Array where Element == any Sendable {
    /// Filter collection with a field predicate
    public func whereField(_ field: String, equals value: String) -> [any Sendable] {
        filter { item in
            guard let dict = item as? [String: any Sendable],
                  let fieldValue = dict[field] else {
                return false
            }
            return String(describing: fieldValue) == value
        }
    }

    /// Filter collection with a numeric comparison
    public func whereField(_ field: String, greaterThan value: Double) -> [any Sendable] {
        filter { item in
            guard let dict = item as? [String: any Sendable],
                  let fieldValue = dict[field],
                  let numValue = fieldValue as? Double ?? (fieldValue as? Int).map(Double.init) else {
                return false
            }
            return numValue > value
        }
    }

    /// Extract a single field from all items
    public func pluck(_ field: String) -> [any Sendable] {
        compactMap { item -> (any Sendable)? in
            guard let dict = item as? [String: any Sendable] else { return nil }
            return dict[field]
        }
    }

    /// Sort by a field
    public func sortedBy(_ field: String, ascending: Bool = true) -> [any Sendable] {
        sorted { lhs, rhs in
            guard let lhsDict = lhs as? [String: any Sendable],
                  let rhsDict = rhs as? [String: any Sendable],
                  let lhsValue = lhsDict[field],
                  let rhsValue = rhsDict[field] else {
                return false
            }

            // Numeric comparison
            if let lhsNum = lhsValue as? Double ?? (lhsValue as? Int).map(Double.init),
               let rhsNum = rhsValue as? Double ?? (rhsValue as? Int).map(Double.init) {
                return ascending ? lhsNum < rhsNum : lhsNum > rhsNum
            }

            // String comparison
            let lhsStr = String(describing: lhsValue)
            let rhsStr = String(describing: rhsValue)
            return ascending ? lhsStr < rhsStr : lhsStr > rhsStr
        }
    }
}
