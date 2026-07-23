//! WASM execution host (Phase α runtime, #56) — loads and runs Track A plugin
//! modules via wasmtime. This is the real engine; the WIT component bindings and
//! richer host-API surface layer on top.

use std::sync::mpsc;
use std::time::Duration;

use wasmtime::{
    Config, Engine, Instance, Module, Store, StoreLimits, StoreLimitsBuilder, TypedFunc, Val,
};

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
    #[error("serialized runtime output is {actual} bytes, exceeding {limit}")]
    OutputTooLarge { actual: usize, limit: usize },
    #[error("serialized runtime memory access is outside the module memory")]
    MemoryBounds,
}

#[derive(Debug, Clone, Copy)]
pub struct WasmLimits {
    pub max_memory_bytes: usize,
    pub fuel_per_call: u64,
    pub call_timeout: Duration,
}

impl Default for WasmLimits {
    fn default() -> Self {
        Self {
            max_memory_bytes: 64 * 1024 * 1024,
            fuel_per_call: 10_000_000,
            call_timeout: Duration::from_secs(2),
        }
    }
}

struct HostState {
    limits: StoreLimits,
}

/// A loaded, instantiated WASM plugin module.
pub struct WasmHost {
    engine: Engine,
    store: Store<HostState>,
    instance: Instance,
    limits: WasmLimits,
}

impl WasmHost {
    /// Compiles and instantiates a module from `.wasm` bytes (no imports).
    pub fn load(bytes: &[u8]) -> Result<Self, WasmError> {
        Self::load_with_limits(bytes, WasmLimits::default())
    }

    pub fn load_with_limits(bytes: &[u8], limits: WasmLimits) -> Result<Self, WasmError> {
        let mut config = Config::new();
        config.consume_fuel(true);
        config.epoch_interruption(true);
        let engine = Engine::new(&config).map_err(|e| WasmError::Compile(e.to_string()))?;
        let module = Module::new(&engine, bytes).map_err(|e| WasmError::Compile(e.to_string()))?;
        let store_limits = StoreLimitsBuilder::new()
            .memory_size(limits.max_memory_bytes)
            .instances(1)
            .memories(1)
            .build();
        let mut store = Store::new(
            &engine,
            HostState {
                limits: store_limits,
            },
        );
        store.limiter(|state| &mut state.limits);
        store
            .set_fuel(limits.fuel_per_call)
            .map_err(|e| WasmError::Instantiate(e.to_string()))?;
        store.set_epoch_deadline(1);
        let instance = Instance::new(&mut store, &module, &[])
            .map_err(|e| WasmError::Instantiate(e.to_string()))?;
        Ok(Self {
            engine,
            store,
            instance,
            limits,
        })
    }

    fn prepare_call(&mut self) -> Result<mpsc::Sender<()>, WasmError> {
        self.store
            .set_fuel(self.limits.fuel_per_call)
            .map_err(|e| WasmError::Trap(e.to_string()))?;
        self.store.set_epoch_deadline(1);
        let (cancel, receiver) = mpsc::channel();
        let engine = self.engine.clone();
        let timeout = self.limits.call_timeout;
        std::thread::spawn(move || {
            if receiver.recv_timeout(timeout).is_err() {
                engine.increment_epoch();
            }
        });
        Ok(cancel)
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
        let cancel = self.prepare_call()?;
        let result = func
            .call(&mut self.store, (a, b))
            .map_err(|e| WasmError::Trap(e.to_string()));
        let _ = cancel.send(());
        result
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
        let cancel = self.prepare_call()?;
        let result = func
            .call(&mut self.store, &params, &mut results)
            .map_err(|e| WasmError::Trap(e.to_string()));
        let _ = cancel.send(());
        result?;
        Ok(results.first().and_then(|v| v.i32()).unwrap_or(0))
    }

