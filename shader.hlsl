#define RENDER_WIDTH 1920
#define RENDER_HEIGHT 1080
#define ASPECT_RATIO (float)RENDER_WIDTH / RENDER_HEIGHT

#define FOV 100

#define SAMPLES_PER_PIXEL 8
#define MAX_BOUNCES 128
#define RR_CUTOFF 5

#define INF 3.4028235e38f
#define PI 3.14159265358979323846f

#define SHARED_SPHERE_COUNT 12
#define WHITE_FURNACE 0
#define TONEMAP 1

#if WHITE_FURNACE
	#define SKY_COLOR float3(1.0f, 1.0f, 1.0f)
#else
	#define SKY_COLOR float3(0.0f, 0.0f, 0.0f)
#endif

cbuffer cb : register(b0)
{
	float3 cam_pos;
	float fov_scale;

	float3 cam_forward;
	uint sphere_count;

	float3 cam_right;
	uint frame;

	float3 cam_up;
	float pad;
};

struct sphere_object
{
	float3 center;
	float radius;

	float3 albedo;
	float3 emission;

	float metallic;
	float roughness;
};

StructuredBuffer<sphere_object> spheres : register(t0);
groupshared sphere_object shared_spheres[SHARED_SPHERE_COUNT];

RWTexture2D<float4> accumulation : register(u0);
RWTexture2D<float4> output : register(u1);

static inline uint wang_hash(uint seed)
{
	seed = (seed ^ 61) ^ (seed >> 16);
	seed *= 9;
	seed = seed ^ (seed >> 4);
	seed *= 0x27d4eb2d;
	seed = seed ^ (seed >> 15);
	return seed;
}

static inline float rand(inout uint rng_state)
{
	rng_state *= 747796405u;
	rng_state += 2891336453u;
	rng_state ^= (rng_state >> 16);
	return (rng_state & 0x00FFFFFF) * (1.0 / 16777216.0);
}

static inline float luminance(float3 c)
{
	return dot(c, float3(0.2126f, 0.7152f, 0.0722f));
}

static inline void build_onb(float3 n, out float3 t, out float3 b)
{
	float sgn = n.z >= 0.0f ? 1.0f : -1.0f;
	float a = -1.0f / (sgn + n.z);
	float bb = n.x * n.y * a;

	t = float3(1.0f + sgn * n.x * n.x * a, sgn * bb, -sgn * n.x);
	b = float3(bb, sgn + n.y * n.y * a, -n.y);
}

static inline float3 get_ray_dir(uint2 pixel, float2 subpixel)
{
	float screen_x = 2.0f * ((pixel.x + subpixel.x) / RENDER_WIDTH) - 1.0f;
	float screen_y = 1.0f - 2.0f * ((pixel.y + subpixel.y) / RENDER_HEIGHT);
	return normalize(cam_forward + cam_right * screen_x * ASPECT_RATIO * fov_scale + cam_up * screen_y * fov_scale);
}

static inline bool ray_sphere_intersection(float3 ray_origin, float3 ray_dir, sphere_object sphere, out float t)
{
    float3 oc = ray_origin - sphere.center;
    float b = dot(oc, ray_dir);
    float c = dot(oc, oc) - sphere.radius * sphere.radius;
    float h = b * b - c;

    if (h < 0.0f)
		return false;
    h = sqrt(h);

    t = -b - h;
	float eps = 1e-4f * max(1.0f, length(ray_origin));
    if (t < eps)
		t = -b + h;

    return t > eps;
}

static inline float3 sample_cosine_hemisphere(float3 normal, inout uint rng_state)
{
	float u1 = rand(rng_state);
	float u2 = rand(rng_state);

	float r = sqrt(u1);
	float phi = 2.0f * PI * u2;

	float x = r * cos(phi);
	float y = r * sin(phi);
	float z = sqrt(max(0.0f, 1.0f - u1));

	float3 tangent, bitangent;
	build_onb(normal, tangent, bitangent);

	return normalize(x * tangent + y * bitangent + z * normal);
}

