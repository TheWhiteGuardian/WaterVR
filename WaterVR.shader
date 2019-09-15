// Massive thanks to https://catlikecoding.com/unity/tutorials/flow/texture-distortion/

Shader "TWG/WaterVR"
{
    Properties
    {
		// Standard material properties. Both are affected by the noise.
		[NoScaleOffset]_MainTex("Main Texture", 2D) = "white" {}
		[NoScaleOffset]_BumpMap("Normal Map", 2D) = "bump" {}

		// Both albedo and alpha are multiplied by this value.
        _Color ("Color", Color) = (1,1,1,1)

		// Global time scalar for the animation.
		_TimeScale("Time Scale", Float) = 1

		// Global space scalar for the animation.
		_GlobalScale("Global Scale Multiplier", Float) = 1

		// Provides a slight displacement between animation iterations.
		_OffsetX("Offset per cycle, X", Float) = .125
		_OffsetY("Offset per cycle, Y", Float) = .125

		// The most important texture as it defines the animation
		// R and G channels represent the x and y components of the displacement vector, where a value of 0.5 means 'no displacement'.
		// The B channel isn't as important and can be any noise, so long as it results in a non-homogenous distribution of values.
		// This is because the B channel noise is used to mask the reset of the animation loop by ensuring that it doesn't play everywhere at once.
		[NoScaleOffset]_NoiseTex("Noise Texture (RG: distortion vector, B: noise)", 2D) = "black" {}

		// Changes the displacement texture relative to the world times _GlobalScale.
		_NoiseScale("Noise Scale", Float) = 1

		// Scales the displacement vector length.
		_NoiseStrength("Noise Strength", Float) = 1

		// Offsets the animation's initial position.
		_NoiseOffset("Noise Phase Offset", Float) = 0

		// Parameters for tweaking the position and transition roughness of the fresnel effects.
		_FresnelScale("Fresnel Scale", Float) = 1
		_FresnelOffset("Fresnel Offset", Float) = 0
		_ReflScale("Reflection Fresnel Scale", Float) = 1
		_ReflOffset("Reflection Fresnel Offset", Float) = 0
    }



    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
		
		// Uncomment this if necessary, I just left it out because this shader doesn't do well with underwater view.
		// Cull Off

        LOD 200

        CGPROGRAM
		// Since we're doing reflections manually, we can get away with simpler lighting models.
        #pragma surface surf Lambert alpha:fade

		// Unity defined this, but perhaps it can be increased further.
        #pragma target 3.0

        struct Input
        {
			float3 worldPos;
			float3 viewDir;
			float3 worldRefl;
			INTERNAL_DATA
        };

		sampler2D _NoiseTex;
		sampler2D _MainTex;
		sampler2D _BumpMap;
        fixed4 _Color;
		float _OffsetX, _OffsetY, _NoiseScale, _TimeScale, _NoiseStrength, _NoiseOffset;
		float _FresnelScale, _FresnelOffset, _ReflScale, _ReflOffset, _GlobalScale;
		
		// Displaces the entered texture coordinates to create the animation loop.
		float3 ComputeUV(float2 worldUV, float timeOffset, half3 noise, float time)
		{
			float phase = frac(time + timeOffset);
			
			float jumpVar = time - phase;
			float2 jump = float2(jumpVar * _OffsetX, jumpVar * _OffsetY);

			float3 output;
			output.xy = worldUV - (noise.rg * (phase + _NoiseOffset));
			output.xy *= _NoiseScale;
			output.xy += timeOffset + jump;
			output.z = 1 - abs(1 - 2 * phase);
			return output;
		}

		// Samples the reflection from any nearby reflection probe, or otherwise from the skybox.
		half3 GetReflection(float3 direction)
		{
			half4 sky = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, direction);
			return DecodeHDR(sky, unity_SpecCube0_HDR);
		}

        void surf (Input IN, inout SurfaceOutput o)
        {
			half3 noise = tex2D(_NoiseTex, IN.worldPos.xz * _GlobalScale).rgb;

			// De-normalize to -1<x<1 so we can also have displacement in the opposite direction.
			noise.xy = ((noise.xy * 2) - 1) * _NoiseStrength;
			float time = (_Time.y * _TimeScale) + noise.b;

			// We use two texture layers so we can mask the animation reset of either by hiding behind the other.
			float3 uv1 = ComputeUV(IN.worldPos.xz, 0.0, noise, time);
			float3 uv2 = ComputeUV(IN.worldPos.xz, 0.5, noise, time);

			// Base color finalize, we'll have to wait until after normals are done to assign though so we can add reflections to the stack.
			fixed4 c = _Color * ((tex2D(_MainTex, uv1.xy) * uv1.z) + (tex2D(_MainTex, uv2.xy) * uv2.z));

			// Messy, but it works
			o.Normal = normalize(
			UnpackNormal(tex2D(_BumpMap, uv1.xy)) * uv1.z +
			UnpackNormal(tex2D(_BumpMap, uv2.xy)) * uv2.z
			);

			// Compute the transparency fresnel and the reflection fresnel. They don't use the same value for artist control.
			float fresnel = 1 - dot(IN.viewDir, o.Normal);
			float reFresnel = (fresnel * _ReflScale) + _ReflOffset;
			reFresnel = saturate(reFresnel);
			fresnel = (fresnel * _FresnelScale) + _FresnelOffset;
			fresnel = saturate(fresnel);
			
			// We have the normal map now, let's sample the cubemap with the normal taken into account
			half3 reflection = GetReflection(WorldReflectionVector(IN, o.Normal));

			// Now we blend in reflection and transparency
			o.Albedo = lerp(c.rgb, reflection, reFresnel);
			o.Alpha = lerp(c.a, 1, fresnel);

			// And that's a wrap.
        }
        ENDCG
    }
}