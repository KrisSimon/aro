// ============================================================
// AST.swift
// ARO Parser - Abstract Syntax Tree Definitions
// ============================================================

import Foundation

// MARK: - AST Node Protocol

/// Base protocol for all AST nodes
public protocol ASTNode: Sendable, Locatable, CustomStringConvertible {
    /// Accepts a visitor for traversal
    func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result
}

// MARK: - Program (Root Node)

/// The root node representing an entire ARO program
public struct Program: ASTNode {
    public let featureSets: [FeatureSet]
    public let span: SourceSpan
    
    public init(featureSets: [FeatureSet], span: SourceSpan) {
        self.featureSets = featureSets
        self.span = span
    }
    
    public var description: String {
        "Program(\(featureSets.count) feature sets)"
    }
    
    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - Feature Set

/// A feature set containing related features
public struct FeatureSet: ASTNode {
    public let name: String
    public let businessActivity: String
    public let statements: [Statement]
    public let span: SourceSpan
    
    public init(name: String, businessActivity: String, statements: [Statement], span: SourceSpan) {
        self.name = name
        self.businessActivity = businessActivity
        self.statements = statements
        self.span = span
    }
    
    public var description: String {
        "FeatureSet(\(name): \(businessActivity), \(statements.count) statements)"
    }
    
    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - Statements

/// Protocol for all statement types
public protocol Statement: ASTNode {}

/// An ARO (Action-Result-Object) statement
public struct AROStatement: Statement {
    public let action: Action
    public let result: QualifiedNoun
    public let object: ObjectClause
    /// Optional literal value (e.g., `with "string"`, `with 42`) - legacy support
    public let literalValue: LiteralValue?
    /// Optional expression value (ARO-0002) - for computed values like `from <x> * <y>`
    public let expression: (any Expression)?
    public let span: SourceSpan

    public init(
        action: Action,
        result: QualifiedNoun,
        object: ObjectClause,
        literalValue: LiteralValue? = nil,
        expression: (any Expression)? = nil,
        span: SourceSpan
    ) {
        self.action = action
        self.result = result
        self.object = object
        self.literalValue = literalValue
        self.expression = expression
        self.span = span
    }

