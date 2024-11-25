Shader "TheWorldBeyond/ToonSky_URP"
{
    Properties
    {
        _SaturationDistance("Saturation Distance", Range(0, 1)) = 1
        _FogCubemap("Fog Cubemap", CUBE) = "white" {}
        _FogStrength("Fog Strength", Range(0, 1)) = 1
        _FogStartDistance("Fog Start Distance", Range(0, 100)) = 1
        _FogEndDistance("Fog End Distance", Range(0, 2000)) = 100
        _FogExponent("Fog Exponent", Range(0, 1)) = 1
        _MainTex("MainTex", 2D) = "white" {}

        _CloudColor("Cloud Color", Color) = (0, 0, 0, 0)
        _CloudMixStrength("Cloud Mix Strength", Range(0, 1)) = 1

        _MountainColor("Mountains Color", Color) = (0, 0, 0, 0)
        _MountainMixStrength("Mountain Mix Strength", Range(0, 1)) = 1
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
                float3 worldNormal : TEXCOORD0;
                float2 uv : TEXCOORD1;
                float3 worldViewDirection : TEXCOORD2;
                half foggingRange : TEXCOORD3;
            };

            // Uniforms
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURECUBE(_FogCubemap);
            SAMPLER(sampler_FogCubemap);

            float _FogStartDistance;
            float _FogEndDistance;
            float _FogExponent;
            float _SaturationDistance;
            float _FogStrength;
            float _CloudMixStrength;
            float _MountainMixStrength;
            float4 _CloudColor;
            float4 _MountainColor;

            half3 fastPow(half3 a, half b)
            {
                return a / ((1.0 - b) * a + b);
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS);
                o.positionHCS = vertexInput.positionCS;
                o.worldNormal = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv * float2(2, 1);
                float3 worldPos = TransformObjectToWorld(v.positionOS);
                o.worldViewDirection = normalize(GetWorldSpaceViewDir(worldPos));
                o.foggingRange = saturate((distance(GetCameraPositionWS(), worldPos) - _FogStartDistance) / (_FogEndDistance - _FogStartDistance));
                o.foggingRange = fastPow(o.foggingRange, _FogExponent);

                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                // Main texture
                float4 mainTexture = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                // Fogging
                float4 foggingColor = SAMPLE_TEXTURECUBE(_FogCubemap, sampler_FogCubemap, i.worldViewDirection);

                // Clouds
                float4 clouds = lerp(foggingColor, _CloudColor, mainTexture.r * _CloudMixStrength);

                // Mountains
                float4 mountains = lerp(foggingColor, _MountainColor, mainTexture.g * _MountainMixStrength);

                // Combine mountains over clouds
                float4 mountainsOverClouds = lerp(clouds, mountains, mainTexture.b);

                // Desaturate
                float desaturatedColor = dot(mountainsOverClouds.rgb, float3(0.299, 0.587, 0.114));

                // Saturate with distance
                float satDistance = saturate((_SaturationDistance * 11) - (i.foggingRange * 10));
                float3 finalColor = lerp(mountainsOverClouds.rgb, desaturatedColor, satDistance);
                finalColor = pow(finalColor, 2.2);

                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}
