immutable type Texture
    handle :: Int32
    w :: Int
    h :: Int
    format :: Symbol
    target :: Uint16
    layer_count :: Int  # 0 if we are not a texture array
    layer :: Int
    mipmap_count :: Int
end

const NoTexture = Texture(-1, 0, 0, :none, 0, 0, 0, 0)

# TODO this whole thing is wrong in many ways and deserves a cleanup
# this also only works for 2D textures
# to be more in line with how gl works

@table lookup_tex_gltype [:DXT1 => GL_COMPRESSED_RGBA_S3TC_DXT1_EXT,
	                  :DXT3 => GL_COMPRESSED_RGBA_S3TC_DXT3_EXT,
	                  :DXT5 => GL_COMPRESSED_RGBA_S3TC_DXT5_EXT,
                          :RGBA => GL_RGBA,
                          :DEPTH32 => GL_DEPTH_COMPONENT32,
                          :DEPTH16 => GL_DEPTH_COMPONENT16,
                          :FLOAT => GL_FLOAT]
@table is_compressed    [:DXT1 => true, :DXT3 => true, :DXT5 => true,
                         :RGBA => false, :DEPTH32 => false, :DEPTH16 => false, :FLOAT => false]

tex_gltype(i::Image) = lookup_tex_gltype(i.format)
is_array(t::Texture) = t.layer_count > 0
function alloc_storage(tex :: Texture)
    if tex.target == GL_TEXTURE_2D_ARRAY
        glTextureStorage3DEXT(tex.handle, tex.target, uint32(tex.mipmap_count), lookup_tex_gltype(tex.format), tex.w, tex.h, tex.layer_count)
    else
        glTextureStorage2DEXT(tex.handle, tex.target, uint32(tex.mipmap_count), lookup_tex_gltype(tex.format), tex.w, tex.h)
    end
end

# should be moved somewhere
v = float32([-1])
glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY, v)
const MAX_ANISO = v[1]

@table gl_filters [:min => GL_TEXTURE_MIN_FILTER,
                   :mag => GL_TEXTURE_MAG_FILTER,
                   :aniso => GL_TEXTURE_MAX_ANISOTROPY]
@table gl_filter_funcs [(:linear, nothing) => GL_LINEAR,
                        (:nearest, nothing) => GL_NEAREST,
                        (:linear, :linear) => GL_LINEAR_MIPMAP_LINEAR,
                        (:linear, :nearest) => GL_LINEAR_MIPMAP_NEAREST,
                        (:nearest, :linear) => GL_NEAREST_MIPMAP_LINEAR,
                        (:nearest, :nearest) => GL_NEAREST_MIPMAP_NEAREST,
                        (:max, nothing) => MAX_ANISO]

function filtering!(tex :: Texture, filter, func, mipmap_func = nothing)
    glTextureParameteriEXT(tex.handle, tex.target, gl_filters(filter), gl_filter_funcs((func, mipmap_func)))
end

function gl_new_tex()
    tex = Uint32[-1]
    glGenTextures(1, tex)
    tex[1]
end

function default_filtering(t :: Texture)
    filtering!(t, :min, :linear, :linear)
    filtering!(t, :mag, :linear)
    filtering!(t, :aniso, :max)
end

function gen_mipmaps(t :: Texture)
    bind_tex(t, int32(0))
    glGenerateMipmap(t.target)
end

type TextureCache
    level :: Int
    arrays :: Dict{(Int, Int, Symbol), Texture}
    layer_used :: Dict{(Int, Int, Symbol), Int}
    next :: Union(TextureCache, Nothing)
end

TextureCache(level = 0) = TextureCache(level, ((Int,Int,Symbol)=>Texture)[], ((Int,Int,Symbol)=>Int)[], nothing)

Base.print(io::IO, t::TextureCache) = print(io, "TexCache(", t.level, ", ", t.layer_used, ") -> ", t.next)

function alloc(cache :: TextureCache, w :: Int, h :: Int, fmt :: Symbol)
    dim = (w, h, fmt)
    if !haskey(cache.arrays, dim)
        array = Texture(gl_new_tex(), w, h, fmt, GL_TEXTURE_2D_ARRAY, MAX_CACHE_LAYER_COUNT, 0, 1)
        alloc_storage(array)
        default_filtering(array)
        cache.arrays[dim] = array
        cache.layer_used[dim] = 0
        layer = 0
    else
        array = cache.arrays[dim]
        layer = cache.layer_used[dim]
    end
    if layer >= MAX_CACHE_LAYER_COUNT
        if cache.next == nothing
            cache.next = TextureCache(cache.level+1)
        end
        return alloc(cache.next, w, h, fmt)
    end
    t = Texture(array.handle, w, h, fmt, GL_TEXTURE_2D_ARRAY, array.layer_count, layer, 1)
    cache.layer_used[dim] = layer + 1
    t
