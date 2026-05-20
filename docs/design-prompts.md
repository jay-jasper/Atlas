# Atlas Design Prompts

This document records two copy-ready English prompts for design generation tools: one for Stitch and one for Figma. Both prompts describe the current Atlas product surface in detail and leave room for future modules such as OCR, translation, window management, AI Agent skills, Privacy Pulse, clipboard history, and workspace automation.

## Stitch Prompt

```text
Design a complete high-fidelity macOS menu bar app UI for Atlas.

Atlas is an AI-native desktop layer: a lightweight local-first utility that replaces many small tools with one modular menu bar app. The current product includes screenshot capture, screenshot editing, system monitoring, Port Master, and feature toggles. Future modules include OCR, universal translation, window layout management, clipboard history, scratchpad notes, AI Agent skills, Privacy Pulse, presentation mode, and display controls.

The output should be a real app experience, not a landing page. Start with the menu bar popover as the first screen.

Product principles:
- Native macOS utility, compact and fast.
- Local-first and privacy-aware by default.
- Modular: disabled features should look available but inactive, and enabled features should appear as live sections.
- Built for frequent use by developers, designers, and AI power users.
- Information-dense but calm, with clear hierarchy and no marketing layout.

Overall visual style:
- macOS-native appearance with SF Pro-style typography, SF Symbols-style icons, material surfaces, subtle separators, compact controls, and restrained color.
- Use neutral grays as the base. Use blue for primary actions and healthy progress, green for success/network upload, orange for warning, red for destructive/error/high usage.
- Support both light mode and dark mode.
- Main popover should feel like a native system utility: 384px wide, 560-680px tall, scrollable content, compact spacing, section dividers, and 6-8px radius.
- Avoid purple-blue gradients, decorative glow blobs, illustrations, hero headlines, oversized cards, and web dashboard styling.
- All text must remain readable and fit within a 360-384px panel.

Core screens to generate:

1. Menu Bar Popover - Default Ready State
- Width: around 384px.
- Header:
  - Left: Atlas app name and status text "Atlas is Ready".
  - Right: small icon buttons for settings, privacy, and more menu.
  - A compact status badge, e.g. "Local" or "2 modules active".
- Content sections:
  - Screenshot.
  - Monitoring.
  - Port Master.
  - Features.
  - Footer.
- Use dividers and spacing instead of large nested cards.
- The first viewport should show the header, Screenshot section, and the beginning of Monitoring.

2. Header More Menu Dropdown
- Triggered from a three-dot or chevron icon in the header.
- Menu items:
  - Open Atlas Window
  - Preferences
  - Privacy Pulse
  - Check Permissions
  - Restart Background Services
  - About Atlas
  - Quit Atlas
- Use macOS menu styling: compact rows, left icons, optional keyboard shortcuts on the right.
- Quit should be separated at the bottom.

3. Screenshot Section
- Section title: Screenshot.
- Primary actions:
  - Area: prominent compact button with selection icon.
  - Full: secondary compact button with screen/window icon.
- Secondary inline actions or dropdown:
  - Recent
  - OCR
  - Translate
  - More
- The More dropdown should include:
  - Capture Area
  - Capture Full Screen
  - Capture Window
  - Timed Capture...
  - Scrolling Capture
  - Record GIF
  - Open Editor
  - Open Screenshots Folder
- Future items such as Scrolling Capture and Record GIF can appear disabled or tagged "Soon".
- Show capture feedback banner below the actions:
  - Success: "Captured 1280×720 px"
  - Success: "Copied screenshot"
  - Error: "Screen Recording permission required"

4. Screenshot Selection Overlay
- Full-screen dim overlay.
- Active selection rectangle with visible border, corner handles, edge handles, and live size label, e.g. "1280 × 720".
- Show a small floating confirmation toolbar attached to the selection:
  - Confirm
  - Copy
  - Save
  - Pin
  - Cancel
- Include optional precision aids:
  - magnifier bubble near cursor
  - subtle crosshair guides
  - pixel color readout
- Keep the overlay minimal and professional.

5. Screenshot Editor Overlay
- Floating editor window around 520×420.
- Background uses macOS material with subtle shadow.
- Top toolbar:
  - Rectangle
  - Arrow
  - Pen
  - Text
  - Highlight
  - Pixelate
  - Blur
  - Color picker
  - Stroke width dropdown
  - Undo
  - Close
- Canvas:
  - Show screenshot preview.
  - Include example annotations: red rectangle, arrow, and pixelated sensitive area.
- Bottom output bar:
  - Copy
  - Save
  - Pin
  - Share dropdown
  - Size label, e.g. "1280 x 720".
- Share dropdown items:
  - Copy PNG
  - Copy Markdown Image
  - Save As...
  - Pin to Screen
  - Send to OCR
  - Translate Selection
  - Analyze with AI
- OCR/Translate/Analyze can appear as future-enabled actions with subtle badges.

6. Monitoring Section - Live State
- Section title: Monitoring.
- CPU card:
  - Total usage percentage.
  - Progress bar.
  - Per-core mini bar chart.
  - Warning color above 80%.
- CPU dropdown/menu:
  - Show All Cores
  - Sort Processes by CPU
  - Copy Snapshot
  - Open Activity Monitor
- Memory card:
  - Used / total.
  - Usage bar.
  - Swap row.
- Network card:
  - Upload and download rates.
  - Interface rows such as en0, bridge0.
  - Dropdown to choose interface:
    - All Interfaces
    - Wi-Fi
    - Ethernet
    - Loopback
- Disk card:
  - Disk name, mount point, used / total, progress.
  - Warning style when usage is high.
- Battery card:
  - Charge, health, cycle count, charging state, time remaining.
- Temperatures card:
  - Label + Celsius.
  - Warning color for high values.
- Top Processes card:
  - Tabs or segmented control: CPU / Memory.
  - Rows: process name, PID, usage.
  - Row action menu:
    - Reveal in Finder
    - Copy PID
    - Inspect
    - Kill Process
- Keep all monitoring cards compact and easy to scan.

7. Monitoring Section - Loading and Disabled States
- Loading:
  - Progress spinner with "Loading monitoring..."
  - Skeleton metric rows.
- Disabled:
  - Compact empty state: "Monitoring is off"
  - Enable Monitoring button.
  - Small explanation: "Background collection starts only when this module is enabled."

8. Port Master Section
- Section title: Port Master.
- Input placeholder: "Port or PID".
- Kill button.
- Lookup button or search icon.
- Result state:
  - Port: 3000
  - PID: 12345
  - Process: node
  - Path or command preview if available.
- Error state:
  - "Invalid input"
  - "No listening process found"
- Destructive confirmation popover:
  - Title: "Kill node?"
  - Body: "This will terminate PID 12345 using SIGKILL."
  - Buttons: Cancel, Kill Process.
- Port dropdown suggestions:
  - 3000 React / Vite
  - 5173 Vite
  - 8000 Local server
  - 8080 API server
  - 5432 PostgreSQL
  - 6379 Redis
- Keep Kill visually clear but not oversized; destructive red only in confirmation or final action.

9. Features Section
- Section title: Features.
- Toggle rows:
  - Screenshot
  - Monitoring
- Future module rows:
  - OCR & Translate
  - Window Layout
  - Clipboard History
  - Scratchpad
  - Agent Skills
  - Privacy Pulse
  - Presentation Mode
  - Display Controls
- Each row should include:
  - Icon
  - Module name
  - One-line secondary description
  - Toggle, disabled badge, or "Soon" badge.
- Feature row dropdown:
  - Enable / Disable
  - Configure
  - Permissions
  - View Logs
  - Reset Module
- Show dependency hint behavior:
  - Enabling "OCR & Translate" may require Screenshot.
  - Show a compact dependency prompt: "Enable Screenshot too?"

10. Preferences Window
- A larger native macOS settings window, not a web page.
- Sidebar categories:
  - General
  - Screenshot
  - Monitoring
  - Port Master
  - Features
  - Privacy
  - AI Providers
  - Shortcuts
  - Advanced
- General:
  - Launch at login
  - Show menu bar status
  - Theme: System / Light / Dark
  - Default panel size
- Screenshot:
  - Default output: Clipboard / File / Editor
  - Save location
  - Capture hotkey
  - Show floating thumbnail
  - Pin screenshots above all windows
- Monitoring:
  - Refresh interval dropdown: 1s, 2s, 5s, 10s
  - Show CPU cores
  - Show top processes
  - Temperature warnings
- Port Master:
  - Favorite ports
  - Require confirmation before kill
  - Show process path
- Privacy:
  - Local-only mode
  - Clear screenshot history
  - Camera/microphone/clipboard access log
- AI Providers:
  - OpenAI
  - Claude
  - Gemini
  - Ollama
  - DeepL
  - API key status badges, without showing full keys.
- Shortcuts:
  - Capture Area
  - Capture Full Screen
  - Open Atlas
  - Toggle Monitoring

11. Privacy Pulse Future Screen
- Compact panel showing recent sensitive access:
  - Screen capture
  - Clipboard
  - Camera
  - Microphone
  - AI provider calls
- Each row includes app/module, timestamp, status, and action menu.
- Include filters:
  - Today
  - 7 days
  - All
  - By Module
- This screen should feel trustworthy, transparent, and understated.

12. Future Workspace / Agent Extensions
- Add small preview surfaces for future modules without overwhelming the app:
  - Window Layout: 3×3 grid selector and saved workspace list.
  - Agent Skills: list of skills with Run button and schedule/trigger badge.
  - Clipboard History: searchable list with text/image rows.
  - Scratchpad: compact markdown note preview with AI summarize action.
- These should look like natural modules inside the same system, not separate products.

Required output:
- Produce high-fidelity UI screens for the main popover, dropdown menus, screenshot overlay, screenshot editor, monitoring states, Port Master confirmation, feature manager, preferences window, and at least one future expansion screen.
- Use consistent components, spacing, typography, icons, and state colors.
- The final design should clearly support growth from the current two enabled modules to a larger modular utility suite.
```

