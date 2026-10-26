# Using Drag 2.0 (Alpha)

[Website](https://dragtwozero.com) · [Project overview](../README.md)

## First launch

Open **Drag 2.0 (Alpha)** and follow the six-step introduction. On the permission step, use the Accessibility control and enable the app in **System Settings → Privacy & Security → Accessibility**. Return to the introduction once access is granted. The guide also covers the shortcut, optional Buffer, and update notifications.

After setup, Drag 2.0 lives in the menu bar. Open its menu for **Settings**, **Turn Off / Turn On**, or **Quit**.

## Drag a block

1. Place the text cursor where you want to insert content in the destination app.
2. Hold **Option + Command** over a paragraph or link in the source app.
3. Click the highlighted block and drag it into the supported input. Release to insert at its existing caret.

The source content stays in place. Drag 2.0 never submits the destination field. Intentionally selected destination text can be replaced; an unrelated selection change cancels the transfer. Press **Escape** to cancel a drag.

Change the trigger shortcut, formatting, appearance, haptics, and animations in Settings. Links and emphasis depend on the attributes exposed by the source app and your formatting preference. Motion respects Reduce Motion.

## Buffer

Using one screen, or need a place for your drag to rest? Enable the optional **Buffer** step in onboarding, before the updates question, or use **Settings → General → Buffer** to hold one item for later. Buffer is off by default.

1. Hold the trigger shortcut to reveal **Buffer**, including over empty space.
2. Drag a captured item into its recessed slot, then release the shortcut.
3. Switch to the destination and drag the stored item out of the slot without holding the shortcut.

Buffer holds one item in memory. A deliberate drop onto its slot replaces the stored item. The **×** clears it. Turning Buffer off, turning the app off, or quitting also clears its contents.

**Position of buffer** offers Left bottom, Right bottom, Left top, Right top, and Dynamic Island. Dynamic Island is the default; the position control is disabled while Buffer is off.

An invalid or cancelled drop keeps the item. Buffer inserts through the same saved-caret delivery path as a direct highlighted drag. Confirmed insertion consumes the item. An unconfirmed paste hides the panel until the next explicit shortcut, then shows the stored content with a warning to check the destination before retrying. There is no automatic retry.

## Experimental features

Both features are in **Settings → General → Experimental** and are off by default.

**Multi-select:** hold the shortcut and drag from empty space across blocks. Release the shortcut while still pressing the mouse or trackpad to drag the group. If you release the mouse first, keep holding the shortcut and click a highlighted block or the hint to start dragging. Releasing the shortcut before starting that drag clears the group.

**Drag selected text:** select a passage natively, hold the shortcut, and hover the selection. Click any highlighted line to drag the entire selection. This requires the source app to expose the selection and its visual bounds through Accessibility. An unreadable selection is rejected rather than expanded to a larger paragraph.

## Clipboard and privacy

In **Settings → About**, use **Check for Updates → Download & Install → Restart**. Each action requires your confirmation. Finish or cancel an active capture/transfer and use or explicitly clear Buffer before restarting. Cancel stops the pending update. Periodic checks can be disabled with **Notify about updates**; manual checks remain available.

**Overwrite clipboard** in General is off by default. Buffer and direct highlight drops temporarily use the clipboard, restoring its previous contents after confirmed insertion when Drag 2.0 still owns that clipboard revision. Parking an item in Buffer does not change the clipboard. With the option on, confirmed delivered content remains available to paste. A newer copy always takes priority. An unconfirmed paste can leave the captured content on the clipboard for late readers and recovery; check the destination before retrying.

Captured content is processed locally. Optional Screen Recording permission is used for small brightness samples to adapt glass contrast; no frames are saved or uploaded. Update checks contact GitHub and can be disabled in About. See [Legal & Privacy](https://dragtwozero.com/legal#app-privacy).

## Compatibility and limitations

- Apple Silicon only, installable on macOS 13+. Official support is limited to the latest major macOS release once validated. Older versions may work but are unsupported; compatibility is not guaranteed. Liquid Glass requires macOS 26 or later.
- This candidate was tested on macOS 26.4.1; macOS 27 validation is pending. The installation minimum does not mean every installable OS version has been tested.
- Capture and insertion depend on each app's Accessibility support. There is no complete verified app/browser compatibility matrix yet.
- Google Docs canvas targeting is disabled. Table drops require a writable cell and replace that cell's value.
- Chrome/Chromium paste compatibility remains a release-validation item. A posted Paste command alone does not prove insertion; check the field before retrying an uncertain transfer.
- Experimental selection features have additional Accessibility requirements and can safely reject unsupported content.

When reporting an issue, include macOS, Drag 2.0, source app, and destination app versions, plus a reproduction using synthetic text. Do not attach private documents or clipboard dumps. Follow [CONTRIBUTING.md](../CONTRIBUTING.md) for bugs and proposals, or [SECURITY.md](../SECURITY.md) for private security reports.
