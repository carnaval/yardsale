cnames = [:x, :y, :z, :w]

for d = 2:4
    tn = symbol("Vector$d")
    sn = symbol("vec$d")
    snd = symbol("vec$(d)d")
    cn = cnames[1:d]
    @eval immutable $tn{T <: Number}
            $([:($x :: T) for x in cn]...)
    end
    for binop in (:+, :-)
        @eval $binop(a :: $tn, b :: $tn) = $tn($([:($binop(a.$f, b.$f)) for f in cn]...))
    end
    for scalop in (:*, :/)
        @eval $scalop{T}(a :: $tn{T}, s :: T) = $tn($([:($scalop(a.$f, s)) for f in cn]...))
        @eval $scalop{T}(a :: $tn{T}, s) = $scalop(a, convert(T, s))
    end
    @eval *(s :: Number, a :: $tn) = a*s
    for unop in (:-,)
        @eval $unop(a :: $tn) = $tn($([:($unop(a.$f)) for f in cn]...))
    end
    @eval norm2(a :: $tn) = +($([:(a.$f*a.$f) for f in cn]...))
    @eval norm(a :: $tn) = sqrt(norm2(a))
    @eval normalize(a :: $tn) = a/norm(a)
    @eval dot(a :: $tn, b :: $tn) = +($([:(a.$f*b.$f) for f in cn]...))
    @eval function Base.show(io :: IO, a :: $tn)
        print(io, $sn, "(")
        $([:(print(io, a.$(cn[i]), $(i == length(cn) ? "" : ", "))) for i = 1:length(cn)]...)
        print(io, ")")
    end

    @eval $sn($(cn...)) = $tn(convert(NTuple{$d, Float32},($(cn...),))...)
    @eval $sn() = $sn($([:0f0 for _ in cn]...))
    @eval $sn(v :: $tn) = v
    @eval $snd($(cn...)) = $tn(convert(NTuple{$d, Float64}, ($(cn...),))...)
    @eval $snd() = $sn($([:0.0 for _ in cn]...))
    @eval typealias $(symbol("Vec$d")) $tn{Float32}
    @eval typealias $(symbol("Vec$(d)d")) $tn{Float64}
end

vec4(x,y,z) = vec4(x,y,z,1f0)
vec4(v :: Vector3) = vec4(v.x, v.y, v.z, 1f0)

function cross(u::Vector4,v::Vector4) # this obviously ignores the projective coordinate
    vec4(u.y*v.z - u.z*v.y,
         u.z*v.x - u.x*v.z,
         u.x*v.y - u.y*v.x)
end

function cross(u :: Vector3, v :: Vector3)
    vec3(u.y*v.z - u.z*v.y,
         u.z*v.x - u.x*v.z,
         u.x*v.y - u.y*v.x)
end

immutable Mat4
    m11 :: Float32; m12 :: Float32; m13 :: Float32; m14 :: Float32
    m21 :: Float32; m22 :: Float32; m23 :: Float32; m24 :: Float32
    m31 :: Float32; m32 :: Float32; m33 :: Float32; m34 :: Float32
    m41 :: Float32; m42 :: Float32; m43 :: Float32; m44 :: Float32
end

Mat4(m11 :: Float32, m12 :: Float32, m13 :: Float32,
     m21 :: Float32, m22 :: Float32, m23 :: Float32,
     m31 :: Float32, m32 :: Float32, m33 :: Float32) =
    Mat4(m11, m12, m13, 0f0,
         m21, m22, m23, 0f0,
         m31, m32, m33, 0f0,
         0f0, 0f0, 0f0, 1f0)
		 
    Mat4(m11 :: Float32, m12 :: Float32,
     m21 :: Float32, m22 :: Float32 ) =
	Mat4(	m11, m12, 0f0, 0f0,
			m21, m22, 0f0, 0f0,
			0f0, 0f0, 1f0, 0f0,
			0f0, 0f0, 0f0, 1f0 )
	

