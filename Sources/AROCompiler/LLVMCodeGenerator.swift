// ============================================================
// LLVMCodeGenerator.swift
// AROCompiler - LLVM IR Text Code Generation
// ============================================================

import Foundation
import AROParser

/// Result of LLVM code generation
public struct LLVMCodeGenerationResult {
    /// The generated LLVM IR text
    public let irText: String

    /// Path to the emitted file (if applicable)
    public var filePath: String?
}

/// Generates LLVM IR text from an analyzed ARO program
public final class LLVMCodeGenerator {
    // MARK: - Properties

    private var output: String = ""
    private var stringConstants: [String: String] = [:]  // string -> global name
    private var uniqueCounter: Int = 0
    private var openAPISpecJSON: String? = nil

    // MARK: - Initialization

    public init() {}

    // MARK: - Code Generation

    /// Generate LLVM IR for an analyzed program
    /// - Parameters:
    ///   - program: The analyzed ARO program
    ///   - openAPISpecJSON: Optional OpenAPI spec as minified JSON to embed in binary
    /// - Returns: Result containing the LLVM IR text
    public func generate(program: AnalyzedProgram, openAPISpecJSON: String? = nil) throws -> LLVMCodeGenerationResult {
        output = ""
        stringConstants = [:]
        uniqueCounter = 0
        self.openAPISpecJSON = openAPISpecJSON

        // Emit module header
        emitModuleHeader()

        // Emit type definitions
        emitTypeDefinitions()

        // Emit external function declarations
        emitExternalDeclarations()

        // Collect all string constants first
        collectStringConstants(program)

        // Emit string constants
        emitStringConstants()

        // Generate feature set functions
        for featureSet in program.featureSets {
            try generateFeatureSet(featureSet)
        }

        // Generate main function
        try generateMain(program: program)

        return LLVMCodeGenerationResult(irText: output)
    }

    // MARK: - Header Generation

    private func emitModuleHeader() {
        emit("; ModuleID = 'aro_program'")
        emit("source_filename = \"aro_program.ll\"")
        emit("target datalayout = \"e-m:o-i64:64-i128:128-n32:64-S128\"")
        #if arch(arm64)
        emit("target triple = \"arm64-apple-macosx14.0.0\"")
        #else
        emit("target triple = \"x86_64-apple-macosx14.0.0\"")
        #endif
        emit("")
    }

    private func emitTypeDefinitions() {
        emit("; Type definitions")
        emit("; AROResultDescriptor: { i8*, i8**, i32 }")
        emit("%AROResultDescriptor = type { ptr, ptr, i32 }")
        emit("")
        emit("; AROObjectDescriptor: { i8*, i32, i8**, i32 }")
        emit("%AROObjectDescriptor = type { ptr, i32, ptr, i32 }")
        emit("")
    }

    private func emitExternalDeclarations() {
        emit("; External runtime function declarations")
        emit("")

        // Runtime lifecycle
        emit("; Runtime lifecycle")
        emit("declare ptr @aro_runtime_init()")
        emit("declare void @aro_runtime_shutdown(ptr)")
        emit("declare ptr @aro_context_create(ptr)")
        emit("declare ptr @aro_context_create_named(ptr, ptr)")
        emit("declare void @aro_context_destroy(ptr)")
        emit("declare i32 @aro_load_precompiled_plugins()")
        emit("")

        // Variable operations
        emit("; Variable operations")
        emit("declare void @aro_variable_bind_string(ptr, ptr, ptr)")
        emit("declare void @aro_variable_bind_int(ptr, ptr, i64)")
        emit("declare void @aro_variable_bind_double(ptr, ptr, double)")
        emit("declare void @aro_variable_bind_bool(ptr, ptr, i32)")
        emit("declare void @aro_variable_bind_dict(ptr, ptr, ptr)")
        emit("declare void @aro_variable_bind_array(ptr, ptr, ptr)")
        emit("declare ptr @aro_variable_resolve(ptr, ptr)")
        emit("declare void @aro_copy_value_to_expression(ptr, ptr)")
        emit("declare ptr @aro_variable_resolve_string(ptr, ptr)")
        emit("declare i32 @aro_variable_resolve_int(ptr, ptr, ptr)")
        emit("declare void @aro_value_free(ptr)")
        emit("declare ptr @aro_value_as_string(ptr)")
        emit("declare i32 @aro_value_as_int(ptr, ptr)")
        emit("declare void @aro_evaluate_expression(ptr, ptr)")
        emit("")

        // All action functions
        emit("; Action functions")
        let actions = [
            "extract", "fetch", "retrieve", "parse", "read",
            "compute", "validate", "compare", "transform", "create", "update",
            "return", "throw", "emit", "send", "log", "store", "write", "publish",
            "start", "listen", "route", "watch", "stop", "keepalive",
            "call",
            // Data pipeline actions (ARO-0018)
            "filter", "reduce", "map"
        ]
        for action in actions {
            emit("declare ptr @aro_action_\(action)(ptr, ptr, ptr)")
        }
        emit("")

        // HTTP operations
        emit("; HTTP operations")
        emit("declare ptr @aro_http_server_create(ptr)")
        emit("declare i32 @aro_http_server_start(ptr, ptr, i32)")
        emit("declare void @aro_http_server_stop(ptr)")
        emit("declare void @aro_http_server_destroy(ptr)")
        emit("")

        // File operations
        emit("; File operations")
        emit("declare ptr @aro_file_read(ptr, ptr)")
        emit("declare i32 @aro_file_write(ptr, ptr)")
        emit("declare i32 @aro_file_exists(ptr)")
        emit("declare i32 @aro_file_delete(ptr)")
        emit("")

        // Standard C library functions
        emit("; Standard C library")
        emit("declare i32 @strcmp(ptr, ptr)")
        emit("")

        // OpenAPI embedding
        emit("; OpenAPI spec embedding")
        emit("declare void @aro_set_embedded_openapi(ptr)")
        emit("")
    }