    public var description: String {
        var desc = "<\(action.verb)> the <\(result)> \(object.preposition) the <\(object.noun)>"
        if let literal = literalValue {
            desc += " with \(literal)"
        }
        if let expr = expression {
            desc += " = \(expr)"
        }
        return desc + "."
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

/// A publish statement for exporting variables
public struct PublishStatement: Statement {
    public let externalName: String
    public let internalVariable: String
    public let span: SourceSpan
    
    public init(externalName: String, internalVariable: String, span: SourceSpan) {
        self.externalName = externalName
        self.internalVariable = internalVariable
        self.span = span
    }
    
    public var description: String {
        "<Publish> as <\(externalName)> <\(internalVariable)>."
    }
    
    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - Require Statement (ARO-0003)

/// Source for a required dependency
public enum RequireSource: Sendable, Equatable, CustomStringConvertible {
    case framework
    case environment
    case featureSet(String)

    public var description: String {
        switch self {
        case .framework: return "framework"
        case .environment: return "environment"
        case .featureSet(let name): return name
        }
    }
}

/// Statement for declaring external dependencies: <Require> the <variable> from the <source>.
public struct RequireStatement: Statement {
    public let variableName: String
    public let source: RequireSource
    public let span: SourceSpan

    public init(variableName: String, source: RequireSource, span: SourceSpan) {
        self.variableName = variableName
        self.source = source
        self.span = span
    }

    public var description: String {
        "<Require> the <\(variableName)> from the <\(source)>."
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - Action

/// Represents an action verb with semantic classification
public struct Action: Sendable, Equatable, CustomStringConvertible {
    public let verb: String
    public let span: SourceSpan
    
    public init(verb: String, span: SourceSpan) {
        self.verb = verb
        self.span = span
    }
    
    /// The semantic role of this action
    public var semanticRole: ActionSemanticRole {
        ActionSemanticRole.classify(verb: verb)
    }
    
    public var description: String {
        verb
    }
}

/// Semantic classification of actions
public enum ActionSemanticRole: String, Sendable, CaseIterable {
    case request    // Fetches from external (Extract, Parse, Retrieve)
    case own        // Internal computation (Compute, Validate, Compare)
    case response   // Outputs to external (Return, Throw, Send)
    case export     // Makes available to other feature sets (Publish)
    
    /// Classifies a verb into its semantic role
    public static func classify(verb: String) -> ActionSemanticRole {
        let lower = verb.lowercased()
        
        let requestVerbs = ["extract", "parse", "retrieve", "fetch", "read", "receive", "get", "load"]
        let responseVerbs = ["return", "throw", "send", "emit", "respond", "output", "write"]
        let exportVerbs = ["publish", "export", "expose", "share"]
        
        if requestVerbs.contains(lower) { return .request }
        if responseVerbs.contains(lower) { return .response }
        if exportVerbs.contains(lower) { return .export }
        return .own
    }
}

// MARK: - Qualified Noun

/// A noun with optional specifiers (e.g., <user: identifier name>)
public struct QualifiedNoun: Sendable, Equatable, CustomStringConvertible {
    public let base: String
    public let specifiers: [String]
    public let span: SourceSpan
    
    public init(base: String, specifiers: [String] = [], span: SourceSpan) {
        self.base = base
        self.specifiers = specifiers
        self.span = span
    }
    
    /// The full qualified name
    public var fullName: String {
        if specifiers.isEmpty {
            return base
        }
        return "\(base): \(specifiers.joined(separator: " "))"
    }
    
    public var description: String {
        fullName
    }
}

// MARK: - Object Clause

/// A literal value that can be passed with an ARO statement
public enum LiteralValue: Sendable, Equatable, CustomStringConvertible {
    case string(String)
    case integer(Int)
    case float(Double)
    case boolean(Bool)
    case null

    public var description: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .integer(let i): return "\(i)"
        case .float(let f): return "\(f)"
        case .boolean(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }
}

/// The object part of an ARO statement
public struct ObjectClause: Sendable, Equatable, CustomStringConvertible {
    public let preposition: Preposition
    public let noun: QualifiedNoun
    
    public init(preposition: Preposition, noun: QualifiedNoun) {
        self.preposition = preposition
        self.noun = noun
    }
    
    /// Whether this references an external source
    public var isExternalReference: Bool {
        preposition.indicatesExternalSource
    }
    
    public var description: String {
        "\(preposition.rawValue) the <\(noun)>"
    }
}

// MARK: - Expressions (ARO-0002)

/// Base protocol for all expression nodes
public protocol Expression: ASTNode {}

// MARK: - Literal Expressions

/// A literal value expression
public struct LiteralExpression: Expression {
    public let value: LiteralValue
    public let span: SourceSpan

    public init(value: LiteralValue, span: SourceSpan) {
        self.value = value
        self.span = span
    }

    public var description: String {
        value.description
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

/// An array literal expression: [1, 2, 3]
public struct ArrayLiteralExpression: Expression {
    public let elements: [any Expression]
    public let span: SourceSpan

    public init(elements: [any Expression], span: SourceSpan) {
        self.elements = elements
        self.span = span
    }

    public var description: String {
        "[\(elements.map { $0.description }.joined(separator: ", "))]"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

/// A map literal expression: { name: "John", age: 30 }
public struct MapLiteralExpression: Expression {
    public let entries: [MapEntry]
    public let span: SourceSpan

    public init(entries: [MapEntry], span: SourceSpan) {
        self.entries = entries
        self.span = span
    }

    public var description: String {
        "{ \(entries.map { $0.description }.joined(separator: ", ")) }"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

/// A single map entry
public struct MapEntry: Sendable, CustomStringConvertible {
    public let key: String
    public let value: any Expression
    public let span: SourceSpan

    public init(key: String, value: any Expression, span: SourceSpan) {
        self.key = key
        self.value = value
        self.span = span
    }

    public var description: String {
        "\(key): \(value.description)"
    }
}

// MARK: - Reference Expressions

/// A variable reference expression: <user> or <user: name>
public struct VariableRefExpression: Expression {
    public let noun: QualifiedNoun
    public let span: SourceSpan

    public init(noun: QualifiedNoun, span: SourceSpan) {
        self.noun = noun
        self.span = span
    }

    public var description: String {
        "<\(noun.fullName)>"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - Operator Expressions

/// Binary operators
public enum BinaryOperator: String, Sendable, CaseIterable {
    // Arithmetic
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "%"
    case concat = "++"

    // Comparison
    case equal = "=="
    case notEqual = "!="
    case lessThan = "<"
    case greaterThan = ">"
    case lessEqual = "<="
    case greaterEqual = ">="
    case `is` = "is"
    case isNot = "is not"

    // Logical
    case and = "and"
    case or = "or"

    // Collection
    case contains = "contains"
    case matches = "matches"
}

/// Unary operators
public enum UnaryOperator: String, Sendable, CaseIterable {
    case negate = "-"
    case not = "not"
}

/// A binary expression: a + b, x == y, etc.
public struct BinaryExpression: Expression {
    public let left: any Expression
    public let op: BinaryOperator
    public let right: any Expression
    public let span: SourceSpan

    public init(left: any Expression, op: BinaryOperator, right: any Expression, span: SourceSpan) {
        self.left = left
        self.op = op
        self.right = right
        self.span = span
    }

    public var description: String {
        "(\(left.description) \(op.rawValue) \(right.description))"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

/// A unary expression: -x, not x
public struct UnaryExpression: Expression {
    public let op: UnaryOperator
    public let operand: any Expression
    public let span: SourceSpan

    public init(op: UnaryOperator, operand: any Expression, span: SourceSpan) {
        self.op = op
        self.operand = operand
        self.span = span
    }

    public var description: String {
        "(\(op.rawValue)\(operand.description))"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - Access Expressions

/// Member access expression: <user>.name
public struct MemberAccessExpression: Expression {
    public let base: any Expression
    public let member: String
    public let span: SourceSpan

    public init(base: any Expression, member: String, span: SourceSpan) {
        self.base = base
        self.member = member
        self.span = span
    }

    public var description: String {
        "\(base.description).\(member)"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

/// Subscript expression: <items>[0]
public struct SubscriptExpression: Expression {
    public let base: any Expression
    public let index: any Expression
    public let span: SourceSpan

    public init(base: any Expression, index: any Expression, span: SourceSpan) {
        self.base = base
        self.index = index
        self.span = span
    }

    public var description: String {
        "\(base.description)[\(index.description)]"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - Special Expressions

/// Grouped (parenthesized) expression: (expr)
public struct GroupedExpression: Expression {
    public let expression: any Expression
    public let span: SourceSpan

    public init(expression: any Expression, span: SourceSpan) {
        self.expression = expression
        self.span = span
    }

    public var description: String {
        "(\(expression.description))"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

/// Existence check expression: <x> exists
public struct ExistenceExpression: Expression {
    public let expression: any Expression
    public let span: SourceSpan

    public init(expression: any Expression, span: SourceSpan) {
        self.expression = expression
        self.span = span
    }

    public var description: String {
        "\(expression.description) exists"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

/// Type check expression: <x> is a Number
public struct TypeCheckExpression: Expression {
    public let expression: any Expression
    public let typeName: String
    public let hasArticle: Bool
    public let span: SourceSpan

    public init(expression: any Expression, typeName: String, hasArticle: Bool, span: SourceSpan) {
        self.expression = expression
        self.typeName = typeName
        self.hasArticle = hasArticle
        self.span = span
    }

    public var description: String {
        if hasArticle {
            return "\(expression.description) is a \(typeName)"
        }
        return "\(expression.description) is \(typeName)"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - String Interpolation

/// Part of an interpolated string
public enum StringPart: Sendable, CustomStringConvertible {
    case literal(String)
    case interpolation(any Expression)

    public var description: String {
        switch self {
        case .literal(let s): return s
        case .interpolation(let expr): return "${\(expr.description)}"
        }
    }
}

/// Interpolated string expression: "Hello ${<name>}!"
public struct InterpolatedStringExpression: Expression {
    public let parts: [StringPart]
    public let span: SourceSpan

    public init(parts: [StringPart], span: SourceSpan) {
        self.parts = parts
        self.span = span
    }

    public var description: String {
        "\"\(parts.map { $0.description }.joined())\""
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visit(self)
    }
}

// MARK: - AST Visitor Protocol

/// Visitor pattern for AST traversal
public protocol ASTVisitor {
    associatedtype Result

    func visit(_ node: Program) throws -> Result
    func visit(_ node: FeatureSet) throws -> Result
    func visit(_ node: AROStatement) throws -> Result
    func visit(_ node: PublishStatement) throws -> Result
    func visit(_ node: RequireStatement) throws -> Result

    // Expression visitors (ARO-0002)
    func visit(_ node: LiteralExpression) throws -> Result
    func visit(_ node: ArrayLiteralExpression) throws -> Result
    func visit(_ node: MapLiteralExpression) throws -> Result
    func visit(_ node: VariableRefExpression) throws -> Result
    func visit(_ node: BinaryExpression) throws -> Result
    func visit(_ node: UnaryExpression) throws -> Result
    func visit(_ node: MemberAccessExpression) throws -> Result
    func visit(_ node: SubscriptExpression) throws -> Result
    func visit(_ node: GroupedExpression) throws -> Result
    func visit(_ node: ExistenceExpression) throws -> Result
    func visit(_ node: TypeCheckExpression) throws -> Result
    func visit(_ node: InterpolatedStringExpression) throws -> Result
}

/// Default implementations that traverse children
public extension ASTVisitor where Result == Void {
    func visit(_ node: Program) throws {
        for featureSet in node.featureSets {
            try featureSet.accept(self)
        }
    }

    func visit(_ node: FeatureSet) throws {
        for statement in node.statements {
            try statement.accept(self)
        }
    }

    func visit(_ node: AROStatement) throws {}
    func visit(_ node: PublishStatement) throws {}
    func visit(_ node: RequireStatement) throws {}

    // Expression default implementations
    func visit(_ node: LiteralExpression) throws {}
    func visit(_ node: ArrayLiteralExpression) throws {
        for element in node.elements {
            try element.accept(self)
        }
    }
    func visit(_ node: MapLiteralExpression) throws {
        for entry in node.entries {
            try entry.value.accept(self)
        }
    }
    func visit(_ node: VariableRefExpression) throws {}
    func visit(_ node: BinaryExpression) throws {
        try node.left.accept(self)
        try node.right.accept(self)
    }
    func visit(_ node: UnaryExpression) throws {
        try node.operand.accept(self)
    }
    func visit(_ node: MemberAccessExpression) throws {
        try node.base.accept(self)
    }
    func visit(_ node: SubscriptExpression) throws {
        try node.base.accept(self)
        try node.index.accept(self)
    }
    func visit(_ node: GroupedExpression) throws {
        try node.expression.accept(self)
    }
    func visit(_ node: ExistenceExpression) throws {
        try node.expression.accept(self)
    }
    func visit(_ node: TypeCheckExpression) throws {
        try node.expression.accept(self)
    }
    func visit(_ node: InterpolatedStringExpression) throws {
        for part in node.parts {
            if case .interpolation(let expr) = part {
                try expr.accept(self)
            }
        }
    }
}

// MARK: - AST Pretty Printer

/// Prints the AST in a readable format
public struct ASTPrinter: ASTVisitor {
    public typealias Result = String
    
    private var indent: Int = 0
    
    public init() {}
    
    private func indentation() -> String {
        String(repeating: "  ", count: indent)
    }
    
    public func visit(_ node: Program) -> String {
        var result = "Program\n"
        var printer = self
        printer.indent += 1
        for featureSet in node.featureSets {
            result += try! featureSet.accept(printer)
        }
        return result
    }
    
    public func visit(_ node: FeatureSet) -> String {
        var result = "\(indentation())FeatureSet: \(node.name)\n"
        result += "\(indentation())  BusinessActivity: \(node.businessActivity)\n"
        
        var printer = self
        printer.indent += 1
        for statement in node.statements {
            result += try! statement.accept(printer)
        }
        return result
    }
    
    public func visit(_ node: AROStatement) -> String {
        var result = "\(indentation())AROStatement\n"
        result += "\(indentation())  Action: \(node.action.verb) [\(node.action.semanticRole)]\n"
        result += "\(indentation())  Result: \(node.result.fullName)\n"
        result += "\(indentation())  Object: \(node.object.preposition.rawValue) \(node.object.noun.fullName)\n"
        return result
    }
    
    public func visit(_ node: PublishStatement) -> String {
        var result = "\(indentation())PublishStatement\n"
        result += "\(indentation())  External: \(node.externalName)\n"
        result += "\(indentation())  Internal: \(node.internalVariable)\n"
        return result
    }

    public func visit(_ node: RequireStatement) -> String {
        var result = "\(indentation())RequireStatement\n"
        result += "\(indentation())  Variable: \(node.variableName)\n"
        result += "\(indentation())  Source: \(node.source)\n"
        return result
    }

    // Expression visitors
    public func visit(_ node: LiteralExpression) -> String {
        "\(indentation())Literal: \(node.value)\n"
    }

    public func visit(_ node: ArrayLiteralExpression) -> String {
        var result = "\(indentation())Array[\(node.elements.count)]\n"
        var printer = self
        printer.indent += 1
        for element in node.elements {
            result += try! element.accept(printer)
        }
        return result
    }

    public func visit(_ node: MapLiteralExpression) -> String {
        var result = "\(indentation())Map{\(node.entries.count)}\n"
        var printer = self
        printer.indent += 1
        for entry in node.entries {
            result += "\(printer.indentation())\(entry.key):\n"
            printer.indent += 1
            result += try! entry.value.accept(printer)
            printer.indent -= 1
        }
        return result
    }

    public func visit(_ node: VariableRefExpression) -> String {
        "\(indentation())VarRef: <\(node.noun.fullName)>\n"
    }

    public func visit(_ node: BinaryExpression) -> String {
        var result = "\(indentation())Binary: \(node.op.rawValue)\n"
        var printer = self
        printer.indent += 1
        result += try! node.left.accept(printer)
        result += try! node.right.accept(printer)
        return result
    }

    public func visit(_ node: UnaryExpression) -> String {
        var result = "\(indentation())Unary: \(node.op.rawValue)\n"
        var printer = self
        printer.indent += 1
        result += try! node.operand.accept(printer)
        return result
    }

    public func visit(_ node: MemberAccessExpression) -> String {
        var result = "\(indentation())MemberAccess: .\(node.member)\n"
        var printer = self
        printer.indent += 1
        result += try! node.base.accept(printer)
        return result
    }

    public func visit(_ node: SubscriptExpression) -> String {
        var result = "\(indentation())Subscript\n"
        var printer = self
        printer.indent += 1
        result += "\(printer.indentation())base:\n"
        printer.indent += 1
        result += try! node.base.accept(printer)
        printer.indent -= 1
        result += "\(printer.indentation())index:\n"
        printer.indent += 1
        result += try! node.index.accept(printer)
        return result
    }

    public func visit(_ node: GroupedExpression) -> String {
        var result = "\(indentation())Grouped\n"
        var printer = self
        printer.indent += 1
        result += try! node.expression.accept(printer)
        return result
    }

    public func visit(_ node: ExistenceExpression) -> String {
        var result = "\(indentation())Exists\n"
        var printer = self
        printer.indent += 1
        result += try! node.expression.accept(printer)
        return result
    }

    public func visit(_ node: TypeCheckExpression) -> String {
        var result = "\(indentation())TypeCheck: \(node.typeName)\n"
        var printer = self
        printer.indent += 1
        result += try! node.expression.accept(printer)
        return result
    }

    public func visit(_ node: InterpolatedStringExpression) -> String {
        var result = "\(indentation())InterpolatedString[\(node.parts.count) parts]\n"
        var printer = self
        printer.indent += 1
        for part in node.parts {
            switch part {
            case .literal(let s):
                result += "\(printer.indentation())literal: \"\(s)\"\n"
            case .interpolation(let expr):
                result += "\(printer.indentation())interpolation:\n"
                printer.indent += 1
                result += try! expr.accept(printer)
                printer.indent -= 1
            }
        }
        return result
    }
}
