# Garry's Mod RTX Fixes 2
## Features
### Universal (x86 and x64)
- Light Updaters
    * Forces Source to render all map lights
- Water replacer
  * Replaces all map water materials with a single one so it can be replaced in Remix
- Material Fixer
    * Fixes some broken UI/game materials and removes detail textures
- Model fixer
    * Fixes props having unstable hashes in RTX Remix so they can be replaced in the Remix Toolkit
    * Allows HL2 RTX mesh replacements to load correctly

## Installation
1. Subscribe to [NikNaks](https://steamcommunity.com/sharedfiles/filedetails/?id=2861839844) on the Steam Workshop.
2. Download [RTXLauncher](https://github.com/Xenthio/RTXLauncher/releases/latest).
3. Put `RTXLauncher.exe` in an empty folder, run it as an <ins>**Administrator**</ins>.
4. Select `Run Quick Install` on the main screen and follow the prompts when asked.
5. Once it's finished, press `Launch Game` at the bottom of the launcher.

## Incompatible Addons
* (Map) [Bro Said He Knew A Spot 💀](https://steamcommunity.com/sharedfiles/filedetails/?id=3252367349) (Breaks other shader-skybox maps)

* (Map) [gm_northbury](https://steamcommunity.com/sharedfiles/filedetails/?id=3251774364) (rasterized)

* (Map) [gm_hinamizawa](https://steamcommunity.com/sharedfiles/filedetails/?id=3298456705) (vertex explosions and untextured draw calls)

* (Map) [gm_bigcity_improved](https://steamcommunity.com/workshop/filedetails/?id=815782148) (rasterized)

* (Addon) [MW/WZ Skydive/Parachute + Infil](https://steamcommunity.com/sharedfiles/filedetails/?id=2635378860)
   - Consumes a lot of vram, most likely precaching
* (Addon) [CS:GO Weapons](https://steamcommunity.com/sharedfiles/filedetails/?id=2193997180)
   - Makes game freeze up on `Starting lua...` when loading into a map

## Known issues
### Vanilla
- Shader skyboxes (gm_flatgrass, gm_construct, etc) cannot be interacted with and may have rendering issues
- Some render targets (spawnmenu icons, screenshots, whatever addons that rely on them) do not appear or behave strangely (investigating)
- NPC Eyes do not render as the fixed function rendering fallback no longer exists (investigating)
- Some particles will not render (need to change each material from $SpriteCard to $UnlitGeneric to fix)
- Some maps will be rasterized and have vertex explosions.
- Some map lights will cull even with Lightupdaters active (investigating)
- Enabling `r_3dsky` causes rendering issues

### Addons
- High vram usage from addons like ARC9 or TFA as they precache textures on map load
- Tactical RP scopes become invisible when using ADS

## Recommended Resources
[HDRI Editor](https://github.com/sambow23/hdri_cube/blob/main/README.md)

## Credits
* [vlazed](https://github.com/vlazed/) for [toggle-cursor](https://github.com/vlazed/toggle-cursor)
* Yosuke Nathan on the RTX Remix Showcase server for the gmod rtx logo
* Everyone on the RTX Remix Showcase server
* NVIDIA for RTX Remix
* [Nak2](https://github.com/Nak2) for [NikNaks](https://github.com/Nak2/NikNaks)
* [BlueAmulet](https://github.com/BlueAmulet) for [SourceRTXTweaks](https://github.com/BlueAmulet/SourceRTXTweaks)
* [0xNULLderef](https://github.com/0xNULLderef) and [Wolƒe Strider Shoσter](https://github.com/wolfestridershooter) for additional x64 patches (culling and HDR map lighting)
