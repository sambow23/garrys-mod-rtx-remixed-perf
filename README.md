
# Garry's Mod RTX Fixes 2 (x64)
## Binary Module Features
- Shader fixes for known shaders that cause compatibility issues with Remix
- Remix API Lights (WIP)
## Lua Features
- Custom World Renderer
  * Renders map geometry with meshed chunks to prevent PVS/Frustrum culling of brush faces
- View Frustrum "Optimizer"
  * Modifies render bounds of static/physics props and light updaters to prevent them getting culled by the view frustrum
- Water replacer
  * Replaces all map water materials with a single one so it can be replaced in Remix
    * Some non-water materials in maps might get replaced with water. If so, please make a github issue with the map name and screenshot on where its happening.

## Installation:
### Required Addons
- [NikNaks](https://steamcommunity.com/sharedfiles/filedetails/?id=2861839844)
- [FuckEmHalos](https://steamcommunity.com/sharedfiles/filedetails/?id=2961222721)
- [RTX Remix Fixes](https://steamcommunity.com/sharedfiles/filedetails/?id=3038853470)
> [!WARNING]  
> Ensure you have a clean 64-bit version of Garry's Mod installed with no 32-bit leftovers. 
> ### This is a total conversion, do not install this on a Garry's Mod install you care about
1. Download the latest [release](https://github.com/Xenthio/gmod-rtx-fixes-2/releases/latest)
2. Make a copy of your Garry's Mod installation and call it something like `GarrysModRTX`. The path should look like this:    
(If you're doing a clean install, open the game once with steam before installing the mod)
  - `C:\Program Files (x86)\Steam\steamapps\common\GarrysModRTX`

3. Open `gmrtx64_(ver).zip`, extract everything inside to
`C:\Program Files (x86)\Steam\steamapps\common\GarrysModRTX`, overwrite everything.
4. Open the game with the bat file:
`GarrysModRTX\bin\win64\gmodrtx64.bat`

5. Profit.

## Incompatible Addons
(Map) [Bro Said He Knew A Spot 💀](https://steamcommunity.com/sharedfiles/filedetails/?id=3252367349) (Breaks other shader-skybox maps)

(Map) [gm_northbury](https://steamcommunity.com/sharedfiles/filedetails/?id=3251774364) (remix cant find a camera)

## Known issues and stuff that doesn't work:
### Vanilla
- Remix cannot lock keyboard and mouse input when the runtime menu is open (happens because of no remix bridge, nvidia will need to fix it on their end)
- The mouse cursor will occasionally appear when moving around the camera (happens because of no remix bridge, nvidia will need to fix it on their end)
- Shader skyboxes (gm_flatgrass, gm_construct, etc) (use the [hdri skybox](https://github.com/sambow23/hdri_cube/blob/main/README.md) addon below as an alternative)
- Some render targets (spawnmenu icons, screenshots, whatever addons that rely on them)
- NPC Eyes (limitation of FF rendering)
- Some particles will not appear (limitation of FF rendering)
- Race conditions with Remix API Lights
  - API Lights will sometimes fail to spawn or spawn infinitely, keep restarting the game until they spawn correctly
  - They can also introduce stability issues and crash the game randomly, at least reported by one user.

- HDR maps (limitation of FF rendering)
- Some materials don't appear (limitation of FF rendering)
- Material Tool (use [SubMaterial](https://steamcommunity.com/sharedfiles/filedetails/?id=2836948539&searchtext=submaterial) for now instead)
  - investigating a fix
- Model replacement for skinned meshes like ragdolls, view modelds, some props, etc.

### Addons
- High vram usage with a lot of addons (most likely from ARC9 or TFA precaching textures on map load)
- Tactical RP scopes become invisible when using ADS
- Hands become rasterized when using ADS with ARC9

## Main Settings
### Custom World Renderer
![image](https://github.com/user-attachments/assets/b21681a6-31ba-4a1f-aab4-e78a6bb6241d)

Replaces engine world rendering with a chunked mesh renderer to get around brush culling.
- `Remix Capture Mode` disables engine world rendering under the custom world renderer to get clean captures.

### RTX View Frustrum
![image](https://github.com/user-attachments/assets/08fd9b77-29a6-48c0-8683-d2fe0dd0fcc7)

Modifies render bounds to prevent culling around the player camera. 
- `Render Bounds Size` controls the distance when static/physics props get culled around the player, higher values means less culling but also less performance
- `RTX Updater Distance` controls the distance when light updaters get culled. A lot of maps can have this at 256 which saves a lot of performance, but if the sun light is far away on the map, crank it to at least 4096.

## Recommended Resources and Addons
[HDRI Editor](https://github.com/sambow23/hdri_cube/blob/main/README.md)

[SourceRTXTweaks](https://github.com/BlueAmulet/SourceRTXTweaks) (We use this for game binary patching; Major thank you to BlueAmulet for their hard work)

[Garry's Mod RTX 32-bit installer by Skurtyyskirts](https://github.com/skurtyyskirts/GmodRTX)
