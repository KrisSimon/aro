// ============================================================
// SemanticAnalyzer.swift
// ARO Parser - Semantic Analysis
// ============================================================

import Foundation

// MARK: - Data Flow Info

/// Information about data flow in a statement
public struct DataFlowInfo: Sendable, Equatable, CustomStringConvertible {
    public let inputs: Set<String>      // Variables consumed
    public let outputs: Set<String>     // Variables produced
    public let sideEffects: [String]    // External effects
    
    public init(inputs: Set<String> = [], outputs: Set<String> = [], sideEffects: [String] = []) {
        self.inputs = inputs
        self.outputs = outputs
        self.sideEffects = sideEffects
    }
    
    public var description: String {
        "DataFlow(in: \(inputs), out: \(outputs), effects: \(sideEffects))"
    }
}

// MARK: - Analyzed Feature Set

/// A feature set with semantic annotations
public struct AnalyzedFeatureSet: Sendable {
    public let featureSet: FeatureSet
    public let symbolTable: SymbolTable
    public let dataFlows: [DataFlowInfo]
    public let dependencies: Set<String>    // External dependencies
    public let exports: Set<String>         // Published symbols
    
    public init(
        featureSet: FeatureSet,
        symbolTable: SymbolTable,
        dataFlows: [DataFlowInfo],
        dependencies: Set<String>,
        exports: Set<String>
    ) {
        self.featureSet = featureSet
        self.symbolTable = symbolTable
        self.dataFlows = dataFlows
        self.dependencies = dependencies
        self.exports = exports
    }
}

// MARK: - Analyzed Program

/// A fully analyzed program
public struct AnalyzedProgram: Sendable {
    public let program: Program
    public let featureSets: [AnalyzedFeatureSet]
    public let globalRegistry: GlobalSymbolRegistry
    
    public init(program: Program, featureSets: [AnalyzedFeatureSet], globalRegistry: GlobalSymbolRegistry) {
        self.program = program
        self.featureSets = featureSets
        self.globalRegistry = globalRegistry
    }
}

// MARK: - Semantic Analyzer

/// Performs semantic analysis on the AST
public final class SemanticAnalyzer {
    
    // MARK: - Properties
    
    private let diagnostics: DiagnosticCollector
    private let globalRegistry: GlobalSymbolRegistry
    
    // MARK: - Initialization
    
    public init(diagnostics: DiagnosticCollector = DiagnosticCollector()) {
        self.diagnostics = diagnostics
        self.globalRegistry = GlobalSymbolRegistry()
    }
    
    // MARK: - Public Interface
    
    /// Analyzes the entire program
    public func analyze(_ program: Program) -> AnalyzedProgram {
        var analyzedSets: [AnalyzedFeatureSet] = []
        
        for featureSet in program.featureSets {
            let analyzed = analyzeFeatureSet(featureSet)
            analyzedSets.append(analyzed)
            
            // Register published symbols
            for symbol in analyzed.symbolTable.publishedSymbols.values {
                globalRegistry.register(symbol: symbol, fromFeatureSet: featureSet.name)
            }
        }
        
        // Second pass: verify external dependencies
        for analyzed in analyzedSets {
            verifyDependencies(analyzed)
        }
        
        return AnalyzedProgram(
            program: program,
            featureSets: analyzedSets,
            globalRegistry: globalRegistry
        )
    }
    
    // MARK: - Feature Set Analysis
    
    private func analyzeFeatureSet(_ featureSet: FeatureSet) -> AnalyzedFeatureSet {
        let builder = SymbolTableBuilder(
            scopeId: "fs-\(featureSet.name.hashValue)",
            scopeName: featureSet.name
        )
        
        var dataFlows: [DataFlowInfo] = []
        var dependencies: Set<String> = []
        var exports: Set<String> = []
        var definedSymbols: Set<String> = []
        
        for statement in featureSet.statements {
            let (flow, newDeps) = analyzeStatement(
                statement,
                builder: builder,
                definedSymbols: &definedSymbols
            )
            dataFlows.append(flow)
            dependencies.formUnion(newDeps)

            if let publish = statement as? PublishStatement {
                exports.insert(publish.externalName)
            }

            // Handle RequireStatement (ARO-0003)
            if let require = statement as? RequireStatement {
                dependencies.insert(require.variableName)
            }
        }

        // Detect unused variables (ARO-0003)
        let symbolTable = builder.build()
        var usedVariables: Set<String> = []
        for flow in dataFlows {
            usedVariables.formUnion(flow.inputs)
        }

        for (name, symbol) in symbolTable.symbols {
            // Skip published variables (they're used externally)
            if symbol.visibility == .published { continue }
            // Skip aliases (the original is tracked)
            if case .alias = symbol.source { continue }
            // Skip external dependencies
            if symbol.visibility == .external { continue }

            if !usedVariables.contains(name) {
                diagnostics.warning(
                    "Variable '\(name)' is defined but never used",
                    at: symbol.definedAt.start
                )
            }
        }

        return AnalyzedFeatureSet(
            featureSet: featureSet,
            symbolTable: symbolTable,
            dataFlows: dataFlows,
            dependencies: dependencies,
            exports: exports
        )
    }
    
