// DateService.swift
// ARO Runtime - Date and Time Handling (ARO-0041)

import Foundation

/// Protocol for date/time operations in ARO
///
/// DateService provides a testable abstraction for all date operations.
/// The default implementation uses Foundation's Date and Calendar.
/// Custom implementations can be injected for testing or special requirements.
public protocol DateService: Sendable {
    /// Get the current date/time
    /// - Parameter timezone: Optional timezone (nil = UTC)
    func now(timezone: String?) -> ARODate

    /// Parse an ISO 8601 date string
    func parse(_ iso8601: String) throws -> ARODate

    /// Apply an offset to a date
    func offset(_ date: ARODate, by offset: DateOffset) -> ARODate

    /// Calculate the distance between two dates
    func distance(from: ARODate, to: ARODate) -> DateDistance

    /// Format a date using a pattern string
    func format(_ date: ARODate, pattern: String) -> String

    /// Create a date range
    func createRange(from start: ARODate, to end: ARODate) -> ARODateRange

    /// Create a recurrence pattern
    func createRecurrence(pattern: String, from startDate: ARODate?) throws -> ARORecurrence
}

// MARK: - Default Implementation

/// Default implementation of DateService using Foundation
public struct DefaultDateService: DateService, Sendable {
    public init() {}

    public func now(timezone: String?) -> ARODate {
        let tz = ARODate.parseTimezone(timezone)
        return ARODate(date: Date(), timezone: tz)
    }

    public func parse(_ iso8601: String) throws -> ARODate {
        try ARODate.parse(iso8601)
    }

    public func offset(_ date: ARODate, by offset: DateOffset) -> ARODate {
        offset.apply(to: date)
    }

    public func distance(from: ARODate, to: ARODate) -> DateDistance {
        DateDistance(from: from, to: to)
    }

    public func format(_ date: ARODate, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = date.timezone
        formatter.dateFormat = pattern
        return formatter.string(from: date.date)
    }

    public func createRange(from start: ARODate, to end: ARODate) -> ARODateRange {
        ARODateRange(from: start, to: end)
    }

    public func createRecurrence(pattern: String, from startDate: ARODate?) throws -> ARORecurrence {
        try ARORecurrence(pattern: pattern, from: startDate)
    }
}

// MARK: - Date Formatting Patterns

/// Common date format patterns
public enum DateFormatPattern {
    /// Standard patterns
    public static let iso8601 = "yyyy-MM-dd'T'HH:mm:ssZ"
    public static let iso8601Date = "yyyy-MM-dd"
    public static let iso8601Time = "HH:mm:ss"

    /// Human-readable patterns
    public static let fullDate = "MMMM dd, yyyy"
    public static let shortDate = "MMM dd, yyyy"
    public static let numericDate = "MM/dd/yyyy"
    public static let europeanDate = "dd.MM.yyyy"

    /// Time patterns
    public static let time24h = "HH:mm:ss"
    public static let time12h = "hh:mm:ss a"
    public static let timeShort = "HH:mm"

    /// Combined patterns
    public static let fullDateTime = "MMMM dd, yyyy 'at' HH:mm:ss"
    public static let shortDateTime = "MMM dd, yyyy HH:mm"
}
