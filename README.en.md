# Star Rail 120 FPS Unlock (one-click scripts)

[中文](README.md) | **English**

Honkai: Star Rail on PC hides its 120 FPS option: the in-game menu only offers 30/60, while the game itself supports 120. This tool edits the game's own settings value (the same hidden option) — one click, no background software.

- Pure PowerShell: no injection, no game file modifications, no anti-cheat interaction
- Works with the global client and the China client (auto-detected)
- Automatic backup + one-click restore to the official default (60)
- Ships with a GPU-agnostic FPS counter window (NVIDIA / AMD / integrated graphics)

> Requirements: Windows 10 / 11 with the built-in PowerShell 5.1. Nothing to install.

## Quick start

1. Download this repository (`Code → Download ZIP`, or `git clone`)
2. **Fully close the game first**
3. Double-click `SET-120FPS.bat` — success shows `FPS cap set to 120 (verified).`
4. Launch the game

To go back to the official 60 FPS cap: close the game and double-click `RESTORE-60FPS.bat`.

## Verify the frame rate

Note: after unlocking, the in-game Settings → FPS value may still display 30/60 — that is a known display bug caused by the hidden option. Trust an external counter instead:

| Method | GPU | How |
|---|---|---|
| FPS counter window (included) | All (NVIDIA / AMD / integrated) | Double-click `FPS-MONITOR.bat`, approve one UAC prompt |
| Xbox Game Bar | All, built-in | `Win+G` → Performance widget → pin it |
| NVIDIA app | NVIDIA only | Press `Alt+R` in game (`Alt+Z → Statistics → Configure heads-up display` to slim it down) |

Expect a steady frame rate close to 120; small dips in heavy scenes are normal.

## The FPS counter (FPS-MONITOR.bat)

- Powered by Intel's official open-source [PresentMon](https://github.com/GameTechDev/PresentMon) (MIT), reading system-level frame events (ETW) — **works on any GPU**, never injects into the game
- Asks for administrator rights once: a Windows requirement for reading frame events; it only reads, never modifies anything
- Drag to move, right-click → Exit. Best used on a second monitor, or while the game runs windowed / borderless
- Bundled PresentMon: v2.6.0 (x64), SHA-256 `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af`

## FAQ

- The game still shows 30/60 in settings. → Known display bug, see above; trust the external counter.
- Frame rate dropped back after I changed graphics options. → Any in-game graphics change resets the cap to 60; run `SET-120FPS.bat` again.
- Does it need admin rights? → The unlock script does not (it only edits your own user registry setting). The FPS counter needs one elevation prompt (to read system frame events).
- Is it bannable? → It does not inject, does not modify game files, and only edits a local display setting (same class as changing an in-game option). Use at your own risk and respect the game's terms.
- Which clients are supported? → Global `HKCU\Software\Cognosphere\Star Rail`; China `HKCU\Software\miHoYo\崩坏：星穹铁道`.
- My monitor isn't 120 Hz. → Still fine. The script warns you that gains are limited below 120 Hz (but it can still reduce stutter).

## How it works

The game stores its graphics settings in the current user's registry, under a binary value named `GraphicsSettings_Model_h*` (UTF-8 JSON). `"FPS":60` is the visible option. The script:

1. Backs up the original value as Base64 to `%LOCALAPPDATA%\star-rail-120fps\backup.b64` (first run only)
2. Replaces the `"FPS"` number with the target (120 or 60) and writes it back
3. Reads it back and verifies

## Safety & rollback

- Edits only your own user registry setting — equivalent to changing an in-game option. No system files, no services, nothing running in the background
- The original value is backed up automatically; `RESTORE-60FPS.bat` returns to the official default
- Not affiliated with the game's developer or publisher. Use at your own risk.

## Related projects

- [PresentMon](https://github.com/GameTechDev/PresentMon) (Intel, MIT) — data source for the FPS counter
- Similar FPS-cap unlockers (for reference/comparison): [winTEuser/Genshin_StarRail_fps_unlocker](https://github.com/winTEuser/Genshin_StarRail_fps_unlocker)

## License

[MIT](LICENSE)
