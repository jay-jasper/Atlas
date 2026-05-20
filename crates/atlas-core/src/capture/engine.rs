use anyhow::{Context, Result};
use image::RgbaImage;
use screenshots::Screen;
use std::io::Cursor;

pub struct CaptureEngine;

struct CapturedDisplay {
    x: i32,
    y: i32,
    image: RgbaImage,
}

impl CaptureEngine {
    /// Captures the desktop across all available displays and returns PNG bytes.
    pub fn capture_full_screen() -> Result<Vec<u8>> {
        let screens =
            Screen::all().map_err(|e| anyhow::anyhow!("Failed to retrieve screens: {}", e))?;
        if screens.is_empty() {
            anyhow::bail!("No monitor found to capture");
        }

        let displays = screens
            .iter()
            .map(|screen| {
                let img = screen.capture().map_err(|e| {
                    anyhow::anyhow!("Failed to capture screen {}: {}", screen.display_info.id, e)
                })?;

                Ok(CapturedDisplay {
                    x: screen.display_info.x,
                    y: screen.display_info.y,
                    image: img,
                })
            })
            .collect::<Result<Vec<_>>>()?;

        let img = compose_displays(&displays)?;

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
        let screens =
            Screen::all().map_err(|e| anyhow::anyhow!("Failed to retrieve screens: {}", e))?;
        let screen = screens.first().context("No monitor found to capture")?;
        let img = screen.capture_area(x, y, width, height).map_err(|e| {
            anyhow::anyhow!(
                "Failed to capture region ({}, {}, {}, {}): {}",
                x,
                y,
                width,
                height,
                e
            )
        })?;

        let mut buffer = Cursor::new(Vec::new());
        img.write_to(&mut buffer, image::ImageOutputFormat::Png)
            .context("Failed to encode region capture to PNG")?;
        Ok(buffer.into_inner())
    }
}

fn compose_displays(displays: &[CapturedDisplay]) -> Result<RgbaImage> {
    let first = displays.first().context("No monitor found to capture")?;
    let mut min_x = first.x;
    let mut min_y = first.y;
    let mut max_x = display_max_x(first)?;
    let mut max_y = display_max_y(first)?;

    for display in &displays[1..] {
        min_x = min_x.min(display.x);
        min_y = min_y.min(display.y);
        max_x = max_x.max(display_max_x(display)?);
        max_y = max_y.max(display_max_y(display)?);
    }

    let width = u32::try_from(max_x - min_x).context("Invalid desktop capture width")?;
    let height = u32::try_from(max_y - min_y).context("Invalid desktop capture height")?;
    let mut desktop = RgbaImage::new(width, height);

    for display in displays {
        let offset_x = u32::try_from(display.x - min_x).context("Invalid display x offset")?;
        let offset_y = u32::try_from(display.y - min_y).context("Invalid display y offset")?;

        for (x, y, pixel) in display.image.enumerate_pixels() {
            desktop.put_pixel(offset_x + x, offset_y + y, *pixel);
        }
    }

    Ok(desktop)
}

fn display_max_x(display: &CapturedDisplay) -> Result<i32> {
    let width = i32::try_from(display.image.width()).context("Display width is too large")?;
    display
        .x
        .checked_add(width)
        .context("Display x coordinate overflow")
}

fn display_max_y(display: &CapturedDisplay) -> Result<i32> {
    let height = i32::try_from(display.image.height()).context("Display height is too large")?;
    display
        .y
        .checked_add(height)
        .context("Display y coordinate overflow")
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    #[test]
    fn test_compose_displays_uses_virtual_desktop_bounds() {
        let left = solid_display(-2, 0, 2, 2, [255, 0, 0, 255]);
        let right = solid_display(0, 1, 3, 1, [0, 255, 0, 255]);

        let image = compose_displays(&[left, right]).unwrap();

        assert_eq!(image.width(), 5);
        assert_eq!(image.height(), 2);
        assert_eq!(image.get_pixel(0, 0), &Rgba([255, 0, 0, 255]));
        assert_eq!(image.get_pixel(1, 1), &Rgba([255, 0, 0, 255]));
        assert_eq!(image.get_pixel(2, 1), &Rgba([0, 255, 0, 255]));
        assert_eq!(image.get_pixel(4, 1), &Rgba([0, 255, 0, 255]));
    }

    #[test]
    fn test_compose_displays_returns_error_for_empty_inputs() {
        assert!(compose_displays(&[]).is_err());
    }

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
            println!(
                "Capture region failed as expected in headless environment: {}",
                e
            );
        }
    }

    fn solid_display(x: i32, y: i32, width: u32, height: u32, rgba: [u8; 4]) -> CapturedDisplay {
        CapturedDisplay {
            x,
            y,
            image: RgbaImage::from_pixel(width, height, Rgba(rgba)),
        }
    }
}