## Figma Prompt

```text
Create a detailed Figma design system and high-fidelity UI for Atlas, a local-first macOS menu bar utility.

Atlas architecture context:
- Rust core + SwiftUI frontend.
- Current implemented/visible modules: Screenshot, Screenshot Editor, Monitoring, Port Master, Feature Toggles.
- Planned modules: OCR & Translate, Window Layout, Clipboard History, Scratchpad, Agent Skills, Privacy Pulse, Presentation Mode, Display Controls, Token/API spend monitoring.
- The design should map cleanly to SwiftUI components and native macOS UI patterns.

Primary design goal:
Design a scalable macOS menu bar utility UI that starts compact but can grow into a modular desktop layer. The design must include detailed screens, dropdown menus, component variants, states, and styling rules.

Design language:
- Native macOS, not web SaaS.
- Use SF Pro-style typography and SF Symbols-style icons.
- Main panel width: 384px.
- Use compact section headers, dividers, 6-8px radius, native controls, subtle material backgrounds.
- Avoid landing-page patterns, giant headings, decorative illustrations, full-page gradients, glow blobs, and oversized cards.
- Use neutral backgrounds and semantic accents:
  - Blue: primary action and normal progress.
  - Green: success and healthy status.
  - Orange: warning.
  - Red: destructive, error, critical usage.
  - Gray: disabled, metadata, inactive modules.
- Provide light mode and dark mode for key frames.

Create these Figma pages:

Page 1: Foundations
- Color styles:
  - Background / Panel / Elevated / Separator.
  - Text Primary / Text Secondary / Text Tertiary / Disabled.
  - Accent Blue / Success Green / Warning Orange / Danger Red.
- Typography styles:
  - Panel Title
  - Section Label
  - Body
  - Caption
  - Metric Value
  - Monospace Value for PID, port, bytes, and hotkeys.
- Effects:
  - Popover shadow
  - Floating editor shadow
  - Focus ring
  - Subtle material surface.
- Spacing tokens:
  - 4, 6, 8, 10, 12, 16.
- Radius tokens:
  - 4 small controls
  - 6 compact buttons
  - 8 metric cards
  - 10 floating editor only.

Page 2: Components
Create reusable components with variants:

1. Header / Atlas Panel Header
- Variants:
  - Ready
  - Busy
  - Permission Required
  - Offline / Local Only
- Elements:
  - Atlas title
  - status subtitle
  - active module badge
  - settings icon
  - privacy icon
  - more icon

2. Status Banner
- Variants:
  - Success
  - Error
  - Warning
  - Info
- Include icon, message, optional action button.
- Example messages:
  - Captured 1280×720 px
  - Copied screenshot
  - Screen Recording permission required
  - Monitoring paused

3. Section Header
- Variants:
  - Plain
  - With action icon
  - With dropdown chevron
  - With "Soon" badge

4. Icon Button
- Variants:
  - Default
  - Hover
  - Pressed
  - Selected
  - Disabled
  - Destructive
- Use native icon button proportions, not large web buttons.

5. Compact Button
- Variants:
  - Primary
  - Secondary
  - Destructive
  - Disabled
  - Icon + label
  - Icon only

6. Dropdown Menu
- Native macOS-style menu component.
- Variants:
  - Header More Menu
  - Screenshot More Menu
  - Share Menu
  - Feature Row Menu
  - Process Row Menu
  - Monitoring Interface Menu
- Include row icons, labels, optional shortcut text, separators, disabled rows, destructive rows.

7. Metric Card
- Variants:
  - CPU
  - Memory
  - Network
  - Disk
  - Battery
  - Temperature
  - Process list
  - Loading skeleton
  - Disabled
- Must support compact content at 384px panel width.

8. Feature Row
- Variants:
  - Enabled
  - Disabled
  - Future / Soon
  - Requires Permission
  - Requires Dependency
- Elements:
  - icon
  - module name
  - short description
  - toggle or badge
  - optional row menu

9. Confirmation Popover
- Variants:
  - Kill Process
  - Enable Dependency
  - Clear History
  - Grant Permission
- Include title, short body, Cancel button, primary/destructive action.

10. Sidebar Settings Row
- Used in Preferences window.
- Variants: selected, default, disabled.

Page 3: Main Popover Screens

Frame: Main Popover - Ready
- Size: 384×640.
- Header:
  - Atlas
  - "Atlas is Ready"
  - badge: "2 modules active"
  - settings, privacy, more buttons.
- Sections:
  - Screenshot with Area and Full buttons.
  - Monitoring live preview.
  - Port Master compact input.
  - Features list.
  - Footer with version and local-first status.

Frame: Main Popover - Screenshot Only
- Monitoring disabled.
- Screenshot section visible.
- Monitoring section collapsed into disabled empty state with Enable button.

Frame: Main Popover - Monitoring Loading
- Screenshot enabled.
- Monitoring section shows spinner and skeleton metric rows.

Frame: Main Popover - Permission Required
- Screenshot section shows warning banner for Screen Recording permission.
- Include "Open System Settings" button.

Frame: Header More Menu Open
- Show menu:
  - Open Atlas Window
  - Preferences
  - Privacy Pulse
  - Check Permissions
  - Restart Background Services
  - About Atlas
  - Quit Atlas

Page 4: Screenshot Flow

Frame: Screenshot Section - More Menu Open
- Menu items:
  - Capture Area
  - Capture Full Screen
  - Capture Window
  - Timed Capture...
  - Scrolling Capture
  - Record GIF
  - Open Editor
  - Open Screenshots Folder
- Mark future items with disabled state or "Soon" badge.

Frame: Selection Overlay
- Full-screen dim overlay.
- Selection rect with handles and size label.
- Floating action toolbar: Confirm, Copy, Save, Pin, Cancel.
- Magnifier bubble and crosshair guides.

Frame: Screenshot Editor Overlay
- Size: 520×420.
- Top toolbar:
  - rectangle
  - arrow
  - pen
  - text
  - highlight
  - pixelate
  - blur
  - color
  - stroke width dropdown
  - undo
  - close
- Canvas with screenshot preview and sample annotations.
- Bottom bar:
  - Copy
  - Save
  - Pin
  - Share
  - dimensions.

Frame: Screenshot Editor - Share Menu Open
- Menu items:
  - Copy PNG
  - Copy Markdown Image
  - Save As...
  - Pin to Screen
  - Send to OCR
  - Translate Selection
  - Analyze with AI
- Use disabled/future state for items that are not current.

Page 5: Monitoring Flow

Frame: Monitoring Live Details
- CPU, Memory, Network, Disk, Battery, Temperatures, Top Processes.
- Include realistic sample values.
- Top Processes uses segmented control: CPU / Memory.

Frame: CPU Menu Open
- Menu:
  - Show All Cores
  - Sort Processes by CPU
  - Copy Snapshot
  - Open Activity Monitor

Frame: Network Interface Dropdown
- Menu:
  - All Interfaces
  - Wi-Fi
  - Ethernet
  - Loopback

Frame: Process Row Action Menu
- Menu:
  - Reveal in Finder
  - Copy PID
  - Inspect
  - Kill Process
- Kill Process should be destructive.

Frame: Monitoring Disabled
- Compact empty state with Enable Monitoring button and text explaining that background collection only runs when enabled.

Page 6: Port Master Flow

Frame: Port Master - Empty
- Input placeholder: Port or PID.
- Lookup icon button.
- Kill button disabled until valid target.

Frame: Port Master - Result
- Show:
  - Port 3000
  - PID 12345
  - Process node
  - command/path preview.
- Actions:
  - Copy PID
  - Reveal
  - Kill.

Frame: Port Master - Suggestions Dropdown
- Suggestions:
  - 3000 React / Vite
  - 5173 Vite
  - 8000 Local server
  - 8080 API server
  - 5432 PostgreSQL
  - 6379 Redis

Frame: Kill Confirmation Popover
- Title: Kill node?
- Body: This will terminate PID 12345 using SIGKILL.
- Buttons: Cancel, Kill Process.

Frame: Port Master - Error
- Error examples:
  - Invalid input
  - No listening process found

Page 7: Feature Manager and Future Modules

Frame: Feature Manager - Current
- Rows:
  - Screenshot: enabled.
  - Monitoring: enabled.
  - OCR & Translate: future or disabled.
  - Window Layout: future or disabled.
  - Clipboard History: future or disabled.
  - Scratchpad: future or disabled.
  - Agent Skills: future or disabled.
  - Privacy Pulse: future or disabled.
  - Presentation Mode: future or disabled.
  - Display Controls: future or disabled.
- Each row has icon, name, description, toggle/badge, and optional menu.

Frame: Feature Row Menu Open
- Menu:
  - Enable / Disable
  - Configure
  - Permissions
  - View Logs
  - Reset Module

Frame: Dependency Prompt
- Example: Enabling OCR & Translate requires Screenshot.
- Title: Enable Screenshot too?
- Buttons: Cancel, Enable Both.

Frame: Future Module Preview
- Show 3 small module previews:
  - Window Layout: 3×3 grid selector and saved workspace row.
  - Agent Skills: skill list row with Run button and trigger badge.
  - Clipboard History: searchable list with text/image rows.
- These previews should feel integrated with the same component system.

Page 8: Preferences Window

Frame: Preferences - General
- Native macOS settings window.
- Sidebar:
  - General
  - Screenshot
  - Monitoring
  - Port Master
  - Features
  - Privacy
  - AI Providers
  - Shortcuts
  - Advanced
- General controls:
  - Launch at login
  - Show menu bar status
  - Theme: System / Light / Dark
  - Default panel size.

Frame: Preferences - Screenshot
- Default output: Clipboard / File / Editor.
- Save location picker.
- Capture hotkey.
- Show floating thumbnail.
- Pin screenshots above all windows.

Frame: Preferences - Monitoring
- Refresh interval dropdown: 1s, 2s, 5s, 10s.
- Show CPU cores.
- Show top processes.
- Temperature warning threshold.

Frame: Preferences - Port Master
- Favorite ports list.
- Require confirmation before kill.
- Show process path.

Frame: Preferences - Privacy
- Local-only mode.
- Clear screenshot history.
- Camera/microphone/clipboard access log.
- Export privacy report.

Frame: Preferences - AI Providers
- Provider rows:
  - OpenAI
  - Claude
  - Gemini
  - Ollama
  - DeepL
- Show connection/API key status badges.
- Do not display full API keys.

Frame: Preferences - Shortcuts
- Shortcut recorder rows:
  - Capture Area
  - Capture Full Screen
  - Open Atlas
  - Toggle Monitoring
  - Open Clipboard History

Page 9: Privacy Pulse

Frame: Privacy Pulse - Activity Log
- Rows:
  - Screen Capture
  - Clipboard
  - Camera
  - Microphone
  - AI Provider Calls
- Each row includes module/app name, timestamp, status, and action menu.
- Filters:
  - Today
  - 7 Days
  - All
  - By Module
- Tone should be trustworthy, transparent, and calm.

Implementation mapping:
- Main popover maps to SwiftUI ContentView.
- Screenshot section maps to ScreenshotPanel.
- Screenshot editor maps to ScreenshotEditorView.
- Monitoring cards map to MonitoringPanel.
- Port Master maps to PortMasterPanel.
- Feature rows map to FeatureTogglePanel.
- Preferences can later map to a separate SwiftUI Settings scene.

Delivery requirements:
- Use clear frame and component names.
- Include component variants for hover, selected, disabled, warning, error, destructive, loading, and future/soon.
- Include both light and dark mode for the main popover, screenshot editor, and preferences window.
- Keep the design scalable: the current app has only a few modules, but the layout must support many future modules without becoming visually noisy.
```
