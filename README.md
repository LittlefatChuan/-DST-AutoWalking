# [DST]Auto Walking

A Client-side Pathfinding Mod in Dont Starve Together In Lua

See it in DST Workshop :  [AutoWalking](https://steamcommunity.com/sharedfiles/filedetails/?id=2849308125)

## How to work :

### Normal Trigger:

just right click in your map (it's okay as well to right click in other map hud when you have a Minimap HUD or Smallmap Mod) and the character will automatically find a way and travel the destination you pointed.

### Wortox Trigger:

For wortox and other modcharacter who has a map action, right click in map for once to autowalk, double rightclick for originally map action.

### Stop:

To stop the walking , just press any of walkbuttons(WASD) or click something in game

## Use it in your code:

you can start the autowalking in your code when you enabled this mod:

```
local dest = Vector3(11,45,14) # Point of your destination
ThePlayer.components.ngl_pathfollower:Travel(dest) # start to pathfind and autowalk to the destination
```
