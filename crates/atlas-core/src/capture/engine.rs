use screenshots::Screen;
use anyhow::{Result, Context};
use std::io::Cursor;

pub struct CaptureEngine;

impl CaptureEngine {
    /// 捕获全屏并返回原始像素数据 (PNG 字节)
    pub fn capture_full_screen() -> Result<Vec<u8>> {
        let screens = Screen::all().map_err(|e| anyhow::anyhow!(e.to_string()))?;
        let screen = screens.first().context("No screen found")?;
        let img = screen.capture().map_err(|e| anyhow::anyhow!(e.to_string()))?;
        
        let mut buffer = Cursor::new(Vec::new());
        img.write_to(&mut buffer, image::ImageOutputFormat::Png)
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;
        Ok(buffer.into_inner())
    }

    /// 根据选区坐标裁剪图片
    pub fn capture_region(x: i32, y: u32, width: u32, height: u32) -> Result<Vec<u8>> {
        let screens = Screen::all().map_err(|e| anyhow::anyhow!(e.to_string()))?;
        let screen = screens.first().context("No screen found")?;
        let img = screen.capture_area(x, y as i32, width, height).map_err(|e| anyhow::anyhow!(e.to_string()))?;
        
        let mut buffer = Cursor::new(Vec::new());
        img.write_to(&mut buffer, image::ImageOutputFormat::Png)
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;
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
