// ============================================================
// GreetingService.swift
// Example ARO Plugin - Custom Greeting Service
// ============================================================
//
// This plugin demonstrates the ARO plugin system.
// It provides a "greeting" service with "hello" and "goodbye" methods.
//
// Usage in ARO:
//   <Call> the <result> from the <greeting: hello> with { name: "World" }.
//
// Plugins use a C-compatible JSON interface:
// - Input: method name and args as JSON
// - Output: result as JSON (must be freed by caller)
// - Return: 0 for success, non-zero for error

import Foundation

// MARK: - Plugin Initialization

/// Plugin initialization - returns service metadata as JSON
/// This tells ARO what services and symbols this plugin provides
@_cdecl("aro_plugin_init")
public func pluginInit() -> UnsafePointer<CChar> {
    let metadata = "{\"services\": [{\"name\": \"greeting\", \"symbol\": \"greeting_call\"}]}"
    let cstr = strdup(metadata)!
    return UnsafePointer(cstr)
}

// MARK: - Service Implementation

/// Main entry point for the greeting service
/// - Parameters:
///   - methodPtr: Method name (C string)
///   - argsPtr: Arguments as JSON (C string)
///   - resultPtr: Output - result as JSON (caller must free)
/// - Returns: 0 for success, non-zero for error
@_cdecl("greeting_call")
public func greetingCall(
    _ methodPtr: UnsafePointer<CChar>,
    _ argsPtr: UnsafePointer<CChar>,
    _ resultPtr: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32 {
    let method = String(cString: methodPtr)
    let argsJSON = String(cString: argsPtr)

    // Parse arguments
    var args: [String: Any] = [:]
    if let data = argsJSON.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        args = parsed
    }

    // Execute method
    let result: String
    do {
        result = try executeMethod(method, args: args)
    } catch {
        // Return error message
        let errorJSON = "{\"error\": \"\(error)\"}"
        resultPtr.pointee = errorJSON.withCString { strdup($0) }
        return 1
    }

    // Return success result as JSON
    let resultJSON = "{\"result\": \"\(result)\"}"
    resultPtr.pointee = resultJSON.withCString { strdup($0) }
    return 0
}

/// Execute a greeting method
private func executeMethod(_ method: String, args: [String: Any]) throws -> String {
    let name = args["name"] as? String ?? "World"

    switch method.lowercased() {
    case "hello":
        return "Hello, \(name)!"

    case "goodbye":
        return "Goodbye, \(name)! See you next time."

    case "greet":
        let style = args["style"] as? String ?? "formal"
        switch style {
        case "casual":
            return "Hey \(name)! What's up?"
        case "enthusiastic":
            return "WOW! Great to see you, \(name)!"
        default:
            return "Good day, \(name). How may I assist you?"
        }

    default:
        throw PluginError.unknownMethod(method)
    }
}

/// Plugin-specific errors
enum PluginError: Error, CustomStringConvertible {
    case unknownMethod(String)

    var description: String {
        switch self {
        case .unknownMethod(let method):
            return "Unknown method: \(method)"
        }
    }
}
