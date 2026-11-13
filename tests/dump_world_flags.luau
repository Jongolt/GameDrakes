-- Prints the world flags for build.py (Terrain.Decoration, GrassLength, Clouds are set in the place file).
local Config = require("../src/shared/Config")
local W = Config.World
print("terrainDecoration=" .. tostring(W.terrainDecoration == true))
print("grassLength=" .. tostring(W.grassLength or 1))
print("cloudCover=" .. tostring(W.clouds.volumetric and W.clouds.volumetric.cover or 0.5))
print("cloudDensity=" .. tostring(W.clouds.volumetric and W.clouds.volumetric.density or 0.3))
print("streamingEnabled=" .. tostring(W.streamingEnabled == true))
print("streamingMin=" .. tostring(W.streaming and W.streaming.minRadius or 64))
print("streamingTarget=" .. tostring(W.streaming and W.streaming.targetRadius or 1024))
print("streamingBehavior=" .. tostring(W.streaming and W.streaming.behavior or "Default"))