const format = "%d %d %d %d\n"
import Base.show
function show(io :: IO, m :: Mat4)
    println(io, "4x4 Float32 matrix:")
    @printf io " %f %f %f %f\n" m.m11 m.m12 m.m13 m.m14
    @printf io " %f %f %f %f\n" m.m21 m.m22 m.m23 m.m24
    @printf io " %f %f %f %f\n" m.m31 m.m32 m.m33 m.m34
    @printf io " %f %f %f %f\n" m.m41 m.m42 m.m43 m.m44
end

*(m1 :: Mat4, m2 :: Mat4) =
Mat4(m1.m11*m2.m11 + m1.m12*m2.m21 + m1.m13*m2.m31 + m1.m14*m2.m41,
     m1.m11*m2.m12 + m1.m12*m2.m22 + m1.m13*m2.m32 + m1.m14*m2.m42,
     m1.m11*m2.m13 + m1.m12*m2.m23 + m1.m13*m2.m33 + m1.m14*m2.m43,
     m1.m11*m2.m14 + m1.m12*m2.m24 + m1.m13*m2.m34 + m1.m14*m2.m44,

     m1.m21*m2.m11 + m1.m22*m2.m21 + m1.m23*m2.m31 + m1.m24*m2.m41,
     m1.m21*m2.m12 + m1.m22*m2.m22 + m1.m23*m2.m32 + m1.m24*m2.m42,
     m1.m21*m2.m13 + m1.m22*m2.m23 + m1.m23*m2.m33 + m1.m24*m2.m43,
     m1.m21*m2.m14 + m1.m22*m2.m24 + m1.m23*m2.m34 + m1.m24*m2.m44,
     
     m1.m31*m2.m11 + m1.m32*m2.m21 + m1.m33*m2.m31 + m1.m34*m2.m41,
     m1.m31*m2.m12 + m1.m32*m2.m22 + m1.m33*m2.m32 + m1.m34*m2.m42,
     m1.m31*m2.m13 + m1.m32*m2.m23 + m1.m33*m2.m33 + m1.m34*m2.m43,
     m1.m31*m2.m14 + m1.m32*m2.m24 + m1.m33*m2.m34 + m1.m34*m2.m44,

     m1.m41*m2.m11 + m1.m42*m2.m21 + m1.m43*m2.m31 + m1.m44*m2.m41,
     m1.m41*m2.m12 + m1.m42*m2.m22 + m1.m43*m2.m32 + m1.m44*m2.m42,
     m1.m41*m2.m13 + m1.m42*m2.m23 + m1.m43*m2.m33 + m1.m44*m2.m43,
     m1.m41*m2.m14 + m1.m42*m2.m24 + m1.m43*m2.m34 + m1.m44*m2.m44)
+(m1 :: Mat4, m2 :: Mat4) =
    Mat4(m1.m11 + m2.m11, m1.m12 + m2.m12, m1.m13 + m2.m13, m1.m14 + m2.m14,
         m1.m21 + m2.m21, m1.m22 + m2.m22, m1.m23 + m2.m23, m1.m24 + m2.m24,
         m1.m31 + m2.m31, m1.m32 + m2.m32, m1.m33 + m2.m33, m1.m34 + m2.m34,
         m1.m41 + m2.m41, m1.m42 + m2.m42, m1.m43 + m2.m43, m1.m44 + m2.m44)
*(m :: Mat4, v :: Vec4) =
    Vec4(v.x*m.m11 + v.y*m.m12 + v.z*m.m13 + v.w*m.m14,
         v.x*m.m21 + v.y*m.m22 + v.z*m.m23 + v.w*m.m24,
         v.x*m.m31 + v.y*m.m32 + v.z*m.m33 + v.w*m.m34,
         v.x*m.m41 + v.y*m.m42 + v.z*m.m43 + v.w*m.m44)


import Base.getindex

# this does a bound check except when inlined with constant arguments
function getindex(m :: Mat4, i0::Int, j0::Int)
    getfield(m, j0 + 4*(i0 - 1))
end