    // MARK: - String Constants

    private func collectStringConstants(_ program: AnalyzedProgram) {
        // Collect all strings used in the program
        for featureSet in program.featureSets {
            registerString(featureSet.featureSet.name)
            registerString(featureSet.featureSet.businessActivity)

            for statement in featureSet.featureSet.statements {
                collectStringsFromStatement(statement)
            }
        }

        // Always register these strings for main
        registerString("Application-Start")
        registerString("_literal_")
        registerString("_expression_")

        // Register OpenAPI spec JSON if provided (for embedded spec)
        if let specJSON = openAPISpecJSON {
            registerString(specJSON)
        }
    }

    private func collectStringsFromStatement(_ statement: Statement) {
        if let aroStatement = statement as? AROStatement {
            registerString(aroStatement.result.base)
            for spec in aroStatement.result.specifiers {
                registerString(spec)
            }

            registerString(aroStatement.object.noun.base)
            for spec in aroStatement.object.noun.specifiers {
                registerString(spec)
            }

            if let literal = aroStatement.literalValue {
                collectStringsFromLiteral(literal)
            }

            // Collect strings from expressions (ARO-0002)
            if let expression = aroStatement.expression {
                collectStringsFromExpression(expression)
            }
        } else if let publishStatement = statement as? PublishStatement {
            registerString(publishStatement.externalName)
            registerString(publishStatement.internalVariable)
        } else if let matchStatement = statement as? MatchStatement {
            registerString(matchStatement.subject.base)
            for caseClause in matchStatement.cases {
                if case .literal(let literalValue) = caseClause.pattern {
                    if case .string(let s) = literalValue {
                        registerString(s)
                    }
                }
                for bodyStatement in caseClause.body {
                    collectStringsFromStatement(bodyStatement)
                }
            }
            if let otherwiseBody = matchStatement.otherwise {
                for bodyStatement in otherwiseBody {
                    collectStringsFromStatement(bodyStatement)
                }
            }
        }
    }

    private func collectStringsFromExpression(_ expression: any AROParser.Expression) {
        if let literalExpr = expression as? LiteralExpression {
            collectStringsFromLiteral(literalExpr.value)
        } else if let varRefExpr = expression as? VariableRefExpression {
            // Register variable name for runtime resolution
            registerString(varRefExpr.noun.base)
        } else if let mapExpr = expression as? MapLiteralExpression {
            // Register JSON representation of the map
            let jsonString = mapExpressionToJSON(mapExpr)
            registerString(jsonString)
            // Also register nested strings from entries
            for entry in mapExpr.entries {
                registerString(entry.key)
                collectStringsFromExpression(entry.value)
            }
        } else if let arrayExpr = expression as? ArrayLiteralExpression {
            // Register JSON representation of the array
            let jsonString = arrayExpressionToJSON(arrayExpr)
            registerString(jsonString)
            // Also register nested strings from elements
            for element in arrayExpr.elements {
                collectStringsFromExpression(element)
            }
        } else if let binaryExpr = expression as? BinaryExpression {
            // Register the JSON representation for runtime evaluation
            let jsonString = binaryExpressionToJSON(binaryExpr)
            registerString(jsonString)
            // Also collect strings from operands
            collectStringsFromExpression(binaryExpr.left)
            collectStringsFromExpression(binaryExpr.right)
        } else if let groupedExpr = expression as? GroupedExpression {
            collectStringsFromExpression(groupedExpr.expression)
        }
    }