static inline float smith_G1(float NdotX, float a2)
{
	return 2.0f * NdotX / max(NdotX + sqrt(a2 + (1.0f - a2) * NdotX * NdotX), 1e-7f);
}

static inline float smith_G2(float NdotV, float NdotL, float a2)
{
	float lv = NdotL * sqrt(a2 + (1.0f - a2) * NdotV * NdotV);
	float ll = NdotV * sqrt(a2 + (1.0f - a2) * NdotL * NdotL);
	return 2.0f * NdotL * NdotV / max(lv + ll, 1e-7f);
}

static inline float3 fresnel_schlick(float3 F0, float cos_theta)
{
	float m = saturate(1.0f - cos_theta);
	float m2 = m * m;
	return F0 + (1.0f - F0) * (m2 * m2 * m);
}

static inline float3 sample_ggx_vndf(float3 Ve, float alpha, float u1, float u2)
{
	float3 Vh = normalize(float3(alpha * Ve.x, alpha * Ve.y, Ve.z));

	float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
	float3 T1 = lensq > 0.0f ? float3(-Vh.y, Vh.x, 0.0f) * rsqrt(lensq) : float3(1.0f, 0.0f, 0.0f);
	float3 T2 = cross(Vh, T1);

	float r = sqrt(u1);
	float phi = 2.0f * PI * u2;
	float t1 = r * cos(phi);
	float t2 = r * sin(phi);
	float s = 0.5f * (1.0f + Vh.z);
	t2 = (1.0f - s) * sqrt(max(0.0f, 1.0f - t1 * t1)) + s * t2;

	float3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0f, 1.0f - t1 * t1 - t2 * t2)) * Vh;
	return normalize(float3(alpha * Nh.x, alpha * Nh.y, max(0.0f, Nh.z)));
}

static inline bool sample_brdf(sphere_object s, float3 N, float3 V, inout uint rng_state, out float3 L, out float3 weight)
{
	L = float3(0.0f, 0.0f, 0.0f);
	weight = float3(0.0f, 0.0f, 0.0f);

	float NdotV = dot(N, V);
	if (NdotV <= 0.0f)
		return false;

	float metallic = saturate(s.metallic);

	float perceptual = saturate(s.roughness);
	float alpha = max(perceptual * perceptual, 1e-4f);
	float a2 = alpha * alpha;

	float3 F0 = lerp(float3(0.04f, 0.04f, 0.04f), s.albedo, metallic);
	float3 diffuse_color = s.albedo * (1.0f - metallic);

	float3 F_view = fresnel_schlick(F0, NdotV);

	float lum_s = luminance(F_view);
	float lum_d = luminance(diffuse_color) * (1.0f - lum_s);
	float p_spec = clamp(lum_s / max(lum_s + lum_d, 1e-4f), 0.05f, 0.95f);

	float3 tangent, bitangent;
	build_onb(N, tangent, bitangent);

	if (rand(rng_state) < p_spec)
	{
		float3 Ve = float3(dot(V, tangent), dot(V, bitangent), NdotV);
		float3 Hl = sample_ggx_vndf(Ve, alpha, rand(rng_state), rand(rng_state));
		float3 H = normalize(Hl.x * tangent + Hl.y * bitangent + Hl.z * N);

		L = normalize(reflect(-V, H));

		float NdotL = dot(N, L);

		if (NdotL <= 0.0f)
			return false;

		float3 F = fresnel_schlick(F0, saturate(dot(V, H)));
		float vis = smith_G2(NdotV, NdotL, a2) / max(smith_G1(NdotV, a2), 1e-7f);

		weight = F * vis / p_spec;
	}
	else
	{
		L = sample_cosine_hemisphere(N, rng_state);

		if (dot(N, L) <= 0.0f)
			return false;

		weight = diffuse_color * (1.0f - F_view) / (1.0f - p_spec);
	}

	return true;
}

