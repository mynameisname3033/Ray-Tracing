#pragma once

struct alignas(16) cb_GPU
{
	float cam_pos[3];
	float fov_scale;

	float cam_forward[3];
	int sphere_count;

	float cam_right[3];
	int frame;

	float cam_up[3];
	float pad;
};

struct sphere_object_GPU
{
	float center[3];
	float radius;

	float albedo[3];
	float emission[3];

	float metallic;
	float roughness;
};
