#pragma once

#include "vec3.h"

struct transform
{
	vec3 position;
	float yaw, pitch, roll;

	transform() : position(), yaw(), pitch(), roll() {}
	transform(const vec3& position, float yaw, float pitch, float roll) : position(position), yaw(yaw), pitch(pitch), roll(roll) {}

	inline vec3 get_forward() const noexcept
	{
		return vec3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)).normalized();
	}

	inline vec3 get_right(const vec3& forward) const noexcept
	{
		return vec3::cross(forward, vec3(0.0f, 1.0f, 0.0f)).normalized();
	}

	inline vec3 get_up(const vec3& forward, const vec3& right) const noexcept
	{
		return vec3::cross(right, forward);
	}
};