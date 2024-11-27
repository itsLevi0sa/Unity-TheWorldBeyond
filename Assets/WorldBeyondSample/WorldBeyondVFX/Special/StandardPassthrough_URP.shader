Shader "TheWorldBeyond/StandardPassthrough_URP"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}
        _InvertedAlpha("Inverted Alpha", float) = 1

        [Header(DepthTest)]
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull", Float) = 2 // Back
        [Enum(Off,0,On,1)] _ZWrite("ZWrite", Float) = 0 // Off
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest("ZTest", Float) = 4 // LessEqual
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOpColor("Blend Color", Float) = 2 // ReverseSubtract
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOpAlpha("Blend Alpha", Float) = 3 // Min
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" }
        LOD 100

        Pass
        {
            Cull[_Cull]
            ZWrite[_ZWrite]
            ZTest[_ZTest]
            BlendOp[_BlendOpColor],[_BlendOpAlpha]
            Blend SrcAlpha OneMinusSrcAlpha, One One

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Input structure for vertex data
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            // Output structure for vertex data to fragment shader
            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            // Texture property
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST; // Texture transformation matrix
            float _InvertedAlpha; // Inverted Alpha property

            // Vertex shader function
            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex); // Use URP's TransformObjectToHClip
                o.uv = TRANSFORM_TEX(v.uv, _MainTex); // Apply texture transformation
                return o;
            }

            // Fragment shader function
            half4 frag(v2f i) : SV_Target
            {
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv); // Sample the texture
                float alpha = lerp(col.r, 1 - col.r, _InvertedAlpha); // Apply the inverted alpha logic
                return half4(0, 0, 0, alpha); // Set RGB to 0, and use calculated alpha
            }

            ENDHLSL
        }
    }

    Fallback "Universal Forward"
}