function inv(a :: Mat4)
    s0 = a[1, 1] * a[2, 2] - a[2, 1] * a[1, 2]
    s1 = a[1, 1] * a[2, 3] - a[2, 1] * a[1, 3]
    s2 = a[1, 1] * a[2, 4] - a[2, 1] * a[1, 4]
    s3 = a[1, 2] * a[2, 3] - a[2, 2] * a[1, 3]
    s4 = a[1, 2] * a[2, 4] - a[2, 2] * a[1, 4]
    s5 = a[1, 3] * a[2, 4] - a[2, 3] * a[1, 4]

    c5 = a[3, 3] * a[4, 4] - a[4, 3] * a[3, 4]
    c4 = a[3, 2] * a[4, 4] - a[4, 2] * a[3, 4]
    c3 = a[3, 2] * a[4, 3] - a[4, 2] * a[3, 3]
    c2 = a[3, 1] * a[4, 4] - a[4, 1] * a[3, 4]
    c1 = a[3, 1] * a[4, 3] - a[4, 1] * a[3, 3]
    c0 = a[3, 1] * a[4, 2] - a[4, 1] * a[3, 2]
    
    det = s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0
    if det == 0 error("Trying to invert non invertible matrix : $m") end
    invdet = 1f0 / det

    Mat4(
         ( a[2, 2] * c5 - a[2, 3] * c4 + a[2, 4] * c3) * invdet,
         (-a[1, 2] * c5 + a[1, 3] * c4 - a[1, 4] * c3) * invdet,
         ( a[4, 2] * s5 - a[4, 3] * s4 + a[4, 4] * s3) * invdet,
         (-a[3, 2] * s5 + a[3, 3] * s4 - a[3, 4] * s3) * invdet,
         
         (-a[2, 1] * c5 + a[2, 3] * c2 - a[2, 4] * c1) * invdet,
         ( a[1, 1] * c5 - a[1, 3] * c2 + a[1, 4] * c1) * invdet,
         (-a[4, 1] * s5 + a[4, 3] * s2 - a[4, 4] * s1) * invdet,
         ( a[3, 1] * s5 - a[3, 3] * s2 + a[3, 4] * s1) * invdet,
         
         ( a[2, 1] * c4 - a[2, 2] * c2 + a[2, 4] * c0) * invdet,
         (-a[1, 1] * c4 + a[1, 2] * c2 - a[1, 4] * c0) * invdet,
         ( a[4, 1] * s4 - a[4, 2] * s2 + a[4, 4] * s0) * invdet,
         (-a[3, 1] * s4 + a[3, 2] * s2 - a[3, 4] * s0) * invdet,
         
         (-a[2, 1] * c3 + a[2, 2] * c1 - a[2, 3] * c0) * invdet,
         ( a[1, 1] * c3 - a[1, 2] * c1 + a[1, 3] * c0) * invdet,
         (-a[4, 1] * s3 + a[4, 2] * s1 - a[4, 3] * s0) * invdet,
         ( a[3, 1] * s3 - a[3, 2] * s1 + a[3, 3] * s0) * invdet)
end
     
array_to_mat(a) = Mat4(a[1,1], a[1,2], a[1,3], a[1,4], a[2,1], a[2,2], a[2,3], a[2,4], a[3,1], a[3, 2], a[3,3], a[3,4], a[4,1], a[4,2], a[4,3], a[4,4])
array34_to_mat(a) = Mat4(a[1,1], a[1,2], a[1,3], a[1,4], a[2,1], a[2,2], a[2,3], a[2,4], a[3,1], a[3,2], a[3,3], a[3,4], 0f0, 0f0, 0f0, 1f0)
mat_to_array(m) = [m.m11 m.m12 m.m13 m.m14; m.m21 m.m22 m.m23 m.m24; m.m31 m.m32 m.m33 m.m34; m.m41 m.m42 m.m43 m.m44]
const lin_id = Mat4(1f0, 0f0, 0f0, 0f0,
                   0f0, 1f0, 0f0, 0f0,
                   0f0, 0f0, 1f0, 0f0,
                   0f0, 0f0, 0f0, 1f0)

