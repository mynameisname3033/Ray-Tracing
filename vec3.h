#pragma once

struct vec3
{
	float x, y, z;

	vec3() : x(), y(), z() {}
	vec3(float a) : x(a), y(a), z(a) {}
	vec3(float x, float y, float z) : x(x), y(y), z(z) {}

	static inline vec3 cross(const vec3& a, const vec3& b) noexcept { return vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x); }

	inline vec3 operator+(const vec3& other) const noexcept { return vec3(x + other.x, y + other.y, z + other.z); }
	inline vec3 operator-(const vec3& other) const noexcept { return vec3(x - other.x, y - other.y, z - other.z); }
	inline vec3 operator*(float scalar) const noexcept { return vec3(x * scalar, y * scalar, z * scalar); }
	inline vec3 operator/(float scalar) const noexcept { return vec3(x / scalar, y / scalar, z / scalar); }

	inline void operator+=(const vec3& other) noexcept { x += other.x; y += other.y; z += other.z; }
	inline void operator-=(const vec3& other) noexcept { x -= other.x; y -= other.y; z -= other.z; }
	inline void operator*=(float scalar) noexcept { x *= scalar; y *= scalar; z *= scalar; }
	inline void operator/=(float scalar) noexcept { x /= scalar; y /= scalar; z /= scalar; }

	inline float magnitude() const noexcept { return sqrt(x * x + y * y + z * z); }
	inline float magnitude_squared() const noexcept { return x * x + y * y + z * z; }
	inline vec3 normalized() const noexcept { float mag = magnitude(); return vec3(x / mag, y / mag, z / mag); }
};