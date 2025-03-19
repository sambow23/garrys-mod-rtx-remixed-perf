
# Garry's Mod RTX Fixes 2 (x64)
## Features
- Custom World Renderer
  * Renders map geometry with meshed chunks to prevent PVS/Frustrum culling of brush faces
- View Frustrum Forcing
  * Modifies render bounds of static props and light updaters to prevent them getting culled by the view frustrum
- Water replacer
  * Replaces all map water materials with a single one so it can be replaced in Remix
    * Some non-water materials in maps might get replaced with water. If so, please make a github issue with the map name and screenshot on where its happening.
- Light Updaters
    * Forces Source to render all map lights
- Material Fixer
    * Fixes some broken UI/game materials and removes detail textures
## Installation:
> [!WARNING]
> ### This is a total conversion, do not install this on a Garry's Mod install you care about
> ### Ensure you are using the x64-86 branch of Garry's Mod
> <img width="632" alt="image" src="https://github.com/user-attachments/assets/4f26ce9f-ac2a-4469-93f0-4fcdf0dffee4" />


1. Subscribe to this [addon collection](https://steamcommunity.com/sharedfiles/filedetails/?id=3417054376) (click `Subscribe to all` > `Add Only`)
2. Download the latest [release](https://github.com/Xenthio/gmod-rtx-fixes-2/releases/latest)
3. Make a copy of your Garry's Mod installation and call it something like `GarrysModRTX`. The path should look like this:    
(If you're doing a clean install, open the game once with steam before installing the mod)
  - `C:\Program Files (x86)\Steam\steamapps\common\GarrysModRTX`

4. Open `gmrtx64_(ver).zip`, extract everything inside to
`C:\Program Files (x86)\Steam\steamapps\common\GarrysModRTX`, overwrite everything.
5. Open the game with the `GarrysModRTX` launcher
6. Profit.

## Incompatible Addons
* (Map) [Bro Said He Knew A Spot 💀](https://steamcommunity.com/sharedfiles/filedetails/?id=3252367349) (Breaks other shader-skybox maps)

* (Map) [gm_northbury](https://steamcommunity.com/sharedfiles/filedetails/?id=3251774364) (rasterized)

* (Map) [gm_hinamizawa](https://steamcommunity.com/sharedfiles/filedetails/?id=3298456705) (vertex explosions and untextured draw calls)

* (Map) [gm_bigcity_improved](https://steamcommunity.com/workshop/filedetails/?id=815782148) (rasterized)

* (Addon) [MW/WZ Skydive/Parachute + Infil](https://steamcommunity.com/sharedfiles/filedetails/?id=2635378860)
   - Consumes a lot of vram, most likely precaching

## Known issues:
### Vanilla
- Shader skyboxes (gm_flatgrass, gm_construct, etc) cannot be interacted with and may have rendering issues
- Some render targets (spawnmenu icons, screenshots, whatever addons that rely on them) do not appear or behave strangely (investigating)
- NPC Eyes do not render as the fixed function rendering fallback no longer exists (investigating)
- Some particles will not render (need to change each material from $SpriteCard to $UnlitGeneric to fix)
- HDR maps crash the game or have no lighting (limitation of FF rendering)
- Some meshes will not render (limitation of FF rendering)
- Some maps will be rasterized and have vertex explosions.
- Some map lights will cull even with Lightupdaters active (investigating)
- Some func_ entities will cull in strange ways (investigating)
- Maps that don't extensively use PVS will have poor performance

### Addons
- High vram usage with a lot of addons (most likely from ARC9 or TFA precaching textures on map load)
- Tactical RP scopes become invisible when using ADS

## Recommended Resources and Addons
[HDRI Editor](https://github.com/sambow23/hdri_cube/blob/main/README.md)

[Garry's Mod RTX 32-bit installer by Skurtyyskirts](https://github.com/skurtyyskirts/GmodRTX)

## Credits
* [@vlazed](https://github.com/vlazed/) for [toggle-cursor](https://github.com/vlazed/toggle-cursor)
* Yosuke Nathan on the RTX Remix Showcase server for the gmod rtx logo
* Everyone on the RTX Remix Showcase server
* NVIDIA for RTX Remix
* [@BlueAmulet](https://github.com/BlueAmulet) for [SourceRTXTweaks](https://github.com/BlueAmulet/SourceRTXTweaks)  (We use this for game binary patching; Major thank you to BlueAmulet for their hard work)