    // MARK: - Statement Analysis
    
    private func analyzeStatement(
        _ statement: Statement,
        builder: SymbolTableBuilder,
        definedSymbols: inout Set<String>
    ) -> (DataFlowInfo, Set<String>) {
        
        if let aro = statement as? AROStatement {
            return analyzeAROStatement(aro, builder: builder, definedSymbols: &definedSymbols)
        }
        
        if let publish = statement as? PublishStatement {
            return analyzePublishStatement(publish, builder: builder, definedSymbols: definedSymbols)
        }

        if let require = statement as? RequireStatement {
            return analyzeRequireStatement(require, builder: builder)
        }

        return (DataFlowInfo(), [])
    }
    
    private func analyzeAROStatement(
        _ statement: AROStatement,
        builder: SymbolTableBuilder,
        definedSymbols: inout Set<String>
    ) -> (DataFlowInfo, Set<String>) {

        var inputs: Set<String> = []
        var outputs: Set<String> = []
        var sideEffects: [String] = []
        var dependencies: Set<String> = []

        let resultName = statement.result.base
        let objectName = statement.object.noun.base

        // ARO-0002: Extract variables from expression if present
        if let expr = statement.expression {
            let exprVars = extractVariables(from: expr)
            for varName in exprVars {
                if !definedSymbols.contains(varName) && !isKnownExternal(varName) {
                    dependencies.insert(varName)
                }
                inputs.insert(varName)
            }
        }

        // Determine data flow based on action semantic role
        switch statement.action.semanticRole {
        case .request:
            // REQUEST: external -> internal
            // Creates a new variable from external source
            if !isKnownExternal(objectName) && !definedSymbols.contains(objectName) {
                dependencies.insert(objectName)
            }
            inputs.insert(objectName)
            outputs.insert(resultName)

            // ARO-0002: Infer type from expression if present
            let dataType: DataType
            if let expr = statement.expression {
                dataType = inferExpressionType(expr)
            } else {
                dataType = DataType.infer(from: statement.result.specifiers) ?? .custom("Any")
            }

            builder.define(
                name: resultName,
                definedAt: statement.span,
                visibility: .internal,
                source: .extracted(from: objectName),
                dataType: dataType
            )
            definedSymbols.insert(resultName)

        case .own:
            // OWN: internal computation
            // Uses existing variables, may create new one
            if !isKnownExternal(objectName) && !definedSymbols.contains(objectName) && !dependencies.contains(objectName) {
                diagnostics.warning(
                    "Variable '\(objectName)' used before definition",
                    at: statement.object.noun.span.start
                )
            }
            inputs.insert(objectName)
            outputs.insert(resultName)

            // ARO-0002: Infer type from expression if present
            let dataType: DataType
            if let expr = statement.expression {
                dataType = inferExpressionType(expr)
            } else {
                dataType = DataType.infer(from: statement.result.specifiers) ?? .custom("Any")
            }

            builder.define(
                name: resultName,
                definedAt: statement.span,
                visibility: .internal,
                source: .computed,
                dataType: dataType
            )
            definedSymbols.insert(resultName)

        case .response:
            // RESPONSE: internal -> external
            // Side effect, uses existing variable
            if !isKnownExternal(objectName) && !definedSymbols.contains(objectName) {
                diagnostics.warning(
                    "Variable '\(objectName)' used before definition",
                    at: statement.object.noun.span.start
                )
            }
            inputs.insert(objectName)
            sideEffects.append("\(statement.action.verb):\(resultName)")

        case .export:
            // Handled by PublishStatement
            break
        }

        return (
            DataFlowInfo(inputs: inputs, outputs: outputs, sideEffects: sideEffects),
            dependencies
        )
    }
    
    private func analyzePublishStatement(
        _ statement: PublishStatement,
        builder: SymbolTableBuilder,
        definedSymbols: Set<String>
    ) -> (DataFlowInfo, Set<String>) {
        
        // Verify the internal variable exists
        if !definedSymbols.contains(statement.internalVariable) {
            diagnostics.error(
                "Cannot publish undefined variable '\(statement.internalVariable)'",
                at: statement.span.start
            )
        }
        
        // Update visibility of the internal variable
        builder.updateVisibility(name: statement.internalVariable, to: .published)
        
        // Create alias for external name
        builder.define(
            name: statement.externalName,
            definedAt: statement.span,
            visibility: .published,
            source: .alias(of: statement.internalVariable)
        )
        
        return (
            DataFlowInfo(inputs: [statement.internalVariable], outputs: [statement.externalName]),
            []
        )
    }

