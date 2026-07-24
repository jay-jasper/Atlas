use crate::report::{CompatibilityFinding, CompatibilityStatus};
use crate::BuilderError;
use oxc_allocator::Allocator;
use oxc_ast::ast::{
    Argument, CallExpression, ExportAllDeclaration, ExportNamedDeclaration, Expression,
    IdentifierReference, ImportDeclaration, ImportDeclarationSpecifier, ImportExpression,
    StringLiteral, TemplateElement,
};
use oxc_ast_visit::{walk, Visit};
use oxc_parser::Parser;
use oxc_semantic::{IsGlobalReference, Scoping, SemanticBuilder};
use oxc_span::{SourceType, Span};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApiUse {
    pub symbol: String,
    pub line: u32,
    pub column: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceAnalysis {
    pub api_usage: Vec<ApiUse>,
    pub capabilities: BTreeSet<String>,
    pub domains: BTreeSet<String>,
    pub compatibility: Vec<CompatibilityFinding>,
    #[serde(skip)]
    pub(crate) module_specifiers: BTreeSet<String>,
}

pub fn analyze_source(source: &str, file: &Path) -> Result<SourceAnalysis, BuilderError> {
    let source_type = SourceType::from_path(file)
        .map_err(|error| BuilderError::Analysis(format!("{}: {error}", file.display())))?;
    let allocator = Allocator::default();
    let parsed = Parser::new(&allocator, source, source_type).parse();
    if let Some(diagnostic) = parsed.diagnostics.first() {
        return Err(BuilderError::Analysis(format!(
            "{}: {diagnostic:?}",
            file.display()
        )));
    }
    let semantic = SemanticBuilder::new_compiler().build(&parsed.program);
    if let Some(diagnostic) = semantic.diagnostics.first() {
        return Err(BuilderError::Analysis(format!(
            "{}: {diagnostic:?}",
            file.display()
        )));
    }

    let mut analyzer = AstAnalyzer {
        source,
        file,
        scoping: semantic.semantic.scoping(),
        output: SourceAnalysis::default(),
        denied: None,
    };
    analyzer.visit_program(&parsed.program);
    if let Some((code, span)) = analyzer.denied {
        let (line, column) = location(source, span.start as usize);
        return Err(BuilderError::SourceDenied {
            code: code.into(),
            file: file.into(),
            line,
            column,
        });
    }

    Ok(analyzer.output)
}

pub fn analyze_project(
    entrypoint: &Path,
    source_root: &Path,
) -> Result<SourceAnalysis, BuilderError> {
    let root = source_root.canonicalize()?;
    let mut pending = vec![entrypoint.canonicalize()?];
    let mut visited = BTreeSet::new();
    let mut combined = SourceAnalysis::default();

    while let Some(module) = pending.pop() {
        if !module.starts_with(&root) {
            return Err(BuilderError::Analysis(format!(
                "source import escapes plugin root: {}",
                module.display()
            )));
        }
        if !visited.insert(module.clone()) {
            continue;
        }
        let mut analysis = analyze_source(&std::fs::read_to_string(&module)?, &module)?;
        for specifier in &analysis.module_specifiers {
            if let Some(resolved) = resolve_relative_module(&module, specifier) {
                pending.push(resolved.canonicalize()?);
            }
        }
        combined.api_usage.append(&mut analysis.api_usage);
        combined.capabilities.append(&mut analysis.capabilities);
        combined.domains.append(&mut analysis.domains);
        combined.compatibility.append(&mut analysis.compatibility);
        combined
            .module_specifiers
            .append(&mut analysis.module_specifiers);
    }
    Ok(combined)
}

struct AstAnalyzer<'s> {
    source: &'s str,
    file: &'s Path,
    scoping: &'s Scoping,
    output: SourceAnalysis,
    denied: Option<(&'static str, Span)>,
}

impl AstAnalyzer<'_> {
    fn deny(&mut self, code: &'static str, span: Span) {
        if self.denied.is_none() {
            self.denied = Some((code, span));
        }
    }

    fn record_raycast_symbol(&mut self, symbol: &str, span: Span) {
        let (line, column) = location(self.source, span.start as usize);
        self.output.api_usage.push(ApiUse {
            symbol: symbol.into(),
            line,
            column,
        });
        match symbol {
            "Clipboard" => {
                self.output.capabilities.insert("clipboard.read".into());
                self.output.capabilities.insert("clipboard.write".into());
            }
            "LocalStorage" | "Cache" => {
                self.output.capabilities.insert("storage.read".into());
                self.output.capabilities.insert("storage.write".into());
            }
            "AI" => self.output.compatibility.push(CompatibilityFinding {
                code: "unsupported-api".into(),
                status: CompatibilityStatus::Unsupported,
                message: "Raycast AI is unavailable".into(),
                file: Some(self.file.into()),
                line: Some(line),
                column: Some(column),
                raycast_symbol: Some("AI".into()),
                atlas_alternative: None,
            }),
            _ => {}
        }
    }

    fn record_domains(&mut self, text: &str) {
        let mut remaining = text;
        while let Some(offset) = remaining.find("https://") {
            let host_start = offset + "https://".len();
            let host = remaining[host_start..]
                .chars()
                .take_while(|character| {
                    character.is_ascii_alphanumeric() || matches!(character, '.' | '-')
                })
                .collect::<String>();
            if !host.is_empty() && host.contains('.') {
                self.output.domains.insert(host.to_ascii_lowercase());
                self.output.capabilities.insert("network.https".into());
            }
            remaining = &remaining[host_start..];
        }
    }
}