    /// Convert a MapLiteralExpression to JSON string
    private func mapExpressionToJSON(_ mapExpr: MapLiteralExpression) -> String {
        let pairs = mapExpr.entries.map { entry in
            let keyEscaped = entry.key.replacingOccurrences(of: "\"", with: "\\\"")
            let valueJSON = expressionToJSON(entry.value)
            return "\"\(keyEscaped)\":\(valueJSON)"
        }
        return "{\(pairs.joined(separator: ","))}"
    }

    /// Convert an ArrayLiteralExpression to JSON string
    private func arrayExpressionToJSON(_ arrayExpr: ArrayLiteralExpression) -> String {
        let items = arrayExpr.elements.map { expressionToJSON($0) }
        return "[\(items.joined(separator: ","))]"
    }

    /// Convert a BinaryExpression to JSON string for runtime evaluation
    /// Format: {"$binary":{"op":"*","left":{...},"right":{...}}}
    private func binaryExpressionToJSON(_ binaryExpr: BinaryExpression) -> String {
        let opStr = binaryExpr.op.rawValue.replacingOccurrences(of: "\"", with: "\\\"")
        let leftJSON = expressionToEvalJSON(binaryExpr.left)
        let rightJSON = expressionToEvalJSON(binaryExpr.right)
        return "{\"$binary\":{\"op\":\"\(opStr)\",\"left\":\(leftJSON),\"right\":\(rightJSON)}}"
    }

    /// Convert any Expression to evaluation JSON format
    /// Format for values: {"$lit": value} or {"$var": "name"} or {"$binary": {...}}
    private func expressionToEvalJSON(_ expr: any AROParser.Expression) -> String {
        if let literalExpr = expr as? LiteralExpression {
            return "{\"$lit\":\(literalToJSON(literalExpr.value))}"
        } else if let varRefExpr = expr as? VariableRefExpression {
            let escaped = varRefExpr.noun.base.replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"$var\":\"\(escaped)\"}"
        } else if let binaryExpr = expr as? BinaryExpression {
            return binaryExpressionToJSON(binaryExpr)
        } else if let groupedExpr = expr as? GroupedExpression {
            return expressionToEvalJSON(groupedExpr.expression)
        } else {
            // Fallback: treat as string literal
            let escaped = expr.description.replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"$lit\":\"\(escaped)\"}"
        }
    }

