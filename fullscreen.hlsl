struct vs_out
{
	float4 pos : SV_Position;
	float2 uv : TEXCOORD;
};

vs_out vs_main(uint id : SV_VertexID)
{
	vs_out o;

	float2 pos[3] =
	{
		float2(-1, -1),
        float2(-1, 3),
        float2(3, -1)
	};

	float2 uv[3] =
	{
		float2(0, 1),
        float2(0, -1),
        float2(2, 1)
	};

	o.pos = float4(pos[id], 0, 1);
	o.uv = uv[id];

	return o;
}

Texture2D inputTex : register(t0);
SamplerState samp : register(s0);

float4 ps_main(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	return inputTex.Sample(samp, uv);
}