impl<'a> Visit<'a> for AstAnalyzer<'_> {
    fn visit_import_declaration(&mut self, declaration: &ImportDeclaration<'a>) {
        let module = declaration.source.value.as_str();
        self.output.module_specifiers.insert(module.into());
        if is_node_builtin(module) {
            self.deny("node-builtin-denied", declaration.source.span);
        } else if module == "@raycast/api" {
            if let Some(specifiers) = &declaration.specifiers {
                for specifier in specifiers {
                    if let ImportDeclarationSpecifier::ImportSpecifier(specifier) = specifier {
                        self.record_raycast_symbol(
                            specifier.imported.name().as_str(),
                            specifier.span,
                        );
                    }
                }
            }
        }
        walk::walk_import_declaration(self, declaration);
    }

    fn visit_export_named_declaration(&mut self, declaration: &ExportNamedDeclaration<'a>) {
        if let Some(source) = &declaration.source {
            self.output
                .module_specifiers
                .insert(source.value.to_string());
        }
        if declaration
            .source
            .as_ref()
            .is_some_and(|source| source.value == "@raycast/api")
        {
            for specifier in &declaration.specifiers {
                self.record_raycast_symbol(specifier.local.name().as_str(), specifier.span);
            }
        }
        walk::walk_export_named_declaration(self, declaration);
    }

    fn visit_export_all_declaration(&mut self, declaration: &ExportAllDeclaration<'a>) {
        self.output
            .module_specifiers
            .insert(declaration.source.value.to_string());
        if declaration.source.value == "@raycast/api" {
            self.output.compatibility.push(CompatibilityFinding {
                code: "raycast-wildcard-reexport".into(),
                status: CompatibilityStatus::Adapted,
                message: "Raycast wildcard re-export is resolved by the compatibility adapter"
                    .into(),
                file: Some(self.file.into()),
                line: Some(location(self.source, declaration.span.start as usize).0),
                column: Some(location(self.source, declaration.span.start as usize).1),
                raycast_symbol: Some("*".into()),
                atlas_alternative: Some("@atlas/raycast-compat".into()),
            });
        }
        walk::walk_export_all_declaration(self, declaration);
    }

    fn visit_import_expression(&mut self, expression: &ImportExpression<'a>) {
        match &expression.source {
            Expression::StringLiteral(literal) => {
                self.output
                    .module_specifiers
                    .insert(literal.value.to_string());
                if is_node_builtin(literal.value.as_str()) {
                    self.deny("node-builtin-denied", literal.span);
                }
            }
            _ => self.deny("dynamic-import-denied", expression.span),
        }
        walk::walk_import_expression(self, expression);
    }

    fn visit_call_expression(&mut self, expression: &CallExpression<'a>) {
        if let Expression::Identifier(callee) = &expression.callee {
            if callee.name == "require" && callee.is_global_reference(self.scoping) {
                match expression.arguments.first() {
                    Some(Argument::StringLiteral(literal)) => {
                        if is_node_builtin(literal.value.as_str()) {
                            self.deny("node-builtin-denied", literal.span);
                        }
                    }
                    _ => self.deny("dynamic-require-denied", expression.span),
                }
            }
        }
        walk::walk_call_expression(self, expression);
    }

    fn visit_identifier_reference(&mut self, identifier: &IdentifierReference<'a>) {
        if identifier.is_global_reference(self.scoping) {
            match identifier.name.as_str() {
                "eval" | "Function" => self.deny("dynamic-code-denied", identifier.span),
                "window" | "document" | "HTMLElement" | "localStorage" => {
                    self.deny("dom-global-denied", identifier.span);
                }
                "process" => self.deny("node-global-denied", identifier.span),
                _ => {}
            }
        }
        walk::walk_identifier_reference(self, identifier);
    }

    fn visit_string_literal(&mut self, literal: &StringLiteral<'a>) {
        self.record_domains(literal.value.as_str());
        walk::walk_string_literal(self, literal);
    }

    fn visit_template_element(&mut self, element: &TemplateElement<'a>) {
        self.record_domains(
            element
                .value
                .cooked
                .as_ref()
                .unwrap_or(&element.value.raw)
                .as_str(),
        );
        walk::walk_template_element(self, element);
    }
}

fn is_node_builtin(module: &str) -> bool {
    matches!(
        module.strip_prefix("node:").unwrap_or(module),
        "fs" | "path" | "child_process" | "net" | "tls" | "http" | "https" | "os" | "process"
    )
}

fn resolve_relative_module(importer: &Path, specifier: &str) -> Option<PathBuf> {
    if !specifier.starts_with('.') {
        return None;
    }
    let base = importer.parent()?.join(specifier);
    let mut candidates = vec![base.clone()];
    for extension in ["ts", "tsx", "js", "jsx", "mts", "cts", "mjs", "cjs"] {
        candidates.push(base.with_extension(extension));
        candidates.push(base.join(format!("index.{extension}")));
    }
    candidates.into_iter().find(|candidate| candidate.is_file())
}

fn location(source: &str, offset: usize) -> (u32, u32) {
    let prefix = &source[..offset];
    let line = prefix.bytes().filter(|byte| *byte == b'\n').count() as u32 + 1;
    let column = prefix
        .rsplit('\n')
        .next()
        .map_or(1, |text| text.chars().count() as u32 + 1);
    (line, column)
}
