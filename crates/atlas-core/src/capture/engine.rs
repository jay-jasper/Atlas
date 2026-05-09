use screenshots::Screen;
use anyhow::{Result, Context};
use std::io::Cursor;

pub struct CaptureEngine;

impl CaptureEngine {
    /// Captures the full screen and returns raw pixel data (PNG bytes).
    ///
    /// # Note
    /// Currently, this only supports the primary monitor (the first screen found).
    pub fn capture_full_screen() -> Result<Vec<u8>> {
        let screens = Screen::all().map_err(|e| anyhow::anyhow!("Failed to retrieve screens: {}", e))?;
        let screen = screens.first().context("No monitor found to capture")?;
        let img = screen.capture().map_err(|e| anyhow::anyhow!("Failed to capture screen: {}", e))?;
        
        let mut buffer = Cursor::new(Vec::new());
        img.write_to(&mut buffer, image::ImageOutputFormat::Png)
            .context("Failed to encode screen capture to PNG")?;
        Ok(buffer.into_inner())
    }

    /// Captures a specific region of the screen and returns raw pixel data (PNG bytes).
    ///
    /// # Note
    /// Currently, this only supports the primary monitor (the first screen found).
    pub fn capture_region(x: i32, y: i32, width: u32, height: u32) -> Result<Vec<u8>> {
        let screens = Screen::all().map_err(|e| anyhow::anyhow!("Failed to retrieve screens: {}", e))?;
        let screen = screens.first().context("No monitor found to capture")?;
        let img = screen.capture_area(x, y, width, height)
            .map_err(|e| anyhow::anyhow!("Failed to capture region ({}, {}, {}, {}): {}", x, y, width, height, e))?;
        
        let mut buffer = Cursor::new(Vec::new());
        img.write_to(&mut buffer, image::ImageOutputFormat::Png)
            .context("Failed to encode region capture to PNG")?;
        Ok(buffer.into_inner())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_capture_full_screen_exists() {
        // In CI environment, Screen::all() might be empty or fail.
        // We just want to ensure the method exists and can be called.
        let result = CaptureEngine::capture_full_screen();
        if let Err(e) = result {
            println!("Capture failed as expected in headless environment: {}", e);
        }
    }

    #[test]
    fn test_capture_region_exists() {
        let result = CaptureEngine::capture_region(0, 0, 100, 100);
        if let Err(e) = result {
            println!("Capture region failed as expected in headless environment: {}", e);
        }
    }
}