    /// Convert any Expression to JSON string (for nested values)
    private func expressionToJSON(_ expr: any AROParser.Expression) -> String {
        if let literalExpr = expr as? LiteralExpression {
            return literalToJSON(literalExpr.value)
        } else if let varRefExpr = expr as? VariableRefExpression {
            // Variable reference: use $ref: prefix so runtime can resolve it
            let escaped = varRefExpr.noun.base.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"$ref:\(escaped)\""
        } else if let mapExpr = expr as? MapLiteralExpression {
            return mapExpressionToJSON(mapExpr)
        } else if let arrayExpr = expr as? ArrayLiteralExpression {
            return arrayExpressionToJSON(arrayExpr)
        } else {
            // Fallback: use description as string
            let escaped = expr.description.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
    }

    private func collectStringsFromLiteral(_ literal: LiteralValue) {
        switch literal {
        case .string(let s):
            registerString(s)
        case .object(let pairs):
            // Register JSON representation
            let jsonString = literalToJSON(literal)
            registerString(jsonString)
            // Also register nested strings
            for (key, value) in pairs {
                registerString(key)
                collectStringsFromLiteral(value)
            }
        case .array(let items):
            // Register JSON representation
            let jsonString = literalToJSON(literal)
            registerString(jsonString)
            // Also register nested strings
            for item in items {
                collectStringsFromLiteral(item)
            }
        default:
            break
        }
    }

    /// Convert a LiteralValue to its JSON string representation
    private func literalToJSON(_ literal: LiteralValue) -> String {
        switch literal {
        case .string(let s):
            // Escape special characters for JSON
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        case .integer(let i):
            return String(i)
        case .float(let f):
            return String(f)
        case .boolean(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .array(let items):
            let itemsJson = items.map { literalToJSON($0) }.joined(separator: ",")
            return "[\(itemsJson)]"
        case .object(let pairs):
            let pairsJson = pairs.map { key, value in
                "\"\(key)\":\(literalToJSON(value))"
            }.joined(separator: ",")
            return "{\(pairsJson)}"
        }
    }

    private func registerString(_ str: String) {
        guard stringConstants[str] == nil else { return }
        let name = "@.str.\(uniqueCounter)"
        uniqueCounter += 1
        stringConstants[str] = name
    }

    private func emitStringConstants() {
        emit("; String constants")
        for (str, name) in stringConstants.sorted(by: { $0.value < $1.value }) {
            let escaped = escapeStringForLLVM(str)
            let length = str.utf8.count + 1  // +1 for null terminator
            emit("\(name) = private unnamed_addr constant [\(length) x i8] c\"\(escaped)\\00\"")
        }
        emit("")
    }

    private func stringConstantRef(_ str: String) -> String {
        guard let name = stringConstants[str] else {
            fatalError("String not registered: \(str)")
        }
        let length = str.utf8.count + 1
        return "ptr \(name)"
    }

    // MARK: - Feature Set Generation

    private func generateFeatureSet(_ featureSet: AnalyzedFeatureSet) throws {
        let funcName = mangleFeatureSetName(featureSet.featureSet.name)

        emit("; Feature Set: \(featureSet.featureSet.name)")
        emit("; Business Activity: \(featureSet.featureSet.businessActivity)")
        emit("define ptr @\(funcName)(ptr %ctx) {")
        emit("entry:")

        // Create local result variable
        emit("  %__result = alloca ptr")
        emit("  store ptr null, ptr %__result")
        emit("")

        // Generate each statement
        for (index, statement) in featureSet.featureSet.statements.enumerated() {
            try generateStatement(statement, index: index)
        }

        // Return the result
        emit("  %final_result = load ptr, ptr %__result")
        emit("  ret ptr %final_result")
        emit("}")
        emit("")
    }

    private func generateStatement(_ statement: Statement, index: Int) throws {
        if let aroStatement = statement as? AROStatement {
            try generateAROStatement(aroStatement, index: index)
        } else if let publishStatement = statement as? PublishStatement {
            try generatePublishStatement(publishStatement, index: index)
        } else if let matchStatement = statement as? MatchStatement {
            try generateMatchStatement(matchStatement, index: index)
        }
    }

    // MARK: - ARO Statement Generation

    private func generateAROStatement(_ statement: AROStatement, index: Int) throws {
        let prefix = "s\(index)"

        emit("  ; <\(statement.action.verb)> the <\(statement.result.base)> ...")

        // If there's a literal value, bind it first
        if let literalValue = statement.literalValue {
            try emitLiteralBinding(literalValue, prefix: prefix)
        }

        // If there's an expression (ARO-0002), bind it to _expression_
        if let expression = statement.expression {
            try emitExpressionBinding(expression, prefix: prefix)
        }

        // Allocate result descriptor
        emit("  %\(prefix)_result_desc = alloca %AROResultDescriptor")

        // Store result base name
        let resultBaseStr = stringConstants[statement.result.base]!
        emit("  %\(prefix)_rd_base_ptr = getelementptr inbounds %AROResultDescriptor, ptr %\(prefix)_result_desc, i32 0, i32 0")
        emit("  store ptr \(resultBaseStr), ptr %\(prefix)_rd_base_ptr")

        // Store result specifiers
        emit("  %\(prefix)_rd_specs_ptr = getelementptr inbounds %AROResultDescriptor, ptr %\(prefix)_result_desc, i32 0, i32 1")
        if statement.result.specifiers.isEmpty {
            emit("  store ptr null, ptr %\(prefix)_rd_specs_ptr")
        } else {
            // Allocate array for specifiers
            let count = statement.result.specifiers.count
            emit("  %\(prefix)_rd_specs_arr = alloca [\(count) x ptr]")
            for (i, spec) in statement.result.specifiers.enumerated() {
                let specStr = stringConstants[spec]!
                emit("  %\(prefix)_rd_spec_\(i)_ptr = getelementptr inbounds [\(count) x ptr], ptr %\(prefix)_rd_specs_arr, i32 0, i32 \(i)")
                emit("  store ptr \(specStr), ptr %\(prefix)_rd_spec_\(i)_ptr")
            }
            emit("  store ptr %\(prefix)_rd_specs_arr, ptr %\(prefix)_rd_specs_ptr")
        }

        // Store result specifier count
        emit("  %\(prefix)_rd_count_ptr = getelementptr inbounds %AROResultDescriptor, ptr %\(prefix)_result_desc, i32 0, i32 2")
        emit("  store i32 \(statement.result.specifiers.count), ptr %\(prefix)_rd_count_ptr")

        // Allocate object descriptor
        emit("  %\(prefix)_object_desc = alloca %AROObjectDescriptor")

        // Store object base name
        let objectBaseStr = stringConstants[statement.object.noun.base]!
        emit("  %\(prefix)_od_base_ptr = getelementptr inbounds %AROObjectDescriptor, ptr %\(prefix)_object_desc, i32 0, i32 0")
        emit("  store ptr \(objectBaseStr), ptr %\(prefix)_od_base_ptr")

        // Store preposition
        let prepValue = prepositionToInt(statement.object.preposition)
        emit("  %\(prefix)_od_prep_ptr = getelementptr inbounds %AROObjectDescriptor, ptr %\(prefix)_object_desc, i32 0, i32 1")
        emit("  store i32 \(prepValue), ptr %\(prefix)_od_prep_ptr")

        // Store object specifiers
        emit("  %\(prefix)_od_specs_ptr = getelementptr inbounds %AROObjectDescriptor, ptr %\(prefix)_object_desc, i32 0, i32 2")
        if statement.object.noun.specifiers.isEmpty {
            emit("  store ptr null, ptr %\(prefix)_od_specs_ptr")
        } else {
            let count = statement.object.noun.specifiers.count
            emit("  %\(prefix)_od_specs_arr = alloca [\(count) x ptr]")
            for (i, spec) in statement.object.noun.specifiers.enumerated() {
                let specStr = stringConstants[spec]!
                emit("  %\(prefix)_od_spec_\(i)_ptr = getelementptr inbounds [\(count) x ptr], ptr %\(prefix)_od_specs_arr, i32 0, i32 \(i)")
                emit("  store ptr \(specStr), ptr %\(prefix)_od_spec_\(i)_ptr")
            }
            emit("  store ptr %\(prefix)_od_specs_arr, ptr %\(prefix)_od_specs_ptr")
        }

        // Store object specifier count
        emit("  %\(prefix)_od_count_ptr = getelementptr inbounds %AROObjectDescriptor, ptr %\(prefix)_object_desc, i32 0, i32 3")
        emit("  store i32 \(statement.object.noun.specifiers.count), ptr %\(prefix)_od_count_ptr")

        // Call the action function
        let actionName = canonicalizeVerb(statement.action.verb.lowercased())
        emit("  %\(prefix)_action_result = call ptr @aro_action_\(actionName)(ptr %ctx, ptr %\(prefix)_result_desc, ptr %\(prefix)_object_desc)")

        // Store result
        emit("  store ptr %\(prefix)_action_result, ptr %__result")
        emit("")
    }

    private func emitLiteralBinding(_ literal: LiteralValue, prefix: String) throws {
        let literalNameStr = stringConstants["_literal_"]!

        switch literal {
        case .string(let s):
            let strConst = stringConstants[s]!
            emit("  call void @aro_variable_bind_string(ptr %ctx, ptr \(literalNameStr), ptr \(strConst))")

        case .integer(let i):
            emit("  call void @aro_variable_bind_int(ptr %ctx, ptr \(literalNameStr), i64 \(i))")

        case .float(let f):
            // Format double as hex for exact representation
            let bits = f.bitPattern
            emit("  call void @aro_variable_bind_double(ptr %ctx, ptr \(literalNameStr), double 0x\(String(bits, radix: 16, uppercase: true)))")

        case .boolean(let b):
            emit("  call void @aro_variable_bind_bool(ptr %ctx, ptr \(literalNameStr), i32 \(b ? 1 : 0))")

        case .null:
            // No binding needed
            break

        case .array:
            // Bind array as JSON string
            let jsonString = literalToJSON(literal)
            let jsonConst = stringConstants[jsonString]!
            emit("  call void @aro_variable_bind_array(ptr %ctx, ptr \(literalNameStr), ptr \(jsonConst))")

        case .object:
            // Bind object as JSON string
            let jsonString = literalToJSON(literal)
            let jsonConst = stringConstants[jsonString]!
            emit("  call void @aro_variable_bind_dict(ptr %ctx, ptr \(literalNameStr), ptr \(jsonConst))")
        }
    }

    private func emitExpressionBinding(_ expression: any AROParser.Expression, prefix: String) throws {
        let exprNameStr = stringConstants["_expression_"]!

        // Handle literal expressions (most common case for "with" clause)
        if let literalExpr = expression as? LiteralExpression {
            switch literalExpr.value {
            case .string(let s):
                let strConst = stringConstants[s]!
                emit("  call void @aro_variable_bind_string(ptr %ctx, ptr \(exprNameStr), ptr \(strConst))")

            case .integer(let i):
                emit("  call void @aro_variable_bind_int(ptr %ctx, ptr \(exprNameStr), i64 \(i))")

            case .float(let f):
                let bits = f.bitPattern
                emit("  call void @aro_variable_bind_double(ptr %ctx, ptr \(exprNameStr), double 0x\(String(bits, radix: 16, uppercase: true)))")

            case .boolean(let b):
                emit("  call void @aro_variable_bind_bool(ptr %ctx, ptr \(exprNameStr), i32 \(b ? 1 : 0))")

            case .null:
                break

            case .array:
                // Bind array as JSON string
                let jsonString = literalToJSON(literalExpr.value)
                let jsonConst = stringConstants[jsonString]!
                emit("  call void @aro_variable_bind_array(ptr %ctx, ptr \(exprNameStr), ptr \(jsonConst))")

            case .object:
                // Bind object as JSON string
                let jsonString = literalToJSON(literalExpr.value)
                let jsonConst = stringConstants[jsonString]!
                emit("  call void @aro_variable_bind_dict(ptr %ctx, ptr \(exprNameStr), ptr \(jsonConst))")
            }
        } else if let varRefExpr = expression as? VariableRefExpression {
            // Variable reference expression: <user>, <user: id>, etc.
            // Resolve the variable and copy its value to _expression_
            let varName = varRefExpr.noun.base
            let varNameStr = stringConstants[varName]!

            emit("  ; Resolve variable reference <\(varName)> for expression binding")
            emit("  %\(prefix)_varref = call ptr @aro_variable_resolve(ptr %ctx, ptr \(varNameStr))")
            emit("  call void @aro_copy_value_to_expression(ptr %ctx, ptr %\(prefix)_varref)")
        } else if let mapExpr = expression as? MapLiteralExpression {
            // Map literal expression: { key: value, ... }
            // Bind as JSON string and let runtime parse it
            let jsonString = mapExpressionToJSON(mapExpr)
            let jsonConst = stringConstants[jsonString]!
            emit("  ; Bind map expression as JSON")
            emit("  call void @aro_variable_bind_dict(ptr %ctx, ptr \(exprNameStr), ptr \(jsonConst))")
        } else if let arrayExpr = expression as? ArrayLiteralExpression {
            // Array literal expression: [elem1, elem2, ...]
            // Bind as JSON string and let runtime parse it
            let jsonString = arrayExpressionToJSON(arrayExpr)
            let jsonConst = stringConstants[jsonString]!
            emit("  ; Bind array expression as JSON")
            emit("  call void @aro_variable_bind_array(ptr %ctx, ptr \(exprNameStr), ptr \(jsonConst))")
        } else if let binaryExpr = expression as? BinaryExpression {
            // Binary expression: <a> + <b>, <x> * <y>, <s> ++ <t>, etc.
            // Serialize to JSON and evaluate at runtime
            let jsonString = binaryExpressionToJSON(binaryExpr)
            let jsonConst = stringConstants[jsonString]!
            emit("  ; Evaluate binary expression at runtime")
            emit("  call void @aro_evaluate_expression(ptr %ctx, ptr \(jsonConst))")
        } else if let groupedExpr = expression as? GroupedExpression {
            // Grouped expression: (expr) - evaluate the inner expression
            try emitExpressionBinding(groupedExpr.expression, prefix: prefix)
        }
    }

    private func generatePublishStatement(_ statement: PublishStatement, index: Int) throws {
        let prefix = "p\(index)"

        emit("  ; Publish <\(statement.externalName)> as <\(statement.internalVariable)>")

        // Allocate result descriptor for external name
        emit("  %\(prefix)_result_desc = alloca %AROResultDescriptor")

        let extNameStr = stringConstants[statement.externalName]!
        emit("  %\(prefix)_rd_base_ptr = getelementptr inbounds %AROResultDescriptor, ptr %\(prefix)_result_desc, i32 0, i32 0")
        emit("  store ptr \(extNameStr), ptr %\(prefix)_rd_base_ptr")

        emit("  %\(prefix)_rd_specs_ptr = getelementptr inbounds %AROResultDescriptor, ptr %\(prefix)_result_desc, i32 0, i32 1")
        emit("  store ptr null, ptr %\(prefix)_rd_specs_ptr")

        emit("  %\(prefix)_rd_count_ptr = getelementptr inbounds %AROResultDescriptor, ptr %\(prefix)_result_desc, i32 0, i32 2")
        emit("  store i32 0, ptr %\(prefix)_rd_count_ptr")

        // Allocate object descriptor for internal variable
        emit("  %\(prefix)_object_desc = alloca %AROObjectDescriptor")

        let intNameStr = stringConstants[statement.internalVariable]!
        emit("  %\(prefix)_od_base_ptr = getelementptr inbounds %AROObjectDescriptor, ptr %\(prefix)_object_desc, i32 0, i32 0")
        emit("  store ptr \(intNameStr), ptr %\(prefix)_od_base_ptr")

        emit("  %\(prefix)_od_prep_ptr = getelementptr inbounds %AROObjectDescriptor, ptr %\(prefix)_object_desc, i32 0, i32 1")
        emit("  store i32 3, ptr %\(prefix)_od_prep_ptr")  // 3 = .with

        emit("  %\(prefix)_od_specs_ptr = getelementptr inbounds %AROObjectDescriptor, ptr %\(prefix)_object_desc, i32 0, i32 2")
        emit("  store ptr null, ptr %\(prefix)_od_specs_ptr")

        emit("  %\(prefix)_od_count_ptr = getelementptr inbounds %AROObjectDescriptor, ptr %\(prefix)_object_desc, i32 0, i32 3")
        emit("  store i32 0, ptr %\(prefix)_od_count_ptr")

        // Call publish action
        emit("  %\(prefix)_result = call ptr @aro_action_publish(ptr %ctx, ptr %\(prefix)_result_desc, ptr %\(prefix)_object_desc)")
        emit("  store ptr %\(prefix)_result, ptr %__result")
        emit("")
    }

    // MARK: - Match Statement Generation (ARO-0004)

    private func generateMatchStatement(_ statement: MatchStatement, index: Int) throws {
        let prefix = "m\(index)"
        let subjectName = statement.subject.base

        emit("  ; match <\(subjectName)>")

        // Resolve the subject value
        let subjectStr = stringConstants[subjectName]!
        emit("  %\(prefix)_subject_val = call ptr @aro_variable_resolve(ptr %ctx, ptr \(subjectStr))")
        emit("  %\(prefix)_subject_str = call ptr @aro_value_as_string(ptr %\(prefix)_subject_val)")

        // Generate labels for each case and the end
        let caseLabels = statement.cases.enumerated().map { "\(prefix)_case\($0.offset)" }
        let otherwiseLabel = "\(prefix)_otherwise"
        let endLabel = "\(prefix)_end"

        // Jump to first case
        if !statement.cases.isEmpty {
            emit("  br label %\(caseLabels[0])_check")
        } else if statement.otherwise != nil {
            emit("  br label %\(otherwiseLabel)")
        } else {
            emit("  br label %\(endLabel)")
        }
        emit("")

        // Generate each case
        for (caseIndex, caseClause) in statement.cases.enumerated() {
            let caseLabel = caseLabels[caseIndex]
            let nextLabel = caseIndex + 1 < statement.cases.count ?
                "\(caseLabels[caseIndex + 1])_check" :
                (statement.otherwise != nil ? otherwiseLabel : endLabel)

            // Case check block
            emit("\(caseLabel)_check:")

            switch caseClause.pattern {
            case .literal(let literalValue):
                switch literalValue {
                case .string(let s):
                    let patternStr = stringConstants[s]!
                    emit("  %\(caseLabel)_cmp = call i32 @strcmp(ptr %\(prefix)_subject_str, ptr \(patternStr))")
                    emit("  %\(caseLabel)_match = icmp eq i32 %\(caseLabel)_cmp, 0")
                case .integer(let i):
                    emit("  %\(caseLabel)_int_ptr = alloca i64")
                    emit("  %\(caseLabel)_int_ok = call i32 @aro_value_as_int(ptr %\(prefix)_subject_val, ptr %\(caseLabel)_int_ptr)")
                    emit("  %\(caseLabel)_int_val = load i64, ptr %\(caseLabel)_int_ptr")
                    emit("  %\(caseLabel)_match = icmp eq i64 %\(caseLabel)_int_val, \(i)")
                default:
                    // For other patterns, just skip to next
                    emit("  %\(caseLabel)_match = icmp eq i32 0, 1")  // Always false
                }
            case .wildcard:
                emit("  %\(caseLabel)_match = icmp eq i32 1, 1")  // Always true
            case .variable:
                emit("  %\(caseLabel)_match = icmp eq i32 0, 1")  // TODO: variable comparison
            }

            emit("  br i1 %\(caseLabel)_match, label %\(caseLabel)_body, label %\(nextLabel)")
            emit("")

            // Case body block
            emit("\(caseLabel)_body:")
            for (bodyIndex, bodyStatement) in caseClause.body.enumerated() {
                try generateStatement(bodyStatement, index: index * 100 + caseIndex * 10 + bodyIndex)
            }
            emit("  br label %\(endLabel)")
            emit("")
        }

        // Otherwise block
        if let otherwiseBody = statement.otherwise {
            emit("\(otherwiseLabel):")
            for (bodyIndex, bodyStatement) in otherwiseBody.enumerated() {
                try generateStatement(bodyStatement, index: index * 100 + 90 + bodyIndex)
            }
            emit("  br label %\(endLabel)")
            emit("")
        }

        // End block
        emit("\(endLabel):")
    }

    // MARK: - Main Function Generation

    private func generateMain(program: AnalyzedProgram) throws {
        // Verify Application-Start exists
        guard program.featureSets.contains(where: { $0.featureSet.name == "Application-Start" }) else {
            throw LLVMCodeGeneratorError.noEntryPoint
        }

        let entryFuncName = mangleFeatureSetName("Application-Start")
        let appStartStr = stringConstants["Application-Start"]!

        emit("; Main entry point")
        emit("define i32 @main(i32 %argc, ptr %argv) {")
        emit("entry:")

        // Initialize runtime
        emit("  %runtime = call ptr @aro_runtime_init()")

        // Check runtime initialization
        emit("  %runtime_null = icmp eq ptr %runtime, null")
        emit("  br i1 %runtime_null, label %runtime_fail, label %runtime_ok")
        emit("")

        emit("runtime_fail:")
        emit("  ret i32 1")
        emit("")

        emit("runtime_ok:")
        // Set embedded OpenAPI spec if available
        if let specJSON = openAPISpecJSON {
            let specStr = stringConstants[specJSON]!
            emit("  ; Set embedded OpenAPI spec")
            emit("  call void @aro_set_embedded_openapi(ptr \(specStr))")
            emit("")
        }

        // Load pre-compiled plugins from the binary's directory
        emit("  %plugin_result = call i32 @aro_load_precompiled_plugins()")
        emit("")
        // Create named context
        emit("  %ctx = call ptr @aro_context_create_named(ptr %runtime, ptr \(appStartStr))")

        // Check context creation
        emit("  %ctx_null = icmp eq ptr %ctx, null")
        emit("  br i1 %ctx_null, label %ctx_fail, label %ctx_ok")
        emit("")

        emit("ctx_fail:")
        emit("  call void @aro_runtime_shutdown(ptr %runtime)")
        emit("  ret i32 1")
        emit("")

        emit("ctx_ok:")
        // Execute Application-Start
        emit("  %result = call ptr @\(entryFuncName)(ptr %ctx)")

        // Check if result needs to be freed
        emit("  %result_null = icmp eq ptr %result, null")
        emit("  br i1 %result_null, label %cleanup, label %free_result")
        emit("")

        emit("free_result:")
        emit("  call void @aro_value_free(ptr %result)")
        emit("  br label %cleanup")
        emit("")

        emit("cleanup:")
        emit("  call void @aro_context_destroy(ptr %ctx)")
        emit("  call void @aro_runtime_shutdown(ptr %runtime)")
        emit("  ret i32 0")
        emit("}")
    }

    // MARK: - Helper Methods

    private func emit(_ line: String) {
        output += line + "\n"
    }

    private func mangleFeatureSetName(_ name: String) -> String {
        return "aro_fs_" + name
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
    }

    private func canonicalizeVerb(_ verb: String) -> String {
        let mapping: [String: String] = [
            "calculate": "compute", "derive": "compute",
            "verify": "validate", "check": "validate",
            "match": "compare",
            "convert": "transform", "map": "transform",
            "make": "create", "build": "create", "construct": "create",
            "modify": "update", "change": "update", "set": "update",
            "respond": "return",
            "raise": "throw", "fail": "throw",
            "dispatch": "send",
            "print": "log", "output": "log", "debug": "log",
            "save": "store", "persist": "store",
            "export": "publish", "expose": "publish", "share": "publish",
            "initialize": "start", "boot": "start",
            "await": "listen", "wait": "listen",
            "forward": "route",
            "monitor": "watch", "observe": "watch"
        ]
        return mapping[verb] ?? verb
    }

    private func prepositionToInt(_ preposition: Preposition) -> Int {
        switch preposition {
        case .from: return 1
        case .for: return 2
        case .with: return 3
        case .to: return 4
        case .into: return 5
        case .via: return 6
        case .against: return 7
        case .on: return 8
        }
    }

    private func escapeStringForLLVM(_ str: String) -> String {
        var result = ""
        for char in str.utf8 {
            switch char {
            case 0x00...0x1F, 0x7F...0xFF, 0x22, 0x5C:
                // Control chars, DEL, extended ASCII, quote, backslash
                result += String(format: "\\%02X", char)
            default:
                result += String(Character(UnicodeScalar(char)))
            }
        }
        return result
    }
}

// MARK: - Code Generator Errors

public enum LLVMCodeGeneratorError: Error, CustomStringConvertible {
    case noEntryPoint
    case unsupportedAction(String)
    case invalidType(String)
    case compilationFailed(String)

    public var description: String {
        switch self {
        case .noEntryPoint:
            return "No Application-Start feature set found"
        case .unsupportedAction(let verb):
            return "Unsupported action verb: \(verb)"
        case .invalidType(let type):
            return "Invalid type: \(type)"
        case .compilationFailed(let message):
            return "Compilation failed: \(message)"
        }
    }
}
