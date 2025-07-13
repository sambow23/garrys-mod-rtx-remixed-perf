//========= Copyright CR, bla bla bla rights reserved. ============//
//
// Implementation of the spritecard shader for fixed-function pipeline
// Buggy as hell
//=============================================================================//

#include "shaderlib/cshader.h"
#include <string.h>
#include "const.h"

// memdbgon must be the last include file in a .cpp file!!!
#include "tier0/memdbgon.h"

// Sprite orientations (from spritecard)
#define SPRITECARD_ORIENTATION_SCREEN_ALIGNED	0	// always face camera
#define SPRITECARD_ORIENTATION_Z_ALIGNED		1	// rotate around z
#define SPRITECARD_ORIENTATION_GROUND_ALIGNED	2	// parallel to ground

// Sequence blend modes (stubbed for fixed-function)
#define SEQUENCE_BLEND_MODE_AVERAGE				0
#define SEQUENCE_BLEND_MODE_ALPHA_FROM_FIRST	1
#define SEQUENCE_BLEND_MODE_FIRST_OVER_SECOND	2

DEFINE_FALLBACK_SHADER(Spritecard, Spritecard_DX6)

BEGIN_SHADER( Spritecard_DX6,
			  "Help for Spritecard_DX6 - Fixed-function spritecard implementation" )
			  
	BEGIN_SHADER_PARAMS
		// Basic spritecard parameters (ported from spritecard.cpp)
		SHADER_PARAM( ORIENTATION, SHADER_PARAM_TYPE_INTEGER, "0", "0 = always face camera, 1 = rotate around z, 2= parallel to ground" )
		SHADER_PARAM( ADDBASETEXTURE2, SHADER_PARAM_TYPE_FLOAT, "0.0", "amount to blend second texture into frame by" )
		SHADER_PARAM( OVERBRIGHTFACTOR, SHADER_PARAM_TYPE_FLOAT, "1.0", "overbright factor for texture. For HDR effects.")
		SHADER_PARAM( ADDOVERBLEND, SHADER_PARAM_TYPE_INTEGER, "0", "use ONE:INVSRCALPHA blending")
		SHADER_PARAM( ADDSELF, SHADER_PARAM_TYPE_FLOAT, "0.0", "amount of base texture to additively blend in" )
		SHADER_PARAM( MINSIZE, SHADER_PARAM_TYPE_FLOAT, "0.0", "minimum screen fractional size of particle")
		SHADER_PARAM( STARTFADESIZE, SHADER_PARAM_TYPE_FLOAT, "10.0", "screen fractional size to start fading particle out")
		SHADER_PARAM( ENDFADESIZE, SHADER_PARAM_TYPE_FLOAT, "20.0", "screen fractional size to finish fading particle out")
		SHADER_PARAM( MAXSIZE, SHADER_PARAM_TYPE_FLOAT, "20.0", "maximum screen fractional size of particle")
		SHADER_PARAM( MAXDISTANCE, SHADER_PARAM_TYPE_FLOAT, "100000.0", "maximum distance to draw particles at")
		SHADER_PARAM( FARFADEINTERVAL, SHADER_PARAM_TYPE_FLOAT, "400.0", "interval over which to fade out far away particles")
		SHADER_PARAM( BLENDFRAMES, SHADER_PARAM_TYPE_BOOL, "1", "whether or not to smoothly blend between animated frames" )
		
		// Stubbed parameters (shader-dependent features disabled)
		SHADER_PARAM( DEPTHBLEND, SHADER_PARAM_TYPE_INTEGER, "0", "fade at intersection boundaries (STUBBED - always 0)" )
		SHADER_PARAM( DEPTHBLENDSCALE, SHADER_PARAM_TYPE_FLOAT, "50.0", "Amplify or reduce DEPTHBLEND fading (STUBBED)" )
		SHADER_PARAM( DUALSEQUENCE, SHADER_PARAM_TYPE_INTEGER, "0", "blend two separate animated sequences (STUBBED - always 0)")
		SHADER_PARAM( SEQUENCE_BLEND_MODE, SHADER_PARAM_TYPE_INTEGER, "0", "blend mode between dual sequence images (STUBBED)")
		SHADER_PARAM( MAXLUMFRAMEBLEND1, SHADER_PARAM_TYPE_INTEGER, "0", "max luminance frame blending for first sequence (STUBBED)")
		SHADER_PARAM( MAXLUMFRAMEBLEND2, SHADER_PARAM_TYPE_INTEGER, "0", "max luminance frame blending for second sequence (STUBBED)")
		SHADER_PARAM( RAMPTEXTURE, SHADER_PARAM_TYPE_TEXTURE, "", "color ramp texture (STUBBED)")
		SHADER_PARAM( ZOOMANIMATESEQ2, SHADER_PARAM_TYPE_FLOAT, "1.0", "zoom animation for second sequence (STUBBED)")
		SHADER_PARAM( EXTRACTGREENALPHA, SHADER_PARAM_TYPE_INTEGER, "0", "extract green/alpha channels (STUBBED)")
		SHADER_PARAM( USEINSTANCING, SHADER_PARAM_TYPE_BOOL, "0", "GPU vertex instancing (STUBBED - always 0)")
		SHADER_PARAM( SPLINETYPE, SHADER_PARAM_TYPE_INTEGER, "0", "spline type (STUBBED - always 0)")
		
		// Legacy sprite_dx6 parameters for compatibility
		SHADER_PARAM( SPRITEORIGIN, SHADER_PARAM_TYPE_VEC3, "[0 0 0]", "sprite origin" )
		SHADER_PARAM( SPRITEORIENTATION, SHADER_PARAM_TYPE_INTEGER, "0", "sprite orientation (legacy)" )
		SHADER_PARAM( SPRITERENDERMODE, SHADER_PARAM_TYPE_INTEGER, "0", "sprite rendermode (legacy)" )
		SHADER_PARAM( IGNOREVERTEXCOLORS, SHADER_PARAM_TYPE_BOOL, "1", "ignore vertex colors" )
	END_SHADER_PARAMS

	SHADER_INIT_PARAMS()
	{
		// Initialize default values (from spritecard.cpp)
		if ( !params[ALPHA]->IsDefined() )
			params[ ALPHA ]->SetFloatValue( 1.0f );
		
		// Initialize spritecard-specific defaults
		if ( !params[MAXDISTANCE]->IsDefined() )
			params[MAXDISTANCE]->SetFloatValue( 100000.0f );
		if ( !params[FARFADEINTERVAL]->IsDefined() )
			params[FARFADEINTERVAL]->SetFloatValue( 400.0f );
		if ( !params[MAXSIZE]->IsDefined() )
			params[MAXSIZE]->SetFloatValue( 20.0f );
		if ( !params[ENDFADESIZE]->IsDefined() )
			params[ENDFADESIZE]->SetFloatValue( 20.0f );
		if ( !params[STARTFADESIZE]->IsDefined() )
			params[STARTFADESIZE]->SetFloatValue( 10.0f );
		if ( !params[OVERBRIGHTFACTOR]->IsDefined() )
			params[OVERBRIGHTFACTOR]->SetFloatValue( 1.0f );
		if ( !params[ADDBASETEXTURE2]->IsDefined() )
			params[ADDBASETEXTURE2]->SetFloatValue( 0.0f );
		if ( !params[ADDSELF]->IsDefined() )
			params[ADDSELF]->SetFloatValue( 0.0f );
		if ( !params[BLENDFRAMES]->IsDefined() )
			params[BLENDFRAMES]->SetIntValue( 1 );
		if ( !params[ORIENTATION]->IsDefined() )
			params[ORIENTATION]->SetIntValue( SPRITECARD_ORIENTATION_SCREEN_ALIGNED );
		
		// Force stubbed parameters to safe defaults
		if ( !params[DEPTHBLEND]->IsDefined() )
			params[DEPTHBLEND]->SetIntValue( 0 );  // Always disabled for fixed-function
		if ( !params[DUALSEQUENCE]->IsDefined() )
			params[DUALSEQUENCE]->SetIntValue( 0 );  // Always disabled
		if ( !params[USEINSTANCING]->IsDefined() )
			params[USEINSTANCING]->SetIntValue( 0 );  // Always disabled
		if ( !params[SPLINETYPE]->IsDefined() )
			params[SPLINETYPE]->SetIntValue( 0 );  // Always disabled
		
		// Handle legacy sprite_dx6 orientation parameter mapping
		if (params[SPRITEORIENTATION]->IsDefined())
		{
			const char *orientationString = params[SPRITEORIENTATION]->GetStringValue();
			if( stricmp( orientationString, "parallel_upright" ) == 0 )
			{
				params[ORIENTATION]->SetIntValue( SPRITECARD_ORIENTATION_SCREEN_ALIGNED );
			}
			else if( stricmp( orientationString, "facing_upright" ) == 0 )
			{
				params[ORIENTATION]->SetIntValue( SPRITECARD_ORIENTATION_SCREEN_ALIGNED );
			}
			else if( stricmp( orientationString, "vp_parallel" ) == 0 )
			{
				params[ORIENTATION]->SetIntValue( SPRITECARD_ORIENTATION_GROUND_ALIGNED );
			}
			else if( stricmp( orientationString, "oriented" ) == 0 )
			{
				params[ORIENTATION]->SetIntValue( SPRITECARD_ORIENTATION_Z_ALIGNED );
			}
			else if( stricmp( orientationString, "vp_parallel_oriented" ) == 0 )
			{
				params[ORIENTATION]->SetIntValue( SPRITECARD_ORIENTATION_Z_ALIGNED );
			}
			else
			{
				Warning( "error with $spriteOrientation - using default\n" );
				params[ORIENTATION]->SetIntValue( SPRITECARD_ORIENTATION_SCREEN_ALIGNED );
			}
		}
		
		// Handle legacy sprite rendermode if specified
		if ( !params[SPRITERENDERMODE]->IsDefined() )
			params[SPRITERENDERMODE]->SetIntValue( kRenderNormal );

		SET_FLAGS( MATERIAL_VAR_NO_DEBUG_OVERRIDE );
		SET_FLAGS( MATERIAL_VAR_VERTEXCOLOR );
		SET_FLAGS( MATERIAL_VAR_VERTEXALPHA );
		SET_FLAGS2( MATERIAL_VAR2_IS_SPRITECARD );
	}

	SHADER_INIT
	{
		LoadTexture( BASETEXTURE );
		
		// Load second texture if specified
		if ( params[ADDBASETEXTURE2]->GetFloatValue() > 0.0f )
		{
			// For fixed-function, we'll use the same base texture on multiple stages
			// More advanced implementations could load a separate texture here
		}
		
		// Stub: Ramp texture loading (not supported in fixed-function)
		if ( params[RAMPTEXTURE]->IsDefined() )
		{
			// Warning: Color ramp textures not supported in fixed-function pipeline
			// This would require programmable shaders to implement properly
		}
	}

	SHADER_DRAW
	{
		// Get render mode - use legacy sprite rendermode if available, otherwise determine from parameters
		int nRenderMode = params[SPRITERENDERMODE]->GetIntValue();
		bool bAdditive2ndTexture = params[ADDBASETEXTURE2]->GetFloatValue() > 0.0f;
		bool bAddSelf = params[ADDSELF]->GetFloatValue() > 0.0f;
		bool bAddOverBlend = params[ADDOVERBLEND]->GetIntValue() != 0;
		
		// Determine effective render mode based on spritecard parameters
		if ( bAddOverBlend )
		{
			nRenderMode = kRenderTransAdd;  // Use additive blending
		}
		else if ( bAdditive2ndTexture || bAddSelf )
		{
			nRenderMode = kRenderTransAdd;  // Use additive blending
		}
		else if ( nRenderMode == kRenderNormal )
		{
			// Check if we should use alpha blending based on material flags
			if ( IS_FLAG_SET(MATERIAL_VAR_ADDITIVE) )
			{
				nRenderMode = kRenderTransAdd;
			}
			else if ( IS_FLAG_SET(MATERIAL_VAR_ALPHATEST) )
			{
				nRenderMode = kRenderTransAlpha;
			}
			else
			{
				nRenderMode = kRenderTransTexture;  // Default to alpha blending
			}
		}
		
		// Render based on the determined mode (adapted from sprite_dx6.cpp)
		switch( nRenderMode )
		{
		case kRenderNormal:
			SHADOW_STATE
			{
				pShaderShadow->EnableCulling( false );
				pShaderShadow->EnableTexture( SHADER_SAMPLER0, true );
				pShaderShadow->DrawFlags( SHADER_DRAW_POSITION | SHADER_DRAW_TEXCOORD0 );
				FogToFogColor();
			}
			DYNAMIC_STATE
			{
				BindTexture( SHADER_SAMPLER0, BASETEXTURE, FRAME );
				
				// Apply overbright factor if specified
				if ( params[OVERBRIGHTFACTOR]->GetFloatValue() != 1.0f )
				{
					float flOverbright = params[OVERBRIGHTFACTOR]->GetFloatValue();
					pShaderAPI->Color3f( flOverbright, flOverbright, flOverbright );
				}
			}
			Draw();
			break;
			
		case kRenderTransColor:
		case kRenderTransTexture:
		case kRenderTransAlpha:
			SHADOW_STATE
			{
				pShaderShadow->EnableCulling( false );
				pShaderShadow->EnableDepthWrites( false );
				pShaderShadow->EnableBlending( true );
				pShaderShadow->BlendFunc( SHADER_BLEND_SRC_ALPHA, SHADER_BLEND_ONE_MINUS_SRC_ALPHA );
				pShaderShadow->EnableTexture( SHADER_SAMPLER0, true );
				pShaderShadow->DrawFlags( SHADER_DRAW_POSITION | SHADER_DRAW_TEXCOORD0 | SHADER_DRAW_COLOR );
				FogToFogColor();
			}
			DYNAMIC_STATE
			{
				BindTexture( SHADER_SAMPLER0, BASETEXTURE, FRAME );
				
				// Apply overbright factor
				if ( params[OVERBRIGHTFACTOR]->GetFloatValue() != 1.0f )
				{
					float flOverbright = params[OVERBRIGHTFACTOR]->GetFloatValue();
					pShaderAPI->Color3f( flOverbright, flOverbright, flOverbright );
				}
			}
			Draw();
			break;
			
		case kRenderGlow:
		case kRenderWorldGlow:
			SHADOW_STATE
			{
				pShaderShadow->EnableCulling( false );
				pShaderShadow->EnableDepthWrites( false );
				pShaderShadow->EnableDepthTest( false );
				pShaderShadow->EnableBlending( true );
				pShaderShadow->BlendFunc( SHADER_BLEND_SRC_ALPHA, SHADER_BLEND_ONE );
				pShaderShadow->EnableTexture( SHADER_SAMPLER0, true );
				pShaderShadow->DrawFlags( SHADER_DRAW_POSITION | SHADER_DRAW_TEXCOORD0 | SHADER_DRAW_COLOR );
				FogToBlack();
			}
			DYNAMIC_STATE
			{
				BindTexture( SHADER_SAMPLER0, BASETEXTURE, FRAME );
				
				// Apply overbright factor
				if ( params[OVERBRIGHTFACTOR]->GetFloatValue() != 1.0f )
				{
					float flOverbright = params[OVERBRIGHTFACTOR]->GetFloatValue();
					pShaderAPI->Color3f( flOverbright, flOverbright, flOverbright );
				}
			}
			Draw();
			break;
			
		case kRenderTransAdd:
			SHADOW_STATE
			{
				pShaderShadow->EnableCulling( false );
				if( params[ IGNOREVERTEXCOLORS ]->GetIntValue() )
				{
					pShaderShadow->DrawFlags( SHADER_DRAW_POSITION | SHADER_DRAW_TEXCOORD0 );
				}
				else
				{
					pShaderShadow->DrawFlags( SHADER_DRAW_POSITION | SHADER_DRAW_TEXCOORD0 | SHADER_DRAW_COLOR );
				}
				pShaderShadow->EnableConstantColor( true );
				pShaderShadow->EnableDepthWrites( false );
				pShaderShadow->EnableBlending( true );
				pShaderShadow->BlendFunc( SHADER_BLEND_SRC_ALPHA, SHADER_BLEND_ONE );
				pShaderShadow->EnableTexture( SHADER_SAMPLER0, true );
				FogToBlack();
			}
			DYNAMIC_STATE
			{
				// Calculate color modulation from various parameters
				float flColorMod = 1.0f;
				float flOverbright = params[OVERBRIGHTFACTOR]->GetFloatValue();
				float flAddSelf = params[ADDSELF]->GetFloatValue();
				float flAdd2nd = params[ADDBASETEXTURE2]->GetFloatValue();
				
				// Combine color modulation factors
				flColorMod = flOverbright + flAddSelf + flAdd2nd;
				
				SetColorState( COLOR, true );
				pShaderAPI->Color3f( flColorMod, flColorMod, flColorMod );
				BindTexture( SHADER_SAMPLER0, BASETEXTURE, FRAME );
			}
			Draw();
			
			// Second pass for additive blending if needed
			if ( bAdditive2ndTexture || bAddSelf )
			{
				SHADOW_STATE
				{
					pShaderShadow->EnableDepthWrites( false );
					pShaderShadow->EnableBlending( true );
					pShaderShadow->BlendFunc( SHADER_BLEND_ONE, SHADER_BLEND_ONE );
					pShaderShadow->EnableTexture( SHADER_SAMPLER0, true );
					pShaderShadow->DrawFlags( SHADER_DRAW_POSITION | SHADER_DRAW_TEXCOORD0 | SHADER_DRAW_COLOR );
					FogToBlack();
				}
				DYNAMIC_STATE
				{
					float flSecondPassMod = params[ADDBASETEXTURE2]->GetFloatValue() + params[ADDSELF]->GetFloatValue();
					pShaderAPI->Color3f( flSecondPassMod, flSecondPassMod, flSecondPassMod );
					BindTexture( SHADER_SAMPLER0, BASETEXTURE, FRAME );
				}
				Draw();
			}
			break;
			
		case kRenderTransAddFrameBlend:
			{
				float flFrame = params[FRAME]->GetFloatValue();
				float flFade = params[ALPHA]->GetFloatValue();
				float flOverbright = params[OVERBRIGHTFACTOR]->GetFloatValue();
				
				SHADOW_STATE
				{
					pShaderShadow->EnableCulling( false );
					if( params[ IGNOREVERTEXCOLORS ]->GetIntValue() )
					{
						pShaderShadow->DrawFlags( SHADER_DRAW_POSITION | SHADER_DRAW_TEXCOORD0 );
					}
					else
					{
						pShaderShadow->DrawFlags( SHADER_DRAW_POSITION | SHADER_DRAW_TEXCOORD0 | SHADER_DRAW_COLOR );
					}
					pShaderShadow->EnableConstantColor( true );
					pShaderShadow->EnableDepthWrites( false );
					pShaderShadow->EnableBlending( true );
					pShaderShadow->BlendFunc( SHADER_BLEND_SRC_ALPHA, SHADER_BLEND_ONE );
					pShaderShadow->EnableTexture( SHADER_SAMPLER0, true );
					FogToBlack();
				}
				DYNAMIC_STATE
				{
					float frameBlendAlpha = 1.0f - ( flFrame - ( int )flFrame );
					float flColorMod = flFade * frameBlendAlpha * flOverbright;
					pShaderAPI->Color3f( flColorMod, flColorMod, flColorMod );
					ITexture *pTexture = params[BASETEXTURE]->GetTextureValue();
					BindTexture( SHADER_SAMPLER0, pTexture, ( int )flFrame );
				}
				Draw();
				
				// Second frame blend pass
				SHADOW_STATE
				{
					FogToBlack();
				}
				DYNAMIC_STATE
				{
					float frameBlendAlpha = ( flFrame - ( int )flFrame );
					float flColorMod = flFade * frameBlendAlpha * flOverbright;
					pShaderAPI->Color3f( flColorMod, flColorMod, flColorMod );
					ITexture *pTexture = params[BASETEXTURE]->GetTextureValue();
					int numAnimationFrames = pTexture->GetNumAnimationFrames();
					BindTexture( SHADER_SAMPLER0, pTexture, ( ( int )flFrame + 1 ) % numAnimationFrames );
				}
				Draw();
			}
			break;
			
		default:
			ShaderWarning( "shader Spritecard_DX6: Unknown sprite render mode\n" );
			break;
		}
	}
END_SHADER 