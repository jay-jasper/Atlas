//! WASM execution host (Phase α runtime, #56) — loads and runs Track A plugin
//! modules via wasmtime. This is the real engine; the WIT component bindings and
//! richer host-API surface layer on top.

use wasmtime::{Engine, Instance, Module, Store, TypedFunc, Val};

#[derive(Debug, thiserror::Error)]
pub enum WasmError {
    #[error("failed to compile WASM module: {0}")]
    Compile(String),
    #[error("failed to instantiate module: {0}")]
    Instantiate(String),
    #[error("export '{0}' not found")]
    MissingExport(String),
    #[error("trap during execution: {0}")]
    Trap(String),
}

/// A loaded, instantiated WASM plugin module.
pub struct WasmHost {
    store: Store<()>,
    instance: Instance,
}

impl WasmHost {
    /// Compiles and instantiates a module from `.wasm` bytes (no imports).
    pub fn load(bytes: &[u8]) -> Result<Self, WasmError> {
        let engine = Engine::default();
        let module = Module::new(&engine, bytes).map_err(|e| WasmError::Compile(e.to_string()))?;
        let mut store = Store::new(&engine, ());
        let instance = Instance::new(&mut store, &module, &[])
            .map_err(|e| WasmError::Instantiate(e.to_string()))?;
        Ok(Self { store, instance })
    }

    /// Returns the names of all exported functions.
    pub fn exported_functions(&mut self) -> Vec<String> {
        let exports: Vec<String> = self
            .instance
            .exports(&mut self.store)
            .filter(|e| e.clone().into_func().is_some())
            .map(|e| e.name().to_string())
            .collect();
        exports
    }

    /// Calls an exported `(i32, i32) -> i32` function (the common plugin shape
    /// for fixed-arity numeric entry points).
    pub fn call_i32(&mut self, name: &str, a: i32, b: i32) -> Result<i32, WasmError> {
        let func: TypedFunc<(i32, i32), i32> = self
            .instance
            .get_typed_func(&mut self.store, name)
            .map_err(|_| WasmError::MissingExport(name.to_string()))?;
        func.call(&mut self.store, (a, b))
            .map_err(|e| WasmError::Trap(e.to_string()))
    }

    /// Calls an exported function dynamically with i32 args, returning the first
    /// i32 result (or 0 for void).
    pub fn call_dynamic(&mut self, name: &str, args: &[i32]) -> Result<i32, WasmError> {
        let func = self
            .instance
            .get_func(&mut self.store, name)
            .ok_or_else(|| WasmError::MissingExport(name.to_string()))?;
        let params: Vec<Val> = args.iter().map(|a| Val::I32(*a)).collect();
        let mut results = vec![Val::I32(0)];
        func.call(&mut self.store, &params, &mut results)
            .map_err(|e| WasmError::Trap(e.to_string()))?;
        Ok(results.first().and_then(|v| v.i32()).unwrap_or(0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wasm(wat: &str) -> Vec<u8> {
        wat::parse_str(wat).expect("valid wat")
    }

    const ADD_MODULE: &str = r#"
        (module
          (func (export "add") (param i32 i32) (result i32)
            local.get 0
            local.get 1
            i32.add)
          (func (export "mul") (param i32 i32) (result i32)
            local.get 0
            local.get 1
            i32.mul))
    "#;

    #[test]
    fn loads_and_calls_exported_function() {
        let mut host = WasmHost::load(&wasm(ADD_MODULE)).unwrap();
        assert_eq!(host.call_i32("add", 2, 3).unwrap(), 5);
        assert_eq!(host.call_i32("mul", 4, 5).unwrap(), 20);
    }

    #[test]
    fn lists_exported_functions() {
        let mut host = WasmHost::load(&wasm(ADD_MODULE)).unwrap();
        let mut exports = host.exported_functions();
        exports.sort();
        assert_eq!(exports, vec!["add".to_string(), "mul".to_string()]);
    }

    #[test]
    fn dynamic_call() {
        let mut host = WasmHost::load(&wasm(ADD_MODULE)).unwrap();
        assert_eq!(host.call_dynamic("add", &[10, 20]).unwrap(), 30);
    }

    #[test]
    fn missing_export_errors() {
        let mut host = WasmHost::load(&wasm(ADD_MODULE)).unwrap();
        assert!(matches!(host.call_i32("nope", 1, 1), Err(WasmError::MissingExport(_))));
    }

    #[test]
    fn invalid_wasm_errors() {
        assert!(matches!(WasmHost::load(b"not wasm"), Err(WasmError::Compile(_))));
    }

    #[test]
    fn trap_is_reported() {
        // A function that divides by zero traps at runtime.
        let module = wasm(
            r#"(module (func (export "boom") (param i32 i32) (result i32)
                 local.get 0 local.get 1 i32.div_s))"#,
        );
        let mut host = WasmHost::load(&module).unwrap();
        assert!(matches!(host.call_i32("boom", 1, 0), Err(WasmError::Trap(_))));
    }
}