    /// Bounded serialized ABI used by the out-of-process Runner. The module
    /// exports `memory`, `atlas_alloc(i32) -> i32`, and a handler
    /// `(i32, i32) -> i64`; the handler packs output pointer in the high 32
    /// bits and output length in the low 32 bits.
    pub fn call_serialized(
        &mut self,
        name: &str,
        input: &[u8],
        max_output_bytes: usize,
    ) -> Result<Vec<u8>, WasmError> {
        let memory = self
            .instance
            .get_memory(&mut self.store, "memory")
            .ok_or_else(|| WasmError::MissingExport("memory".into()))?;
        let allocate: TypedFunc<i32, i32> = self
            .instance
            .get_typed_func(&mut self.store, "atlas_alloc")
            .map_err(|_| WasmError::MissingExport("atlas_alloc".into()))?;
        let handler: TypedFunc<(i32, i32), i64> = self
            .instance
            .get_typed_func(&mut self.store, name)
            .map_err(|_| WasmError::MissingExport(name.into()))?;

        let input_len = i32::try_from(input.len()).map_err(|_| WasmError::MemoryBounds)?;
        let cancel = self.prepare_call()?;
        let input_ptr = allocate
            .call(&mut self.store, input_len)
            .map_err(|error| WasmError::Trap(error.to_string()))?;
        let input_offset = usize::try_from(input_ptr).map_err(|_| WasmError::MemoryBounds)?;
        memory
            .write(&mut self.store, input_offset, input)
            .map_err(|_| WasmError::MemoryBounds)?;
        let packed = handler
            .call(&mut self.store, (input_ptr, input_len))
            .map_err(|error| WasmError::Trap(error.to_string()))?;
        let _ = cancel.send(());

        let packed = packed as u64;
        let output_offset =
            usize::try_from((packed >> 32) as u32).map_err(|_| WasmError::MemoryBounds)?;
        let output_len = usize::try_from(packed as u32).map_err(|_| WasmError::MemoryBounds)?;
        if output_len > max_output_bytes {
            return Err(WasmError::OutputTooLarge {
                actual: output_len,
                limit: max_output_bytes,
            });
        }
        let mut output = vec![0_u8; output_len];
        memory
            .read(&self.store, output_offset, &mut output)
            .map_err(|_| WasmError::MemoryBounds)?;
        Ok(output)
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
        assert!(matches!(
            host.call_i32("nope", 1, 1),
            Err(WasmError::MissingExport(_))
        ));
    }

    #[test]
    fn invalid_wasm_errors() {
        assert!(matches!(
            WasmHost::load(b"not wasm"),
            Err(WasmError::Compile(_))
        ));
    }

    #[test]
    fn trap_is_reported() {
        // A function that divides by zero traps at runtime.
        let module = wasm(
            r#"(module (func (export "boom") (param i32 i32) (result i32)
                 local.get 0 local.get 1 i32.div_s))"#,
        );
        let mut host = WasmHost::load(&module).unwrap();
        assert!(matches!(
            host.call_i32("boom", 1, 0),
            Err(WasmError::Trap(_))
        ));
    }

    #[test]
    fn rejects_memory_over_limit() {
        let module = wasm("(module (memory 2000))");
        assert!(matches!(
            WasmHost::load_with_limits(
                &module,
                WasmLimits {
                    max_memory_bytes: 1024 * 1024,
                    ..WasmLimits::default()
                }
            ),
            Err(WasmError::Instantiate(_))
        ));
    }

    #[test]
    fn fuel_interrupts_infinite_loop() {
        let module = wasm("(module (func (export \"loop\") (loop br 0)))");
        let mut host = WasmHost::load_with_limits(
            &module,
            WasmLimits {
                fuel_per_call: 10_000,
                call_timeout: Duration::from_millis(100),
                ..WasmLimits::default()
            },
        )
        .unwrap();
        assert!(matches!(
            host.call_dynamic("loop", &[]),
            Err(WasmError::Trap(_))
        ));
    }

    #[test]
    fn bounded_serialized_event_abi_reads_runtime_output() {
        let output = br#"[{"type":"ui-close"}]"#;
        let escaped: String = output.iter().map(|byte| format!("\\{byte:02x}")).collect();
        let module = wasm(&format!(
            r#"
            (module
              (memory (export "memory") 1)
              (data (i32.const 1024) "{escaped}")
              (func (export "atlas_alloc") (param i32) (result i32) i32.const 0)
              (func (export "atlas_start") (param i32 i32) (result i64)
                i64.const {}))
            "#,
            ((1024_u64) << 32) | output.len() as u64
        ));
        let mut host = WasmHost::load(&module).unwrap();
        assert_eq!(
            host.call_serialized("atlas_start", b"{}", 1024).unwrap(),
            output
        );
        assert!(matches!(
            host.call_serialized("atlas_start", b"{}", 4),
            Err(WasmError::OutputTooLarge { .. })
        ));
    }
}
