Shader "TheWorldBeyond/ToonFoggy_URP"
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

        _Color("Color", Color) = (0, 0, 0, 0)
        _Overbrightening("Overbrightening", Range(0, 2)) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry+0" }
        LOD 100

        Pass
        {
            Name "Base"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // Attribute struct for the vertex shader
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            // Varying struct for passing data between vertex and fragment shaders
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 worldNormal : TEXCOORD0;
                float2 uv : TEXCOORD1;
                float3 worldViewDirection : TEXCOORD2;
                half foggingRange : TEXCOORD3;
            };

            // Uniforms and samplers
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURECUBE(_FogCubemap);
            SAMPLER(sampler_FogCubemap);

            float _FogStartDistance;
            float _FogEndDistance;
            float _FogExponent;
            float _SaturationDistance;
            float _FogStrength;
            float4 _Color;
            float _Overbrightening;

            half3 fastPow(half3 a, half b)
            {
                return a / ((1.0 - b) * a + b);
            }

            // Vertex shader
            Varyings vert(Attributes v)
            {
                Varyings o;

                // Transform position and normal
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS);
                o.positionHCS = vertexInput.positionCS;
                o.worldNormal = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;

                // World position and view direction
                float3 worldPos = TransformObjectToWorld(v.positionOS);
                o.worldViewDirection = normalize(GetWorldSpaceViewDir(worldPos));

                // Calculate fogging range based on distance from the camera
                o.foggingRange = saturate((distance(GetCameraPositionWS(), worldPos) - _FogStartDistance) / (_FogEndDistance - _FogStartDistance));
                o.foggingRange = fastPow(o.foggingRange, _FogExponent);

                return o;
            }

            // Fragment shader
            float4 frag(Varyings i) : SV_Target
            {
                // Sample the main texture
                float4 mainTexture = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                // Fogging effect
                float4 foggingColor = SAMPLE_TEXTURECUBE(_FogCubemap, sampler_FogCubemap, i.worldViewDirection);

                // Apply fog strength and blending
                float4 foggedColor = lerp(mainTexture, foggingColor, i.foggingRange * _FogStrength);

                // Apply overbrightening and color adjustment
                foggedColor *= _Color * _Overbrightening;

                // Desaturation (luminance)
                float desaturatedColor = dot(foggedColor.rgb, float3(0.299, 0.587, 0.114));

                // Saturation adjustment based on fogging range
                float satDistance = saturate((_SaturationDistance * 11) - (i.foggingRange * 10));
                float3 finalColor = lerp(foggedColor.rgb, desaturatedColor, satDistance);
                finalColor = pow(finalColor, 2.2); // Gamma correction

                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }

    FallBack "UniversalForward"
}
