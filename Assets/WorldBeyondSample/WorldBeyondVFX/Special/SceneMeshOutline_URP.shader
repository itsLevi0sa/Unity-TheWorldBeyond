// Copyright (c) Meta Platforms, Inc. and affiliates.

Shader "TheWorldBeyond/SceneMeshOutlineURP"
{
    Properties
    {
        _EdgeColor("Edge Color", Color) = (1,1,1,1)
        _EffectPosition("Effect Position", Vector) = (0,1000,0,1)
        _EffectRadius("Effect Radius", float) = 1
        _EffectIntensity("Effect Intensity", float) = 1
        _EdgeTimeline("Edge Anim Timeline", float) = 1
        _CeilingHeight("CeilingHeight", float) = 1
        [IntRange] _StencilRef("Stencil Reference Value", Range(0, 255)) = 0
    }

    SubShader
    {
        // Set the render queue to "Geometry-3"
        Tags { "RenderType"="Transparent" "Queue"="Geometry-3" }
        LOD 100

        // First pass: stencil operations to mark the stencil buffer
        Pass
        {
            Name "OUTLINE"
            Tags { "LightMode" = "UniversalForward" }

            Stencil {
                Ref[_StencilRef]
                Comp NotEqual
                Pass Replace
            }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            ColorMask RGB

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 position : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 vertWorld : TEXCOORD1;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.vertex = TransformObjectToHClip(v.position);
                o.uv = v.uv;
                o.vertWorld = mul(unity_ObjectToWorld, v.position);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 mask = half4(1, 1, 1, 0);
                return mask;
            }
            ENDHLSL
        }

        // Second pass: render the outline with effect based on distance
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "UniversalForward" }

            Stencil {
                Ref[_StencilRef]
                Comp Equal
                Pass Keep
            }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            ColorMask RGB

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 color : TEXCOORD1;
                float4 vertWorld : TEXCOORD2;
                float4 vertex : SV_POSITION;
            };

            // Edge effect uniforms
            float4 _EdgeColor;
            float4 _EffectPosition;
            float _EffectRadius;
            float _EffectIntensity;
            float _EdgeTimeline;
            float _CeilingHeight;

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                o.color = v.color;
                o.vertWorld = mul(unity_ObjectToWorld, v.vertex);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // Glow effect based on vertex color
                float glow = 1 - pow(i.color.r, 0.2);
                float stroke = 1 - step(0.03, i.color.r);
                float edgeReveal = (i.vertWorld.y * 10) + (_EdgeTimeline * 11 * _CeilingHeight) - (_CeilingHeight * 10);

                // Combine edge effects with color
                float edgeEffect = saturate(glow * 0.5 + stroke);
                float4 col = edgeEffect * _EffectIntensity * _EdgeColor * saturate(edgeReveal);

                // Calculate light intensity based on distance from the effect position
                float lightIntensity = distance(i.vertWorld, _EffectPosition) / _EffectRadius;
                lightIntensity = pow(saturate(lightIntensity), 0.9);
                col.a = lightIntensity * 0.97;

                return col;
            }
            ENDHLSL
        }
    }

    Fallback "UniversalForward"
}