translation(v :: Vec3) =
    Mat4(1f0, 0f0, 0f0, v.x,
         0f0, 1f0, 0f0, v.y,
         0f0, 0f0, 1f0, v.z,
         0f0, 0f0, 0f0, 1f0)
scale(v :: Vec3) =
    Mat4(v.x, 0f0, 0f0, 0f0,
         0f0, v.y, 0f0, 0f0,
         0f0, 0f0, v.z, 0f0,
         0f0, 0f0, 0f0, 1f0)
translation(fs...) = translation(vec3(fs...))
scale(f :: Float32) = scale(f,f,f)
scale(fs...) = scale(vec3(fs...))

		 
normalize(u::Vector{Float32}) = u/sqrt(u[1]*u[1] + u[2]*u[2] + u[3]*u[3])

immutable Quat
    x :: Float32
    y :: Float32
    z :: Float32
    w :: Float32
end

#TODO ultimately remove these 2 ctors
function Quat(x :: Vector{Float32})
    @assert size(x) == (4,) "Wrong size for a quat"
    Quat(x[1], x[2], x[3], x[4])
end
function Vec4(x :: Vector{Float32})
    @assert (size(x) == (4,) || size(x) == (3,)) "Wrong size for a vec4"
    Vec4(x...)
end

Quat() = Quat(0f0, 0f0, 0f0, 1f0)

function quat_to_mat(q :: Quat)
    x,y,z,w = q.x,q.y,q.z,q.w
    Mat4(1-2(y*y + z*z), 2(x*y - w*z),   2(x*z + w*y),   0f0,
         2(x*y + w*z),   1-2(x*x + z*z), 2(y*z - w*x),   0f0,
         2(x*z - w*y),   2(y*z + w*x),   1-2(x*x + y*y), 0f0,
         0f0,            0f0,            0f0,            1f0)
end

function Quat(v :: Vec3, a :: Float32)
    s = sin(a/2)
    v = normalize(v)
    Quat(v.x*s, v.y*s, v.z*s, cos(a/2))
end

function *(q1 :: Quat, q2 :: Quat)
    Quat(q1.w*q2.x + q1.x*q2.w + q1.y*q2.z - q1.z*q2.y,
         q1.w*q2.y + q1.y*q2.w + q1.z*q2.x - q1.x*q2.z,
         q1.w*q2.z + q1.z*q2.w + q1.x*q2.y - q1.y*q2.x,
         q1.w*q2.w - q1.x*q2.x - q1.y*q2.y - q1.z*q2.z)
end

function *(q :: Quat, v :: Vec3)
    x,y,z,w = q.x,q.y,q.z,q.w
    Vec3((1-2(y*y + z*z))*v.x + 2(x*y - w*z)*v.y + 2(x*z + w*y)*v.z,
         2(x*y + w*z)*v.x + (1-2(x*x + z*z))*v.y + 2(y*z - w*x)*v.z,
         2(x*z - w*y)*v.x + 2(y*z + w*x)*v.y + (1-2(x*x + y*y))*v.z)
end

norm2(q :: Quat) = q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w

function inv(q :: Quat)
    sqn = norm2(q)
    Quat(-q.x/sqn, -q.y/sqn, -q.z/sqn, q.w/sqn)
end

# Represents the affine transform u -> t + q*u (= tr*q)
# i should probably add scaling in there :p
immutable type Aff
    q :: Quat
    t :: Vec3
end

const Aff_id = Aff(Quat(), vec3())

Aff(t :: Vec3) = Aff(Quat(), t)
Aff(q :: Quat) = Aff(q, vec3())

function aff_to_mat(a :: Aff)
    translation(a.t)*quat_to_mat(a.q)
end

*(a1 :: Aff, a2 :: Aff) = Aff(a1.q*a2.q, a1.t + a1.q*a2.t)

function inv(a :: Aff)
    iq = inv(a.q)
    Aff(iq, iq*(-a.t))
end

*(a :: Aff, v :: Vec3) = a.t + a.q*v
