use atlas_plugin_builder::Builder;
use std::path::Path;

pub fn run(extension: &Path, json: bool) -> Result<bool, String> {
    let report = Builder::default()
        .inspect(extension)
        .map_err(|error| error.to_string())?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&report).map_err(|error| error.to_string())?
        );
    } else if report.findings.is_empty() {
        println!("compatible: no findings");
    } else {
        for finding in &report.findings {
            println!("{:?} {}: {}", finding.status, finding.code, finding.message);
        }
    }
    Ok(report.is_compatible())
}