    private func analyzeRequireStatement(
        _ statement: RequireStatement,
        builder: SymbolTableBuilder
    ) -> (DataFlowInfo, Set<String>) {
        // Register as an external dependency
        builder.define(
            name: statement.variableName,
            definedAt: statement.span,
            visibility: .external,
            source: .extracted(from: "\(statement.source)")
        )

        // The variable is treated as an input from external source
        return (
            DataFlowInfo(inputs: [], outputs: [statement.variableName]),
            [statement.variableName]
        )
    }

    // MARK: - Dependency Verification
    
    private func verifyDependencies(_ analyzed: AnalyzedFeatureSet) {
        for dependency in analyzed.dependencies {
            // Check if this dependency is published by another feature set
            if globalRegistry.lookup(dependency) == nil {
                // Check if it's a known external (framework-provided)
                if !isKnownExternal(dependency) {
                    diagnostics.warning(
                        "External dependency '\(dependency)' is not published by any feature set",
                        hints: ["Consider adding a <Publish> statement or marking it as framework-provided"]
                    )
                }
            }
        }
    }
    
    private func isKnownExternal(_ name: String) -> Bool {
        // These are typically provided by the framework/runtime
        let knownExternals: Set<String> = [
            // HTTP/Request context
            "request", "incoming-request", "context", "session",
            "pathparameters", "queryparameters", "headers",
            // Runtime objects
            "console", "application", "event",
            // Service targets
            "port", "host", "directory", "file", "events",
            // Literals (internal representation)
            "_literal_",
            // Expression placeholders (ARO-0002)
            "_expression_"
        ]
        return knownExternals.contains(name.lowercased())
    }

    // MARK: - Expression Analysis (ARO-0002)

    /// Extracts variable names referenced in an expression
    private func extractVariables(from expression: any Expression) -> Set<String> {
        var variables: Set<String> = []
        collectVariables(expression, into: &variables)
        return variables
    }

    private func collectVariables(_ expr: any Expression, into variables: inout Set<String>) {
        switch expr {
        case let varRef as VariableRefExpression:
            variables.insert(varRef.noun.base)

        case let binary as BinaryExpression:
            collectVariables(binary.left, into: &variables)
            collectVariables(binary.right, into: &variables)

        case let unary as UnaryExpression:
            collectVariables(unary.operand, into: &variables)

        case let member as MemberAccessExpression:
            collectVariables(member.base, into: &variables)

        case let subscript_ as SubscriptExpression:
            collectVariables(subscript_.base, into: &variables)
            collectVariables(subscript_.index, into: &variables)

        case let grouped as GroupedExpression:
            collectVariables(grouped.expression, into: &variables)

        case let existence as ExistenceExpression:
            collectVariables(existence.expression, into: &variables)

        case let typeCheck as TypeCheckExpression:
            collectVariables(typeCheck.expression, into: &variables)

        case let array as ArrayLiteralExpression:
            for element in array.elements {
                collectVariables(element, into: &variables)
            }

        case let map as MapLiteralExpression:
            for entry in map.entries {
                collectVariables(entry.value, into: &variables)
            }

        case let interp as InterpolatedStringExpression:
            for part in interp.parts {
                if case .interpolation(let expr) = part {
                    collectVariables(expr, into: &variables)
                }
            }

        default:
            // Literals don't have variables
            break
        }
    }

    /// Infers the type of an expression
    private func inferExpressionType(_ expr: any Expression) -> DataType {
        switch expr {
        case let literal as LiteralExpression:
            switch literal.value {
            case .string: return .string
            case .integer: return .custom("Integer")
            case .float: return .custom("Float")
            case .boolean: return .boolean
            case .null: return .custom("Null")
            }

        case is ArrayLiteralExpression:
            return .custom("List")

        case is MapLiteralExpression:
            return .custom("Map")

        case let binary as BinaryExpression:
            // Infer type based on operator
            switch binary.op {
            case .add, .subtract, .multiply, .divide, .modulo:
                return .custom("Number")
            case .concat:
                return .string
            case .equal, .notEqual, .lessThan, .greaterThan, .lessEqual, .greaterEqual,
                 .and, .or, .contains, .matches, .is, .isNot:
                return .boolean
            }

        case is UnaryExpression:
            return .custom("Any")

        case is VariableRefExpression:
            return .custom("Any")

        case is TypeCheckExpression, is ExistenceExpression:
            return .boolean

        case is InterpolatedStringExpression:
            return .string

        default:
            return .custom("Any")
        }
    }
}

// MARK: - Convenience Extension

extension SemanticAnalyzer {
    /// Analyzes source code in one step
    public static func analyze(_ source: String, diagnostics: DiagnosticCollector = DiagnosticCollector()) throws -> AnalyzedProgram {
        let program = try Parser.parse(source, diagnostics: diagnostics)
        return SemanticAnalyzer(diagnostics: diagnostics).analyze(program)
    }
}
