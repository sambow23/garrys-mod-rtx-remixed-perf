 
#include "convar.h"

static class GlobalConvars
{
public:
	static ConVar* r_forcenovis;
	static ConVar* c_frustumcull;
	static void InitialiseConVars();
}; 