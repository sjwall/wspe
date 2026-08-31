use std::process::Command;

/// Switches the active macOS Space to the specified number without using keyboard shortcuts.
///
/// This works by temporarily triggering Mission Control, programmatically clicking
/// the requested desktop thumbnail, and letting Mission Control close.
pub fn switch_space_no_shortcuts(space_number: u8) -> Result<(), String> {
    let target_space = if space_number == 0 {
        10
    } else {
        space_number
    };

    let script = format!(
        r#"
        tell application "Mission Control" to launch
        delay 0.4

        tell application "System Events"
            tell process "Dock"
                set clicked to false

                -- Strategy 1: Match by description or name (e.g., "Desktop 2", "Space 2")
                try
                    tell list 1 of group 2 of group 1 of group 1
                        set matchedItems to (every UI element whose description contains "{target_space}" or name contains "{target_space}")
                        if (count of matchedItems) > 0 then
                            click item 1 of matchedItems
                            set clicked to true
                        end if
                    end tell
                end try

                -- Strategy 2: Click by UI element index in standard Spaces bar
                if not clicked then
                    try
                        click UI element {target_space} of list 1 of group 2 of group 1 of group 1
                        set clicked to true
                    on error
                        try
                            click button 1 of UI element {target_space} of list 1 of group 2 of group 1 of group 1
                            set clicked to true
                        end try
                    end try
                end if

                -- Strategy 3: Click button directly by index
                if not clicked then
                    try
                        click button {target_space} of list 1 of group 2 of group 1 of group 1
                        set clicked to true
                    end try
                end if

                -- Strategy 4: Fallback for alternate hierarchy (group 1 of group 1)
                if not clicked then
                    try
                        click UI element {target_space} of list 1 of group 1 of group 1
                        set clicked to true
                    on error
                        try
                            click button {target_space} of list 1 of group 1 of group 1
                            set clicked to true
                        end try
                    end try
                end if

                -- If all strategies failed, press Escape to close Mission Control
                if not clicked then
                    key code 53 -- Escape
                    error "Could not switch to desktop space " & {target_space}
                end if
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
        Err(format!("AppleScript execution failed: {}", error.trim()))
    }
}
