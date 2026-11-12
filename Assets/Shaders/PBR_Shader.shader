Shader "Custom/PBR_Shader"
{
    // holds material properties (i.e. textures, vectors, etc.)
    Properties
    {
        _FragColor("Color", Color) = (1, 0, 0, 1)

        _DiffuseTex("Diffuse Texture", 2D) = "" {}
        _NormalMap("Normal Map", 2D) = "" {}

        _AlbedoMap("Albedo", 2D) = "" {}
        _AOMap("AO", 2D) = "" {}
        _MetallicMap("Metallic", 2D) = "" {}
        _RoughnessMap("Roughness", 2D) = "" {}
    }

    SubShader
    {
        // assign key-value pairs of data
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        // shader code goes here
        Pass
        {
            HLSLPROGRAM

            // define vertex & fragment shaders
            #pragma vertex Vertex
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct vertexdata {
                float3 pos : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f {
                float4 clipPos : SV_POSITION;
                float3 viewPos : POSITION1;
                float3 worldPos : POSITION2;

                float2 uv : TEXCOORD;
                float3 normal : NORMAL;
                float3 tangent : TANGENT0;
                float3 bitangent : TANGENT1;
            };

            // ---light variables---
            CBUFFER_START(LightVariables)
                float3 lightDir;
                float3 lightColor;
            CBUFFER_END

            // ---material variables---
            CBUFFER_START(MaterialVariables)
                float4 _FragColor;

                sampler2D _DiffuseTex;
                sampler2D _NormalMap;

                sampler2D _AlbedoMap;
                sampler2D _AOMap;
                sampler2D _MetallicMap;
                sampler2D _RoughnessMap;
            CBUFFER_END

            // ---SHADERS---
            // vertex shader
            v2f Vertex(vertexdata vert) {
                v2f frag;

                // returns vertex's position in world, view, and clip space
                VertexPositionInputs inputPos = GetVertexPositionInputs(vert.pos);
                // returns vertex's normal, tangents, & bitangents
                VertexNormalInputs inputNorm = GetVertexNormalInputs(vert.normal, vert.tangent);
                
                // vert (out) -> frag (in)
                frag.clipPos = inputPos.positionCS; // position vars
                frag.viewPos = inputPos.positionVS;
                frag.worldPos = inputPos.positionWS;

                frag.uv = vert.uv; // texture vars

                frag.normal = inputNorm.normalWS; // normal vars
                frag.tangent = inputNorm.tangentWS;
                frag.bitangent = inputNorm.bitangentWS;
                
                return frag;
            }

            // fragment shader
            float4 Frag(v2f frag) : SV_TARGET {

                // sample textures
                float3 diffuseTex = tex2D(_DiffuseTex, frag.uv);
                
                // ---TBN matrix---
                float3 unpackedNormal = tex2D(_NormalMap, frag.uv).rgb * 2 - 1; 
                
                float3 T_mat = normalize(frag.tangent);
                float3 B_mat = normalize(frag.bitangent);
                float3 N_mat = normalize(frag.normal);
                float3x3 TBN = float3x3(T_mat, B_mat, N_mat);
                
                float3 normalMap = normalize(mul(TBN, unpackedNormal));
                
                float3 albedo = tex2D(_AlbedoMap, frag.uv);
                float metallic = tex2D(_MetallicMap, frag.uv).r;
                float roughness = tex2D(_RoughnessMap, frag.uv).r;
                roughness = max(roughness, 0.04);
                float ao = tex2D(_AOMap, frag.uv).r;

                // ---lighting setup---
                Light light = GetMainLight();
                lightColor = light.color;

                // standard light calculations
                float3 N = normalize(normalMap); // normal vector
                float3 V = normalize(_WorldSpaceCameraPos - frag.worldPos); // view vector

                float3 Lo = float3(0.0, 0.0, 0.0); 

                // ---PBR calculation---
                float3 L = normalize(light.direction); // incoming light vector
                float3 H = normalize(V + L); // halfway vector

                // attenuation (only for point lights)
                /*
                float distance = length(lightPos - frag.worldPos);
                float attenuation = 1.0 / (distance * distance); 
                float3 radiance = lightColor * attenuation;
                */

                // Cook-Torrance BRDF: specular
                // D(x): distribution GGX
                float a = roughness * roughness;
                float a2 = a*a;
                float NdotH = max(dot(N, H), 0.0);
                float NdotH2 = NdotH * NdotH;

                float d_num = a2;
                float d_denom = (NdotH2 * (a2 - 1.0) + 1.0);
                d_denom = PI * d_denom * d_denom;

                float D = d_num / d_denom;

                // F(0): fresnel Schlick
                float3 F0 = float3(0.04, 0.04, 0.04);
                F0 = lerp(F0, albedo, metallic); // for metallic surfaces
                float cosTheta = max(dot(H, V), 0.0);
                
                float3 F = F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);

                // G(x): smith + schlick
                float r = (roughness + 1.0); // schlick 
                float k = (r*r) / 8.0;
                float NdotV = max(dot(N, V), 0.0);
                float NdotL = max(dot(N, L), 0.0);

                float g1_num = NdotV; // ggx1
                float g1_denom = NdotV * (1.0 - k) + k;
                float g2_num = NdotL; // ggx2
                float g2_denom = NdotL * (1.0 - k) + k;
            
                float ggx1 = g1_num / g1_denom;
                float ggx2 = g2_num / g2_denom;

                float G = ggx1 * ggx2;

                // Cook-Torrance BRDF full equation
                float3 DFG = D * F * G;
            
                float dfg_denom = 4.0 * max(NdotV * NdotL, 0.0) + 0.0001;

                // specular and diffuse
                float3 specular = DFG / dfg_denom;

                float3 kS = F;
                float3 kD = float3(1.0, 1.0, 1.0) - kS;
                kD *= 1.0 - metallic;

                // adding to light output
                Lo += (kD * albedo / PI + specular) * lightColor * NdotL;

                // add ambient
                float3 ambient = float3(0.01, 0.01, 0.01) * albedo * ao;
                float3 color = ambient + Lo;
                
                _FragColor = float4(color, 1.0);

                return _FragColor;
            }

            ENDHLSL
        }
    }
}
