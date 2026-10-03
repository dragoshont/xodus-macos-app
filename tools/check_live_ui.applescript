-- SPDX-License-Identifier: GPL-3.0-only
on run arguments
    if (count of arguments) is not 2 then error "Usage: exact-owned-app-PID snapshot|Library|Discover|Downloads|Account"
    set ownedPID to (item 1 of arguments) as integer
    set requestedAction to item 2 of arguments
    if requestedAction is not in {"snapshot", "Library", "Discover", "Downloads", "Account"} then error "Unsupported action."
    set navigationIDs to {"xodus.navigation.library", "xodus.navigation.discover", "xodus.navigation.downloads", "xodus.account"}
    set safeLabels to {"Library", "Discover", "Downloads", "Account", "Your Library", "Registered on this Mac", "Live Xodus connection - development build", "Xodus for Mac - development build", "Connect your Xodus engine", "Check your saved sign-in or sign in with Microsoft. Public browsing does not read your Keychain."}
    tell application "System Events"
        set ownedProcesses to every application process whose unix id is ownedPID
        if (count of ownedProcesses) is not 1 then error "Exact owned process unavailable."
        set ownedProcess to item 1 of ownedProcesses
        if bundle identifier of ownedProcess is not "io.github.dragoshont.xodus.development" then error "Unexpected bundle identity."
        set ownedWindows to every window of ownedProcess whose name is "Xodus"
        if (count of ownedWindows) is not 1 then error "Expected exactly one normal, non-fixture Xodus window."
        set ownedWindow to item 1 of ownedWindows
        set elements to entire contents of ownedWindow
        if (count of elements) > 3000 then error "Accessibility bound exceeded."
        set navigationMatches to {}
        repeat with element in elements
            if exists attribute "AXIdentifier" of element then
                set identifier to value of attribute "AXIdentifier" of element
                if identifier is in navigationIDs then
                    if role of element is not "AXButton" then error "Navigation identifier is not an actionable button."
                    log ("navigation=" & identifier)
                    if requestedAction is not "snapshot" and identifier is my targetIdentifier(requestedAction) then
                        set end of navigationMatches to contents of element
                    end if
                end if
            end if
            repeat with fieldName in {"AXTitle", "AXDescription", "AXValue"}
                if exists attribute (fieldName as text) of element then
                    set labelValue to value of attribute (fieldName as text) of element
                    if class of labelValue is text and labelValue is in safeLabels then log ("safe-label=" & labelValue)
                end if
            end repeat
        end repeat
        if requestedAction is not "snapshot" then
            if (count of navigationMatches) is not 1 then error "Exact navigation target unavailable; refusing blind interaction."
            set navigationTarget to item 1 of navigationMatches
            if not enabled of navigationTarget then error "Navigation target is disabled."
            click navigationTarget
            log ("clicked=" & requestedAction)
        end if
    end tell
end run

on targetIdentifier(destination)
    if destination is "Library" then return "xodus.navigation.library"
    if destination is "Discover" then return "xodus.navigation.discover"
    if destination is "Downloads" then return "xodus.navigation.downloads"
    if destination is "Account" then return "xodus.account"
    error "Unknown destination."
end targetIdentifier
