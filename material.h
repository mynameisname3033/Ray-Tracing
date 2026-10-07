#pragma once

#include "vec3.h"

struct material
{
	vec3 albedo;
	vec3 emission;

	float metallic;
	float roughness;

	material() : albedo(1), emission(), metallic(), roughness() {}
	material(const vec3& albedo, const vec3& emission, float metallic, float roughness) : albedo(albedo), emission(emission), metallic(metallic), roughness(roughness) {}
};