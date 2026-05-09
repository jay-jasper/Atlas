pub struct AtlasCore {
    pub version: String,
}

impl AtlasCore {
    pub fn new() -> Self {
        Self {
            version: "0.1.0".to_string(),
        }
    }

    pub fn get_status(&self) -> String {
        format!("Atlas Core v{} is running", self.version)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_core_status() {
        let core = AtlasCore::new();
        assert_eq!(core.get_status(), "Atlas Core v0.1.0 is running");
    }
}
