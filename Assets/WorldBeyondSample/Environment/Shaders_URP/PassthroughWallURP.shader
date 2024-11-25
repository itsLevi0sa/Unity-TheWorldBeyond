// Copyright (c) Meta Platforms, Inc. and affiliates.

Shader "TheWorldBeyond/PassthroughWallURP"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}
        _EffectPosition("Effect Position", Vector) = (0,1000,0,1)
        _EffectTimer("Effect Timer", Range(0.0,1.0)) = 1.0
        _InvertedMask("Inverted Mask", float) = 1
        _PatternTiling("Pattern Tiling", float) = 1

        [Header(DepthTest)]
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest("ZTest", Float) = 4 //"LessEqual"
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOpColor("Blend Color", Float) = 2 //"ReverseSubtract"
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOpAlpha("Blend Alpha", Float) = 3 //"Min"
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" }
        LOD 100

        Pass
        {
            Name"FORWARD"
            Tags { "LightMode" = "UniversalForward" }
            
            // Use ZWrite and ZTest appropriate for URP
            ZWrite Off
            ZTest [_ZTest]
            BlendOp [_BlendOpColor], [_BlendOpAlpha]
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float4 vertWorld : TEXCOORD1;
                float2 uv : TEXCOORD0;
                float4 vertexColor : COLOR;
                float3 objectScale : TEXCOORD2;
                half4 sin : TEXCOORD3;
            };

            // Properties
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST; // Reintroducing _MainTex_ST for texture tiling and offset

            float4 _EffectPosition;
            float _EffectTimer;
            float _InvertedMask;
            float _PatternTiling;

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionHCS = TransformObjectToHClip(v.positionOS);
                o.vertWorld = mul(unity_ObjectToWorld, v.positionOS);

                // Apply texture transformations using _MainTex_ST
                o.uv = TRANSFORM_TEX(v.uv, _MainTex); // Apply tiling/offset via _MainTex_ST

                o.vertexColor = (1 - v.color) * 4;

                // Calculate the object scale based on the object matrix
                half3x3 m = (half3x3)UNITY_MATRIX_M;
                o.objectScale = half3(
                    length(half3(m[0][0], m[1][0], m[2][0])),
                    length(half3(m[0][1], m[1][1], m[2][1])),
                    length(half3(m[0][2], m[1][2], m[2][2]))
                );
                
                // Sinusoidal animation based on time
                o.sin.x = sin(_Time.y + 0.0) * 0.5 + 0.5;
                o.sin.y = sin(_Time.y + 1.0) * 0.5 + 0.5;
                o.sin.z = sin(_Time.y + 2.0) * 0.5 + 0.5;
                o.sin.w = sin(_Time.y + 3.0) * 0.5 + 0.5;

                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                // Distance calculation for the effect
                float radialDist = distance(i.vertWorld, _EffectPosition) * 10;
                float dist = saturate(radialDist + 1 - _EffectTimer * 50);
                if (_EffectTimer >= 1.0)
                {
                    dist = 0;
                }

                // Sampling the main texture
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                // Animated color based on sine wave
                half colAnimatedR = saturate((col.r * 5) - ((i.sin.x * 5) + i.vertexColor.r));
                half colAnimatedG = saturate((col.g * 5) - ((i.sin.y * 5) + i.vertexColor.r));
                half colAnimatedB = saturate((col.b * 5) - ((i.sin.z * 5) + i.vertexColor.r));
                half colAnimatedA = saturate((col.a * 5) - ((i.sin.w * 5) + i.vertexColor.r));

                // Calculate the alpha based on inverted mask
                float alpha = lerp(dist, 1 - dist, _InvertedMask);
                float final = alpha * saturate(colAnimatedR + colAnimatedG + colAnimatedB + colAnimatedA);

                return float4(final, final, final, final);
            }

            ENDHLSL
        }
    }

    FallBack "Universal Forward"
}
