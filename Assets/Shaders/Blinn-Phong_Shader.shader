Shader "Custom/Blinn-Phong_Shader"
{
    Properties
    {
        _DiffuseTex("Diffuse Texture", 2D) = "" {}

        _Shininess("Shininess", Float) = 0.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "LightMode" = "UniversalForward" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


            struct vertexdata
            {
                float4 pos : POSITION;
                float3 norm : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float3 positionVS : TEXCOORD2;

                float3 normalWS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            // material vars
            CBUFFER_START(Materials)
                sampler2D _DiffuseTex;

                float _Shininess;
            CBUFFER_END

            float3 tolinear(float3 sRGBColor) {
                float3 linearColor;

                // gamma factor
                float g = 2.2;
                linearColor = pow(sRGBColor, float3(g, g, g));

                return linearColor;
            }

            float3 blinnphong(v2f f) {
                // light vars
                Light light = GetMainLight();

                // material vars
                float3 material = tex2D(_DiffuseTex, f.uv).rgb;
                material = tolinear(material);

                // ambient
                float a = 0.2;
                float3 ambientFactor = float3(a, a, a);
                float3 ambient = light.color * ambientFactor * material;
                
                // diffuse
                float3 lightDir = normalize(light.direction);
                float3 normal = TransformObjectToWorldNormal(f.normalWS);
                normal = normalize(f.normalWS);
                float diffuseFactor = max(dot(lightDir, normal), 0.0);
                float3 diffuse = light.color * diffuseFactor * material;
                
                // specular
                float3 viewDir = f.positionVS;
                float3 halfwayDir = normalize(lightDir + viewDir);
                float spec = pow(max(dot(normal, halfwayDir), 0.0), _Shininess);
                float3 specular = light.color * spec;

                return float3(ambient + diffuse + specular);
            }

            // vertex shader
            v2f vert(vertexdata v) {
                v2f output;

                VertexPositionInputs input = GetVertexPositionInputs(v.pos);

                // send data to fragment shader
                output.positionCS = input.positionCS; // clip space
                output.positionWS = input.positionWS; // world space
                output.positionVS = GetWorldSpaceViewDir(output.positionWS); // view space

                output.normalWS = v.norm;
                output.uv = v.uv;

                return output;
            }

            // fragment shader
            float4 frag(v2f f) : SV_TARGET {

                // Blinn-Phong lighting
                float3 output = blinnphong(f);

                // gamma correction
                float g = 1.0 / 2.2;
                output = pow(output, float3(g, g, g));

                return float4(output, 1);
            }

            
            ENDHLSL
        }
    }
}