static inline float3 trace_ray(float3 ray_origin, float3 ray_dir, inout uint rng_state, uint valid_sphere_count)
{
	float3 color = float3(0.0f, 0.0f, 0.0f);
	float3 throughput = float3(1.0f, 1.0f, 1.0f);

	float3 origin = ray_origin;
	float3 dir = ray_dir;

	for (uint depth = 0; depth < MAX_BOUNCES; ++depth)
	{
		uint closest_sphere_index = valid_sphere_count;
		float closest_t = INF;

		for (uint i = 0; i < valid_sphere_count; ++i)
		{
			sphere_object sphere = shared_spheres[i];
			float t;
			if (ray_sphere_intersection(origin, dir, sphere, t) && t < closest_t)
			{
				closest_sphere_index = i;
				closest_t = t;
			}
		}

		if (closest_sphere_index == valid_sphere_count)
		{
			color += throughput * SKY_COLOR;
			break;
		}

		sphere_object closest_sphere = shared_spheres[closest_sphere_index];

		color += throughput * closest_sphere.emission;

		float3 hit_point = origin + dir * closest_t;
		float3 outward_normal = normalize(hit_point - closest_sphere.center);
		float3 N = dot(dir, outward_normal) < 0.0f ? outward_normal : -outward_normal;
		float3 V = -dir;

		float3 L, weight;
		if (!sample_brdf(closest_sphere, N, V, rng_state, L, weight))
			break;

		throughput *= weight;

		if (depth >= RR_CUTOFF)
		{
			float p_RR = clamp(luminance(throughput), 0.01f, 1.0f);
			if (rand(rng_state) > p_RR)
			{
				break;
			}
			throughput /= p_RR;
		}

		dir = L;
		float eps = 1e-4f * max(1.0f, length(hit_point));
		origin = hit_point + N * eps;
	}

	return color;
}

#if TONEMAP
static inline float3 tonemap(float3 x)
{
	const float a = 2.51f;
	const float b = 0.03f;
	const float c = 2.43f;
	const float d = 0.59f;
	const float e = 0.14f;
	return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}
#endif

[numthreads(16, 16, 1)]
void cs_main(uint3 id : SV_DispatchThreadID, uint group_index : SV_GroupIndex)
{
	uint valid_sphere_count = min(sphere_count, SHARED_SPHERE_COUNT);

	if (group_index < valid_sphere_count)
	{
		shared_spheres[group_index] = spheres[group_index];
	}
	GroupMemoryBarrierWithGroupSync();

	if (id.x >= RENDER_WIDTH || id.y >= RENDER_HEIGHT)
		return;

	if (frame == 1)
	{
		accumulation[id.xy] = float4(0.0f, 0.0f, 0.0f, 0.0f);
	}

	uint rng_state = wang_hash(id.x + id.y * RENDER_WIDTH + frame * RENDER_WIDTH * RENDER_HEIGHT);
	uint sqrt_SPP = (uint)sqrt((float)SAMPLES_PER_PIXEL);
	float r_sqrt_SPP = 1.0f / sqrt_SPP;
	float3 color = float3(0.0f, 0.0f, 0.0f);

	for (uint i = 0; i < SAMPLES_PER_PIXEL; ++i)
	{
		uint x = i % sqrt_SPP;
		uint y = i / sqrt_SPP;

		float jitter_x = rand(rng_state);
		float jitter_y = rand(rng_state);

		float2 subpixel = float2((x + jitter_x) * r_sqrt_SPP, (y + jitter_y) * r_sqrt_SPP);
		subpixel += float2(rand(rng_state), rand(rng_state)) * r_sqrt_SPP;
		subpixel = frac(subpixel);

		float3 ray_dir = get_ray_dir(id.xy, subpixel);
		color += trace_ray(cam_pos, ray_dir, rng_state, valid_sphere_count);
	}

	accumulation[id.xy] += float4(color / SAMPLES_PER_PIXEL, 0.0f);

	float3 hdr = max(0.0f, accumulation[id.xy].xyz / frame);
#if TONEMAP
	hdr = tonemap(hdr);
#endif
	output[id.xy] = float4(pow(hdr, 1.0f / 2.2f), 1.0f);
}
