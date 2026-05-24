# Calculator & Unit Conversion — Command Palette Provider

**Date:** 2026-05-24  
**Status:** Approved  
**Feature:** `calculator` (Palette Provider, no standalone module)

---

## Overview

A Command Palette provider that detects mathematical expressions, unit conversions, and currency exchanges inline as the user types. When a pattern is recognized, a result item is injected at the top of palette results. No trigger keyword required — recognition is automatic and silent (unrecognized input falls through to normal search).

---

## Architecture

```
User input
    │
    ▼
CalculatorCommandProvider (Swift, CommandProviding)
    ├── ExpressionDetector      → classify input intent
    ├── AtlasBridge.evaluateExpression()  →  FFI  →  atlas-core/calculator.rs
    │       └── evalexpr crate  →  numeric result string
    ├── UnitConverter (Swift, static tables, offline)
    └── CurrencyService (Swift, HTTP + UserDefaults cache TTL 1h)
    │
    ▼
CommandItem (injected at top of palette results)
    ├── title:    "= 413"
    ├── subtitle: "12 * 34 + 5"
    ├── badge:    "Calculator" | "Unit" | "Currency"
    └── actions:  Copy Result (default) | Copy Expression (⌘C)
```

### Layer responsibilities

| Layer | Responsibility |
|-------|---------------|
| `atlas-core/src/calculator.rs` | Pure expression evaluation via `evalexpr`. No unit or currency logic. Returns `Option<String>`. |
| `atlas-ffi` UDL | Exposes `string? evaluate_expression(string input)` |
| `ExpressionDetector.swift` | Classifies input as `.math`, `.unitConversion`, `.currency`, or `.none` using regex |
| `UnitConverter.swift` | Static offline conversion tables for 5 unit categories |
| `CurrencyService.swift` | Fetches and caches exchange rate table from exchangerate-api.com |
| `CalculatorCommandProvider.swift` | Orchestrates detection → evaluation → `CommandItem` assembly |

---

## Expression Detection

Priority order (first match wins):

1. **Currency** — `^\d+(\.\d+)?\s+[A-Z]{3}\s+(to|in)\s+[A-Z]{3}$`  
   e.g. `100 USD to CNY`

2. **Unit conversion** — `^\d+(\.\d+)?\s+<unit>\s+(to|in)\s+<unit>$`  
   e.g. `5 km to miles`

3. **Percentage shorthand** — `^\d+(\.\d+)?%\s+of\s+\d+(\.\d+)?$`  
   Expanded to `0.XX * N` before passing to evalexpr.

4. **Math expression** — contains operator characters `+-*/^()` adjacent to digits  
   e.g. `12 * 34 + 5`, `sqrt(144)`, `pi * 5^2`

5. **No match** — provider returns empty array; does not interfere with other providers.

### evalexpr capabilities

| Input | Output |
|-------|--------|
| `2^10` | `1024` |
| `sqrt(144)` | `12` |
| `pi * 5^2` | `78.54` |
| `(1 + 0.05)^12` | `1.796` |
| `15% of 320` (expanded) | `48` |

### Unit coverage (offline)

| Category | Units |
|----------|-------|
| Length | km, m, cm, mm, miles, ft, in |
| Weight | kg, g, lbs, oz |
| Temperature | °C, °F, K |
| Storage | TB, GB, MB, KB |
| Speed | km/h, mph, m/s |

---

## Currency Service

- **Endpoint:** `https://api.exchangerate-api.com/v4/latest/USD`
- **Cache:** Full rate table stored in `UserDefaults` with a timestamp key
- **TTL:** 1 hour. On cache miss or expiry, fetch in background; display stale result immediately if available.
- **Staleness label:** Result subtitle shows "Rate from X minutes ago" when cache age > 5 min.
- **Offline / API failure, no cache:** Show "Exchange rates unavailable — check network" as subtitle, no result value.
- **Unknown currency code:** Return `.none`; fall through to normal search.

---

## Result Display

```
┌──────────────────────────────────────────────────────┐
│  = 413                                  [Calculator]  │
│    12 * 34 + 5                                        │
│    ↵ Copy  ·  ⌘C Copy with expression                │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  = 3.107 miles                              [Unit]    │
│    5 km → miles                                       │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  = 724.50 CNY                         [Currency]      │
│    100 USD · Rate from 23 minutes ago                 │
└──────────────────────────────────────────────────────┘
```

- Result item is always index 0 in provider output.
- Default action (Return): copy result value to clipboard, e.g. `413`.
- Secondary action (⌘C): copy full expression, e.g. `12 * 34 + 5 = 413`.
- Numbers formatted with up to 6 significant figures; trailing zeros trimmed.

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| evalexpr parse failure (e.g. `1 / 0`, malformed) | Return `.none`; silent, no UI effect |
| Unsupported unit | Return `.none` |
| Currency API failure, cache present | Show result with stale-data label |
| Currency API failure, no cache | Show "Exchange rates unavailable" subtitle, no value |
| Invalid currency code (e.g. `ABC`) | Return `.none` |

---

## Rust Changes

**`crates/atlas-core/Cargo.toml`**
```toml
[dependencies]
evalexpr = "11"
```

**`crates/atlas-core/src/calculator.rs`** (new file)
```rust
pub fn evaluate_expression(input: &str) -> Option<String> {
    evalexpr::eval(input)
        .ok()
        .map(|v| format_value(v))
}
```

**`crates/atlas-ffi/src/atlas.udl`** (addition)
```
namespace atlas {
    string? evaluate_expression(string input);
};
```

---

## New Swift Files

| File | Purpose |
|------|---------|
| `ExpressionDetector.swift` | Regex-based intent classifier |
| `UnitConverter.swift` | Static offline conversion tables |
| `CurrencyService.swift` | HTTP fetch + UserDefaults cache |
| `CalculatorCommandProvider.swift` | Provider orchestrator |

`CalculatorCommandProvider` is registered in `CommandPaletteState.init()` alongside existing providers.

---

## Testing

| Test file | Coverage |
|-----------|---------|
| `CalculatorTests.swift` (Rust, `atlas-core`) | evaluate_expression: valid expressions, division by zero, malformed input |
| `ExpressionDetectorTests.swift` | All detection cases + negative cases |
| `UnitConverterTests.swift` | Round-trip conversions for each category |
| `CurrencyServiceTests.swift` | Cache hit, cache miss, stale-data label, API failure paths |
