 
#include "convar.h"

static class GlobalConvars
{
public:
	static ConVar* r_forcenovis;
	static ConVar* c_frustumcull;
	static ConVar* r_worldnodenocull;
	static ConVar* r_forcehwlight;
	static void InitialiseConVars();
}; 