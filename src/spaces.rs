use std::process::Command;
use std::thread;
use std::time::Duration;

/// Switches the active macOS Space to the specified number without using keyboard shortcuts.
///
/// This works by temporarily triggering Mission Control, programmatically clicking
/// the requested desktop thumbnail, and letting Mission Control close.
pub fn switch_space_no_shortcuts(space_number: u8) -> Result<(), String> {
    // We construct an AppleScript that:
    // 1. Opens Mission Control
    // 2. Finds the list of Spaces (groups) in the Dock process
    // 3. Clicks the button corresponding to our target space number
    let script = format!(
        r#"
        tell application "System Events"
            -- Trigger Mission Control
            do shell script "open -a 'Mission Control'"

            -- Small delay to let the Mission Control UI render
            delay 0.1

            tell process "Dock"
                try
                    -- Navigate the Mission Control UI hierarchy to find the spaces list
                    set spacesList to groups of list 1 of group 1

                    -- Click the button for the requested space number
                    click button {space_number} of item 1 of spacesList
                on error errMsg
                    log errMsg
                end try
            end tell
        end tell
        "#
    );

    let output = Command::new("osascript")
        .arg("-e")
        .arg(&script)
        .output()
        .map_err(|e| format!("Failed to execute osascript: {}", e))?;

    if output.status.success() {
        Ok(())
    } else {
        let error = String::from_utf8_lossy(&output.stderr);
        Err(format!("AppleScript execution failed: {}", error))
    }
}
