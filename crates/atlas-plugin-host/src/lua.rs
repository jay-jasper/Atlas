//! Real Lua scripting engine (Hammerspoon-style bridge, #55) backed by mlua
//! (vendored Lua 5.4 — no system dependency). Host actions are registered into
//! an `atlas` table; user scripts get full Lua (variables, control flow,
//! functions) and call back into Atlas through it.

use std::sync::{Arc, Mutex};

use mlua::{Lua, MultiValue, Value as LuaValue};

#[derive(Debug, thiserror::Error)]
pub enum LuaError {
    #[error("lua error: {0}")]
    Runtime(String),
}

/// A registered host command: takes string args, returns a string result.
pub type HostCommand = Arc<dyn Fn(Vec<String>) -> String + Send + Sync>;

/// An embedded Lua engine exposing Atlas host actions as `atlas.<name>(...)`.
pub struct LuaEngine {
    lua: Lua,
    /// Records what scripts invoked, for observability/testing.
    log: Arc<Mutex<Vec<String>>>,
}

impl LuaEngine {
    pub fn new() -> Self {
        Self {
            lua: Lua::new(),
            log: Arc::new(Mutex::new(Vec::new())),
        }
    }

    /// Registers `atlas.<name>(...)` callable from Lua. Args are coerced to
    /// strings; the return value is exposed back to Lua as a string.
    pub fn register(&self, name: &str, command: HostCommand) -> Result<(), LuaError> {
        let log = self.log.clone();
        let name_owned = name.to_string();
        let func = self
            .lua
            .create_function(move |_, args: MultiValue| {
                let string_args: Vec<String> = args
                    .into_iter()
                    .map(|v| match v {
                        LuaValue::String(s) => s.to_string_lossy().to_string(),
                        LuaValue::Integer(i) => i.to_string(),
                        LuaValue::Number(n) => n.to_string(),
                        LuaValue::Boolean(b) => b.to_string(),
                        other => format!("{other:?}"),
                    })
                    .collect();
                log.lock().unwrap().push(format!("{name_owned}({})", string_args.join(",")));
                Ok(command(string_args))
            })
            .map_err(|e| LuaError::Runtime(e.to_string()))?;

        let atlas = self.atlas_table()?;
        atlas.set(name, func).map_err(|e| LuaError::Runtime(e.to_string()))?;
        Ok(())
    }

    /// Runs a Lua script, returning its result coerced to a string.
    pub fn run(&self, script: &str) -> Result<String, LuaError> {
        let value: LuaValue = self
            .lua
            .load(script)
            .eval()
            .map_err(|e| LuaError::Runtime(e.to_string()))?;
        Ok(match value {
            LuaValue::String(s) => s.to_string_lossy().to_string(),
            LuaValue::Integer(i) => i.to_string(),
            LuaValue::Number(n) => n.to_string(),
            LuaValue::Boolean(b) => b.to_string(),
            LuaValue::Nil => String::new(),
            other => format!("{other:?}"),
        })
    }

    /// The commands this run invoked, in order.
    pub fn invocations(&self) -> Vec<String> {
        self.log.lock().unwrap().clone()
    }

    fn atlas_table(&self) -> Result<mlua::Table, LuaError> {
        let globals = self.lua.globals();
        if let Ok(table) = globals.get::<_, mlua::Table>("atlas") {
            return Ok(table);
        }
        let table = self.lua.create_table().map_err(|e| LuaError::Runtime(e.to_string()))?;
        globals.set("atlas", &table).map_err(|e| LuaError::Runtime(e.to_string()))?;
        Ok(table)
    }
}

impl Default for LuaEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runs_basic_lua_with_variables_and_arithmetic() {
        let engine = LuaEngine::new();
        assert_eq!(engine.run("local x = 6 * 7 return x").unwrap(), "42");
    }

    #[test]
    fn supports_control_flow_and_loops() {
        let engine = LuaEngine::new();
        let script = r#"
            local sum = 0
            for i = 1, 10 do sum = sum + i end
            return sum
        "#;
        assert_eq!(engine.run(script).unwrap(), "55");
    }

    #[test]
    fn calls_registered_host_command() {
        let engine = LuaEngine::new();
        engine
            .register("notify", Arc::new(|args| format!("notified: {}", args.join(" "))))
            .unwrap();
        let result = engine.run(r#"return atlas.notify("hello", "world")"#).unwrap();
        assert_eq!(result, "notified: hello world");
        assert_eq!(engine.invocations(), vec!["notify(hello,world)".to_string()]);
    }

    #[test]
    fn host_command_inside_lua_logic() {
        let engine = LuaEngine::new();
        let calls = Arc::new(Mutex::new(0));
        let calls2 = calls.clone();
        engine
            .register("tick", Arc::new(move |_| {
                *calls2.lock().unwrap() += 1;
                "ok".into()
            }))
            .unwrap();
        engine.run("for i = 1, 3 do atlas.tick() end").unwrap();
        assert_eq!(*calls.lock().unwrap(), 3);
    }

    #[test]
    fn syntax_error_is_reported() {
        let engine = LuaEngine::new();
        assert!(matches!(engine.run("this is not lua !!"), Err(LuaError::Runtime(_))));
    }
}