end

function alloc(cache :: TextureCache, img :: Image)
    t = alloc(cache, img.w, img.h, img.format)
    t[1, :, :] = img.data[1]
    t
end

# TODO implement better memory management + sparse texture arrays
const MAX_CACHE_LAYER_COUNT = 32

function make_dds_tex(io::IOStream)
    img = read_dds(io)
    make_tex(img)
end
Base.size(t :: Texture) = (t.mipmap_count, t.w, t.h)
Base.size(t :: Texture, i :: Int) = size(t)[i]
Base.ndims(t :: Texture) = 3
function Base.setindex!(t :: Texture, data :: Vector, mipmap :: Int, xrange :: Range1, yrange :: Range1)
    bytedata = reinterpret(Uint8, data)
    xlen = xrange.stop - xrange.start + 1
    ylen = yrange.stop - yrange.start + 1
    if is_compressed(t.format)
        if t.target == GL_TEXTURE_2D
            glCompressedTextureSubImage2DEXT(t.handle, t.target, mipmap - 1, xrange.start - 1, yrange.start - 1, xlen, ylen, lookup_tex_gltype(t.format), length(bytedata), bytedata)
        elseif t.target == GL_TEXTURE_2D_ARRAY
            glCompressedTextureSubImage3DEXT(t.handle, t.target, mipmap - 1, xrange.start - 1, yrange.start - 1, t.layer, xlen, ylen, 1, lookup_tex_gltype(t.format), length(bytedata), bytedata)
        else
            error("??")
        end
    else
        error("not done")
    end
end
global_tex_cache = TextureCache()
function make_tex(img :: Image, cache :: TextureCache = global_tex_cache)
#    t = Texture(gl_new_tex(), uint32(img.w), uint32(img.h), img.format, GL_TEXTURE_2D, 0, 0, 1)
#    default_filtering(t)
#    alloc_storage(t)
#    t[1, :, :] = img.data[1]
#    gen_mipmaps(t)
    alloc(cache, img)
end

const CUBE_FACES = (GL_TEXTURE_CUBE_MAP_POSITIVE_X,
                    GL_TEXTURE_CUBE_MAP_NEGATIVE_X,
                    GL_TEXTURE_CUBE_MAP_POSITIVE_Y,
                    GL_TEXTURE_CUBE_MAP_NEGATIVE_Y,
                    GL_TEXTURE_CUBE_MAP_POSITIVE_Z,
                    GL_TEXTURE_CUBE_MAP_NEGATIVE_Z)

function make_dds_cube(ios :: Vector{IOStream})
    imgs = map(read_dds, ios)
    tex = Uint32[-1]
    glGenTextures(1, tex)
    tex = tex[1]
    t = Texture(tex, uint32(imgs[1].w), uint32(imgs[1].h), imgs[1].format, GL_TEXTURE_CUBE_MAP, 0, 0, 0)
    bind_tex(t, int32(0))
    filtering!(t, :min, :linear, :linear)
    filtering!(t, :mag, :linear)
    filtering!(t, :aniso, :max)
    for (img, face) in zip(imgs, CUBE_FACES)
        glCompressedTextureImage2DEXT(tex, face, 0, tex_gltype(img), img.w, img.h, 0, length(img.data[1]), img.data[1])
    end
    glGenerateMipmap(GL_TEXTURE_CUBE_MAP)
    t
end

function alloc_tex2d(width, height, format :: Symbol)
    tex = Uint32[-1]
    glGenTextures(1, tex)
    tex = tex[1]
    internal_format = lookup_tex_gltype(format) # should not be this
    ext_format = lookup_tex_gltype(format)
    if format == :DEPTH32 # todo horrible hack
        ext_format = GL_DEPTH_COMPONENT
        ty = GL_FLOAT
    elseif format == :FLOAT
        ty = GL_FLOAT
        ext_format = GL_RGBA
        internal_format = GL_RGBA32F
    else
        ty = GL_UNSIGNED_BYTE
    end
    t = Texture(tex, uint32(width), uint32(height), format, GL_TEXTURE_2D, 0, 0, 0)
    glTextureImage2DEXT(tex, GL_TEXTURE_2D, 0, internal_format, width, height, 0, ext_format, ty, 0)
    filtering!(t, :min, :linear, :linear)
    filtering!(t, :mag, :linear)
    filtering!(t, :aniso, :max)
    bind_tex(t, int32(0))
    glGenerateMipmap(GL_TEXTURE_2D)
    t
end

function bind_tex(tex :: Texture, unit :: Int32)
    glActiveTexture(GL_TEXTURE0 + unit)
    glBindTexture(tex.target, tex.handle)
end
