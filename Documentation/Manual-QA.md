# Manual QA checklist

Use a signed build whose identity matches the intended test build. Record the macOS version, hardware architecture, display arrangement, and result for each item.

## App lifecycle

- [ ] A fresh launch opens onboarding and does not open an unrelated main window.
- [ ] Completing onboarding prevents it from reopening; Reset Onboarding makes it appear on the next launch.
- [ ] Menu bar Open Switcher works without a global shortcut.
- [ ] Pause Shortcuts disables every global binding and Resume restores them.
- [ ] Dock and menu bar visibility settings apply without relaunching.
- [ ] The menu-bar and Dock controls never permit both app entry points to be hidden.
- [ ] Disabling Remember Display Preference restores Pointer Display after relaunch.
- [ ] Launch at Login registers in a Developer ID signed build and reports the correct macOS status.
- [ ] A Launch at Login registration failure rolls the toggle back and shows the failure beside the real system status.
- [ ] Quit removes the overlay and all hotkeys.

## Permissions

- [ ] With both permissions denied, cards show titles/icons, activation degrades safely, and no repeated system prompt appears.
- [ ] Accessibility request and System Settings link open the correct pane.
- [ ] Screen Recording request and System Settings link open the correct pane.
- [ ] Permission status updates after returning from System Settings or restarting when macOS requires it.
- [ ] After previews have been captured, revoking Screen Recording replaces visible and subsequently reopened previews with title/icon fallbacks.
- [ ] Replacing an installed build with a newer build signed by the same certificate retains both permissions.
- [ ] An ad-hoc build displays the development-signature warning in Settings → Permissions.
- [ ] Protected video produces a fallback card rather than a crash or error image.

## Shortcuts

- [ ] Default Option-Tab opens and advances; releasing Tab keeps the overlay open and releasing Option confirms.
- [ ] Option-Shift-Tab moves backward and wraps from first to last.
- [ ] A custom shortcut takes effect immediately without restarting.
- [ ] Clearing a shortcut with Delete unregisters it.
- [ ] A modifierless global shortcut is rejected; modifierless Escape remains valid for local dismissal.
- [ ] Restore Defaults restores all default bindings.
- [ ] Duplicating another OrbitSwitch binding is rejected.
- [ ] Command-Tab, Command-Space, Command-Backtick, and Control-arrow bindings show a warning.
- [ ] A shortcut owned by another utility reports registration failure and leaves the previous shortcut working.
- [ ] If another utility claims a shortcut while OrbitSwitch is paused, Resume fails visibly and OrbitSwitch remains paused.
- [ ] Test at least one non-US keyboard layout and a shortcut involving a punctuation key.
- [ ] Fast repeated presses during overlay preparation select the expected card.

## Overlay and activation

- [ ] With Include minimized on, minimizing a window keeps it in the switcher. Verify specifically with Chrome, whose Accessibility and Core Graphics titles for one window differ — every minimized Chrome window used to be dropped from the switcher entirely.
- [ ] Selecting a minimized window from the switcher un-minimizes and raises it.
- [ ] Return confirms and Escape cancels.
- [ ] Left/up moves backward; right/down and Tab move forward.
- [ ] Mouse wheel and trackpad scrolling move in both directions without excessive repeats.
- [ ] Clicking a background card selects it; clicking the selected card confirms.
- [ ] The selected card uses neutral elevation without an accent-colored outline.
- [ ] Window controls fade in only while the pointer is over the selected card and disappear when it leaves.
- [ ] The bottom position capsule follows selection and wrapping, and stays hidden for zero or one window.
- [ ] Empty, one-window, and thirty-plus-window sets remain usable.
- [ ] With more than sixteen windows open, selecting one past the sixteenth still fills in a preview shortly after it is selected, in both styles.
- [ ] Closing a selected window removes only its card after the window disappears; every surviving card remains visible immediately without another Tab press. Verify in both Orbit and Sidebar. An unsaved-document confirmation keeps the card present.
- [ ] A minimized window restores when macOS exposes it through Accessibility.
- [ ] With Include Minimized enabled, minimized windows appear; with it disabled, they do not.
- [ ] With Accessibility enabled and Current Space Only selected, ordinary windows on another Space remain excluded.
- [ ] Multiple browser and document windows retain approximate front-to-back order.
- [ ] Menu bar, Dock, desktop, tiny panels, and OrbitSwitch windows are absent.
- [ ] Menu-bar-only utilities, agents, and background helpers never appear as switchable windows.
- [ ] Include Hidden Apps and Ignore Transient Utility Panels each change filtering as labeled.
- [ ] Multiple comma-separated excluded bundle identifiers can be typed and applied with Return.
- [ ] Full-screen apps can show the auxiliary overlay and dismiss it cleanly.

