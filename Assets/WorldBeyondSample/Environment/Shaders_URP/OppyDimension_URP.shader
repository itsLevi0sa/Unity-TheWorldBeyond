Shader "TheWorldBeyond/OppyDimension_URP"
{
    Properties
    {
        _SaturationAmount("Saturation Amount", Range(0, 1)) = 1
        _FogCubemap("Fog Cubemap", CUBE) = "white" {}
        _FogStrength("Fog Strength", Range(0, 1)) = 1
        _FogStartDistance("Fog Start Distance", Range(0, 100)) = 1
        _FogEndDistance("Fog End Distance", Range(0, 2000)) = 100
        _FogExponent("Fog Exponent", Range(0, 1)) = 1
        _MainTex("MainTex", 2D) = "white" {}
        _TriPlanarFalloff("Triplanar Falloff", Range(0, 10)) = 1
        _OppyPosition("Oppy Position", Vector) = (0,1000,0,0)
        _OppyRippleStrength("Oppy Ripple Strength", Range(0, 1)) = 1
        _MaskRippleStrength("Mask Ripple Strength", Range(0, 1)) = 0
        _Color("Color", Color) = (0, 0, 0, 0)
        _EffectPosition("Effect Position", Vector) = (0, 1000, 0, 1)
        _EffectTimer("Effect Timer", Range(0.0, 1.0)) = 1.0
        _InvertedMask("Inverted Mask", float) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalRenderPipeline" "RenderType" = "Opaque" }
        LOD 100

        Pass
        {
            Name "Main"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 worldPos : TEXCOORD0;   // Pass the world position
                float3 worldNormal : TEXCOORD1;
                float2 uv : TEXCOORD2;
                float3 worldViewDirection : TEXCOORD3;
                half foggingRange : TEXCOORD4;
            };

            // Uniforms
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURECUBE(_FogCubemap);
            SAMPLER(sampler_FogCubemap);

            float _FogStartDistance;
            float _FogEndDistance;
            float _FogExponent;
            float _FogStrength;
            float _SaturationAmount;
            float3 _OppyPosition;
            float _OppyRippleStrength;
            float _MaskRippleStrength;
            float4 _EffectPosition;
            float _EffectTimer;
            float _InvertedMask;

            half3 fastPow(half3 a, half b)
            {
                return a / ((1.0 - b) * a + b);
            }

            Varyings vert(Attributes v)
            {
                Varyings o;

                // Calculate world position and transform to clip space
                o.worldNormal = TransformObjectToWorldNormal(v.normalOS);
                o.positionHCS = TransformObjectToHClip(v.positionOS);
                o.worldPos = mul(unity_ObjectToWorld, v.positionOS).xyz;   // Store world position
                o.worldViewDirection = normalize(GetWorldSpaceViewDir(o.worldPos));

                // Calculate fogging range
                o.foggingRange = saturate((distance(GetCameraPositionWS(), o.worldPos) - _FogStartDistance) / (_FogEndDistance - _FogStartDistance));
                o.foggingRange = fastPow(o.foggingRange, _FogExponent);
                
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                // Main texture sampling
                float4 mainTexture = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                // Fogging effect
                float4 foggingColor = SAMPLE_TEXTURECUBE(_FogCubemap, sampler_FogCubemap, i.worldViewDirection);
                float4 foggedColor = lerp(mainTexture, foggingColor, i.foggingRange * _FogStrength);

                // Distance ripple effect
                float distanceToOppy = pow(distance(_OppyPosition, i.worldPos), 1.5);
                float distanceRipple = saturate(sin(distanceToOppy * 6 + (_Time.w * 2)) * 0.5 + 0.25);
                distanceRipple *= _OppyRippleStrength;

                // Mask ripple effect
                float maskRipple = saturate(sin(distanceToOppy * 20 + (_Time.w * 2)) * 0.5 + 0.25);
                maskRipple *= saturate(1 - (distanceToOppy * 0.5)) * 0.7;
                maskRipple *= _MaskRippleStrength;

                // Desaturating effect
                float desaturatedColor = dot(foggedColor.rgb, float3(0.299, 0.587, 0.114));
                float3 finalColor = lerp(desaturatedColor.xxx, foggedColor.rgb, _SaturationAmount);

                // Final color adjustment
                finalColor = pow(finalColor, 0.455);

                // Apply ripple effect and mask based on _EffectTimer
                float radialDist = distance(i.worldPos, _EffectPosition.xyz) * 10;
                float dist = saturate(radialDist + 5 - _EffectTimer * 50);
                if (_EffectTimer >= 1.0) {
                    dist = 0;
                }
                float alpha = lerp(dist, 1 - dist, _InvertedMask);
                clip(alpha.r - 0.5);

                // Apply ripple mask with adjusted intensity
                half distanceToBall = distance(_OppyPosition, i.worldPos);
                half finalRipple = saturate(sin((distanceToBall * 20) + (_Time.w * 2)) * 0.5 + 0.25) * saturate(1 - (distanceToBall * 0.5)) * 0.7;
                finalRipple *= saturate((distanceToBall - 0.2) * 5);

                return half4(finalColor, finalRipple * _MaskRippleStrength);
            }

            ENDHLSL
        }
    }

    Fallback "UniversalForward"
}
