This .dll and the ./src code is from https://github.com/RaphaelIT7/obsolete-source-engine
The current changes are:
1. Port the spritecard shader to fixed function. A lot of parameters do not work but it allows most particles/effects to render.
1. Port Eyes, Eye_refract, etc shaders to vertexlitgeneric_dx6. Currently allows the eyeball to render, the iris does not work yet.

 -CR