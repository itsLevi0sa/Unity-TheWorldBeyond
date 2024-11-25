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
        _LightingRamp("Lighting Ramp", 2D) = "white" {}
        _MainTex("MainTex", 2D) = "white" {}
        _TriPlanarFalloff("Triplanar Falloff", Range(0, 10)) = 1
        _OppyPosition("Oppy Position", Vector) = (0, 1000, 0, 0)
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
            Name "Base"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.0
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariables.hlsl"

            // Attributes and Varying structs for the vertex and fragment shaders
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 worldNormal : TEXCOORD1;
                float3 worldViewDirection : TEXCOORD2;
                half foggingRange : TEXCOORD3;
                float3 lightDir : TEXCOORD4;
            };

            // Uniforms and samplers
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURECUBE(_FogCubemap);
            SAMPLER(sampler_FogCubemap);
            TEXTURE2D(_LightingRamp);
            SAMPLER(sampler_LightingRamp);

            float _FogStartDistance;
            float _FogEndDistance;
            float _FogExponent;
            float _SaturationAmount;
            float _FogStrength;
            float4 _Color;
            float _TriPlanarFalloff;
            float3 _OppyPosition;
            float _OppyRippleStrength;
            float _MaskRippleStrength;
            float4 _EffectPosition;
            float _EffectTimer;
            float _InvertedMask;

            // Triplanar sampler function (used for texture blending)
            half4 TriplanarSampler(sampler2D projectedTexture, float3 worldPos, float3 normalSign, float3 projNormal, half2 tiling)
            {
                half4 xNorm = tex2D(projectedTexture, tiling * worldPos.zy * half2(normalSign.x, 1.0) + _MainTex_ST.zw);
                half4 yNorm = tex2D(projectedTexture, tiling * worldPos.xz * half2(normalSign.y, 1.0) + _MainTex_ST.zw);
                half4 zNorm = tex2D(projectedTexture, tiling * worldPos.xy * half2(-normalSign.z, 1.0) + _MainTex_ST.zw);
                return (xNorm * projNormal.x) + (yNorm * projNormal.y) + (zNorm * projNormal.z);
            }

            // Vertex shader
            Varyings vert(Attributes v)
            {
                Varyings o;

                // Transform position and normal
                o.worldNormal = TransformObjectToWorldNormal(v.normalOS);
                o.positionHCS = TransformObjectToHClip(v.positionOS);
                o.worldPos = mul(unity_ObjectToWorld, v.positionOS).xyz;
                o.worldViewDirection = normalize(_WorldSpaceCameraPos - o.worldPos);

                o.lightDir = normalize(_WorldSpaceLightPos0.xyz - o.worldPos);
                o.foggingRange = saturate((distance(_WorldSpaceCameraPos, o.worldPos) - _FogStartDistance) / (_FogEndDistance - _FogStartDistance));
                o.foggingRange = pow(o.foggingRange, _FogExponent);

                return o;
            }

            // Fragment shader
            half4 frag(Varyings i) : SV_Target
            {
                // Sample the main texture with triplanar mapping
                half4 mainTexture = TriplanarSampler(_MainTex, i.worldPos, i.lightDir, i.lightDir, _MainTex_ST.xy);

                // Distance gradient (for ripple effect)
                half distanceToOppy = pow(distance(_OppyPosition, i.worldPos), 1.5);
                half distanceToOppyMask = saturate(1 - (distanceToOppy * 0.2));
                half distanceRipple = saturate(sin((distanceToOppy * 6) + (_Time.w * 2)) * 0.5 + 0.25) * distanceToOppyMask * 4;

                // Noisy mask for texture blending
                half noisyMask = ((((_Time.y * 0.06 + (mainTexture.b * 1.73)) + (_Time.y * 0.19 + (mainTexture.g * 1.52))) % 1.0));
                noisyMask = abs(noisyMask - 0.5) * 2;

                // Lighting calculation using the lighting ramp
                half lambert = dot(i.worldNormal, i.lightDir) * 0.5 + 0.5;
                half4 lightingRamp = tex2D(_LightingRamp, half2(lambert, 0));
                half4 finalLighting = (half4(_LightColor0.rgb, 0.0) * lightingRamp) + half4(UNITY_LIGHTMODEL_AMBIENT.xyz, 0);
                half4 litTexture = finalLighting * _Color + (mainTexture.rrrr * ((noisyMask * 0.85) + (distanceRipple * _OppyRippleStrength)));

                // Fogging effect
                half4 foggingColor = texCUBE(_FogCubemap, i.worldViewDirection);
                half4 foggedColor = lerp(litTexture, foggingColor, i.foggingRange * _FogStrength);

                // Desaturation effect (luminance)
                half desaturatedColor = dot(foggedColor.rgb, half3(0.299, 0.587, 0.114));

                // Saturation adjustment based on fogging range
                half3 finalColor = lerp(desaturatedColor.xxx, foggedColor.rgb, _SaturationAmount);
                finalColor = pow(finalColor, 0.455);

                // Clip out pixels based on effect position (used for ring effects)
                float radialDist = distance(i.worldPos, _EffectPosition) * 10;
                float dist = saturate(radialDist + 5 - _EffectTimer * 50);
                if (_EffectTimer >= 1.0) {
                    dist = 0;
                }

                float alpha = lerp(dist, 1 - dist, _InvertedMask);
                clip(alpha.r - 0.5);

                // Ripple effect mask based on the distance from the `OppyPosition`
                half distanceToBall = distance(_OppyPosition, i.worldPos);
                half maskRipple = saturate(sin((distanceToBall * 20) + (_Time.w * 2)) * 0.5 + 0.25) * saturate(1 - (distanceToBall * 0.5)) * 0.7;
                maskRipple *= saturate((distanceToBall - 0.2) * 5);
                return half4(finalColor, maskRipple * _MaskRippleStrength);
            }

            ENDHLSL
        }
    }

    Fallback "UniversalForward"
}
