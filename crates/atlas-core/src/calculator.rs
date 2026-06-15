//! Inline expression evaluation for the Command Palette calculator provider.
//!
//! Pure numeric evaluation only — unit and currency conversion live on the
//! Swift side. Returns `None` for anything that does not evaluate to a finite
//! number so the palette can fall through to normal search silently.

use evalexpr::{eval, Value};

/// Evaluates a mathematical expression, returning a formatted result string.
///
/// Returns `None` when the input fails to parse, divides by zero, or produces
/// a non-finite value. The result is formatted with up to 6 significant
/// figures and trailing zeros trimmed.
pub fn evaluate_expression(input: &str) -> Option<String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return None;
    }

    match eval(trimmed).ok()? {
        Value::Float(f) if f.is_finite() => Some(format_number(f)),
        Value::Int(i) => Some(i.to_string()),
        _ => None,
    }
}

/// Formats a float with up to 6 significant figures, trimming trailing zeros.
/// Whole-valued floats render without a decimal point (e.g. `12`, not `12.0`).
fn format_number(value: f64) -> String {
    if value == value.trunc() && value.abs() < 1e15 {
        return format!("{}", value as i64);
    }

    // Up to 6 significant figures, then strip trailing zeros and any dangling dot.
    let formatted = format!("{:.6}", value);
    let trimmed = formatted.trim_end_matches('0').trim_end_matches('.');
    trimmed.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evaluates_basic_arithmetic() {
        assert_eq!(evaluate_expression("12 * 34 + 5"), Some("413".to_string()));
    }

    #[test]
    fn evaluates_power() {
        assert_eq!(evaluate_expression("2^10"), Some("1024".to_string()));
    }

    #[test]
    fn evaluates_sqrt() {
        assert_eq!(evaluate_expression("math::sqrt(144.0)"), Some("12".to_string()));
    }

    #[test]
    fn trims_trailing_zeros() {
        // pi approx via expression
        let result = evaluate_expression("3.14000").unwrap();
        assert_eq!(result, "3.14");
    }

    #[test]
    fn division_by_zero_returns_none() {
        assert_eq!(evaluate_expression("1 / 0"), None);
    }

    #[test]
    fn malformed_returns_none() {
        assert_eq!(evaluate_expression("12 *"), None);
        assert_eq!(evaluate_expression("hello world"), None);
    }

    #[test]
    fn empty_returns_none() {
        assert_eq!(evaluate_expression("   "), None);
    }

    #[test]
    fn fractional_result() {
        // 1/8 = 0.125
        assert_eq!(evaluate_expression("1.0 / 8.0"), Some("0.125".to_string()));
    }
}