## Sidebar style

- [ ] Switching the style in Settings → Appearance takes effect the next time the switcher opens, with no relaunch.
- [ ] The strip appears on the same display the Orbit stack would use for Active, Pointer, and All Displays.
- [ ] All four edges position the strip against that edge and lean the selected tile toward the screen.
- [ ] Left and right stack the tiles in a column; top and bottom lay them out in a row.
- [ ] The background dimming is heaviest at whichever edge the strip is docked to.
- [ ] The strip clears the menu bar, and clears the Dock with the Dock on the left, right, and bottom.
- [ ] Tab keeps cycling past the last tile and wraps to the first; Option-Shift-Tab wraps backward.
- [ ] With more windows than tiles, the strip scrolls to keep the selection visible and the end tiles fade.
- [ ] With fewer windows than the configured count, all tiles show and none are faded.
- [ ] Windows On Screen and Tile Width apply as labeled; a display too small for the requested count shows fewer, not clipped, tiles — check a column on a short display and a row on a narrow one.
- [ ] The position capsule stays with the strip for both few and many windows: past the end of a column, below a top row, above a bottom row.
- [ ] Clicking a tile selects it, clicking the selected tile confirms, and clicking the desktop dismisses.
- [ ] Window controls appear on hover over the selected tile and act on the right window.
- [ ] Scroll and arrow keys move the selection in both directions.
- [ ] Empty, one-window, and thirty-plus-window sets remain usable.
- [ ] Reduce Motion, Reduce Transparency, and Increase Contrast behave as they do in the Orbit style.
- [ ] VoiceOver reads each tile as app name followed by window title.

## Dock peek

