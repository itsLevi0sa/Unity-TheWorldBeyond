Shader "TheWorldBeyond/PassthroughShadow_URP"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}

        [Header(DepthTest)]
        [Enum(Off,0,On,1)] _ZWrite("ZWrite", Float) = 0
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest("ZTest", Float) = 4
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOpColor("Blend Color", Float) = 2
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOpAlpha("Blend Alpha", Float) = 3
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" }
        LOD 100

        Pass
        {
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
            float4 _MainTex_ST; // Explicitly declare _MainTex_ST

            // Vertex shader function
            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex); // Use URP's TransformObjectToHClip
                o.uv = TRANSFORM_TEX(v.uv, _MainTex); // Correct texture transform
                return o;
            }

            // Fragment shader function
            half4 frag(v2f i) : SV_Target
            {
                half4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                return half4(0, 0, 0, col.a); // Output only alpha
            }

            ENDHLSL
        }
    }

    Fallback "Universal Forward"
}
