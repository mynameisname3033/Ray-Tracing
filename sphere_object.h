#pragma once

#include "material.h"
#include "vec3.h"

struct sphere_object
{
	vec3 center;
	float radius;

	material mat;

	sphere_object() : center(), radius(1), mat() {}
	sphere_object(const vec3& center, float radius, const material& mat) : center(center), radius(radius), mat(mat) {}
};