- [ ] With Dock Peek off, hovering Dock icons does nothing and no panel ever appears.
- [ ] With Accessibility denied, the Dock Peek tab shows the permission warning and the feature stays inert; granting it starts peek without relaunching.
- [ ] Enabling Dock Peek and resting on a running app's icon opens a panel after the configured hover delay.
- [ ] The panel lists every window of that app, including one parked on another Desktop, one that is minimized, and one belonging to a hidden app.
- [ ] Those three appear even with Include minimized and Include hidden apps switched off and Current Space only switched on under Windows.
- [ ] Clicking a minimized window's preview un-minimizes and raises that window.
- [ ] Minimizing every window of an app still leaves its Dock peek populated.
- [ ] Minimize a Chrome window, then confirm it appears in BOTH the Dock peek and the Tab switcher. Chrome's Accessibility and Core Graphics titles for one window differ, which previously dropped every minimized Chrome window from both. Repeat with an Incognito window and a second Chrome profile.
- [ ] A window excluded by minimum size or by excluded bundle identifier does not appear.
- [ ] Hovering a non-running icon, Trash, a stack, a folder, or a minimized-window Dock item opens nothing.
- [ ] Hovering an app with no eligible windows opens nothing and does not repeatedly re-query while the pointer rests there.
- [ ] Clicking a preview raises that exact window and closes the panel.
- [ ] Hovering a preview reveals the close, minimize, and zoom buttons; each performs its action.
- [ ] Closing a document window with unsaved changes leaves its card in place until the save sheet is resolved.
- [ ] Zooming from a peek refreshes that card's thumbnail.
- [ ] Closing the last window of an app closes the panel rather than leaving it empty.
- [ ] Quitting the peeked application while its panel is open closes the panel.
- [ ] Moving diagonally from the icon into the panel does not close it; moving away entirely does.
- [ ] Sliding along the Dock switches the panel to the next app without closing and reopening.
- [ ] Clicking anywhere outside the panel, including on the Dock icon itself, closes it immediately. Specifically: hover an icon to open the panel, then click that same icon rather than a preview — the panel must go, not linger until you hover a different app.
- [ ] After such a click, hovering the same icon again reopens the panel normally.
- [ ] The panel never becomes key: text being typed in another app keeps its insertion point throughout.
- [ ] Opening the Tab switcher while a peek is up closes the peek, and peek stays suppressed until the switcher is dismissed.
- [ ] Hover delay and preview width take effect on the next hover without relaunching.
- [ ] Turning Show window controls off hides the buttons.
- [ ] The Dock Peek label toggles apply to peek only and leave the switcher's Appearance labels untouched, and vice versa.
- [ ] With the app name hidden, the window title is centered in the label row rather than sitting low in it.
- [ ] Turning every Dock Peek label off gives the label row's space back to the preview image.
- [ ] With Screen Recording denied, peek cards fall back to titles and icons; revoking it mid-session clears visible previews.
- [ ] An icon at either end of the Dock still produces a fully on-screen panel.
- [ ] Repeat with the Dock on the left edge, on the right edge, and with Dock auto-hide enabled.
- [ ] Repeat on a secondary display, and confirm rearranging displays while a peek is open closes it cleanly.
- [ ] An app with a very long window list narrows the previews, then wraps into an evenly balanced grid whose tiles widen back into the freed room.
- [ ] With enough windows to overflow (30+), the panel stops growing at three rows and four fifths of the screen instead of filling the display.
- [ ] That panel scrolls by trackpad and by mouse wheel, reaches the last window, and stops cleanly at both ends.
- [ ] The window count appears in the corner while scrollable, is clear of every card's title, and is absent when nothing scrolls.
- [ ] Hovering after scrolling highlights the card actually under the pointer, and a scrolled-away card never reports hover.
- [ ] Clicking a card after scrolling raises that card's window, not the one that was originally in its place.
- [ ] Counted against the app's real window count, every window is reachable by scrolling — none are missing.
- [ ] Reduce Transparency replaces the panel's vibrancy with a solid surface; Increase Contrast strengthens its border.
- [ ] Sweeping the pointer across the whole screen with peek enabled shows no measurable CPU cost; disabling the setting removes the monitor entirely.

## Displays and Spaces

- [ ] Active Display, Pointer Display, and All Displays behave as labeled.
- [ ] Changing the primary display and disconnecting a display before the next invocation does not crash.
- [ ] Disconnecting a display or changing resolution while the overlay is visible dismisses it instead of stranding a panel.
- [ ] All Displays accepts keyboard input on the primary overlay and mirrors selection elsewhere.
- [ ] Current Space Only excludes off-Space windows where public APIs expose that state.
- [ ] Switch between several Spaces and verify stale windows do not crash activation.

## Accessibility and appearance

- [ ] VoiceOver reads each card as app name followed by window title.
- [ ] VoiceOver announces each selection change as the switcher is cycled, once per change with All Displays enabled.
- [ ] VoiceOver can press a card and invoke Close, Minimize, and Zoom as custom actions on the selected card.
- [ ] VoiceOver does not focus cards hidden beyond the Orbit depth limit or outside the Sidebar viewport.
- [ ] The empty-state message is legible in Light, Dark, and System themes.
- [ ] Reduce Motion removes the perspective movement and uses a short transition.
- [ ] Increase Contrast keeps selection borders and labels legible.
- [ ] Light, Dark, and System app appearances update Settings and system-material overlay elements; window cards retain their dark photographic treatment.
- [ ] Settings controls have meaningful labels and can be reached by keyboard.

## Privacy and reliability

- [ ] Network inspection shows no outbound connection from OrbitSwitch.
- [ ] No preview image or window-title log appears on disk after repeated switching.
- [ ] Locking the screen and later invoking the overlay does not reveal stale previews.
- [ ] Locking the session or sleeping displays dismisses a visible overlay immediately.
- [ ] Memory returns near baseline after repeatedly opening a thirty-window stack.
- [ ] Rapid shortcut, display, and Settings changes never create duplicate overlays.
