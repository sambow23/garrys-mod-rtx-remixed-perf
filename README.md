
# Garry's Mod RTX Fixes 2 (x64)
## Binary Module Features
- Shader fixes for known shaders that cause compatibility issues with Remix (temporarily disabled)
- Remix API Lights (WIP)
## Lua Features
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
    * Fixes some broken UI/game materials
## Installation:
> [!WARNING]  
> Ensure you have a clean 64-bit version of Garry's Mod installed with no 32-bit leftovers. 
> ### This is a total conversion, do not install this on a Garry's Mod install you care about
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

* (Map) [gm_northbury](https://steamcommunity.com/sharedfiles/filedetails/?id=3251774364) (remix cant find a camera)

* (Map) [gm_hinamizawa](https://steamcommunity.com/sharedfiles/filedetails/?id=3298456705) (vertex explosions and untextured draw calls)

* (Addon) [MW/WZ Skydive/Parachute + Infil](https://steamcommunity.com/sharedfiles/filedetails/?id=2635378860)
   - Absolutely destroys vram, what the hell does this addon do

## Known issues and stuff that doesn't work:
### Vanilla
- Shader skyboxes (gm_flatgrass, gm_construct, etc) (use the [hdri skybox](https://github.com/sambow23/hdri_cube/blob/main/README.md) addon below as an alternative)
- Some render targets (spawnmenu icons, screenshots, whatever addons that rely on them)
  - Looking into a potential fix
- NPC Eyes (limitation of FF rendering)
- Some particles will not appear (limitation of FF rendering)
- Race conditions with Remix API Lights
  - API Lights will sometimes fail to spawn or spawn infinitely, keep restarting the game until they spawn correctly
  - They can also introduce stability issues and crash the game randomly, at least reported by one user.

- HDR maps (limitation of FF rendering)
- Some materials don't appear (limitation of FF rendering)
- Model replacement for skinned meshes like ragdolls, view modelds, some props, etc.
- 3D Skybox is visible within the main map
- CEF Causes some maps to be rasterized and have vertex explosions. Use the noCEF version if you dont want to deal with these issues.

### Addons
- High vram usage with a lot of addons (most likely from ARC9 or TFA precaching textures on map load)
- Tactical RP scopes become invisible when using ADS

## Main Settings
### Custom World Renderer
![image](https://github.com/user-attachments/assets/b21681a6-31ba-4a1f-aab4-e78a6bb6241d)

Replaces engine world rendering with a chunked mesh renderer to get around brush culling.
- `Remix Capture Mode` disables engine world rendering under the custom world renderer to get clean captures.

### RTX View Frustrum
![image](https://github.com/user-attachments/assets/d854a811-ea5c-49c7-bd4a-2c1c1ae927da)

Modifies render bounds to prevent light and static prop culling around the player camera. 
   - `Regular Entity Bounds` controls the distance when static props get culled around the player, higher values means less culling but also less performance. Recommended to leave it at `256`
   - `Standard Light Distance` controls the distance when light updaters get culled. Recommended to leave it at `256`
   - `Enviornment Light Distance` controls the distance when sun light updaters get culled. Recommended to leave it at `32768` unless you're on a extremely large map

- `Add Current Map`
  - Adds the current map with an assigned Render Bounds preset. Sets the preset on map load.

## Recommended Resources and Addons
[HDRI Editor](https://github.com/sambow23/hdri_cube/blob/main/README.md)

[Garry's Mod RTX 32-bit installer by Skurtyyskirts](https://github.com/skurtyyskirts/GmodRTX)

## Credits
* [@vlazed](https://github.com/vlazed/) for [toggle-cursor](https://github.com/vlazed/toggle-cursor)
* Yosuke Nathan on the RTX Remix Showcase server for the gmod rtx logo
* Everyone on the RTX Remix Showcase server
* NVIDIA for RTX Remix
* [@BlueAmulet](https://github.com/BlueAmulet) for [SourceRTXTweaks](https://github.com/BlueAmulet/SourceRTXTweaks)  (We use this for game binary patching; Major thank you to BlueAmulet for their hard work)
