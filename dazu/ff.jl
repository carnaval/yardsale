global in_err = false
function ERR()
    global in_err
    in_err && return
    in_err = true
    err = glGetError()
    in_err = false
    if err != 0
        error("GL error $err")
    end
end
const LTRACE = false
macro c(cc, fn, f, rt, at)
    args = [symbol("x" * string(i)) for i=1:length(at.args)]
    quote
        function $(esc(fn))($(args...))
            r = if $(cc == false)
                ccall( $(esc(f)), cdecl, $rt, $at, $(args...) )
            else
                ccall( $(esc(f)), stdcall, $rt, $at, $(args...) )
            end
            ERR() #TODO better way to enable debug
            $(LTRACE ? :(println(string($f[1]), "(...)")) : ())
            r
        end
    end
end

macro clib(sym, name, cc)
    quote
        macro $(sym)(f, rt, at)
            name = $name
            fs = :()
            fs.head = :quote
            fs.args = [ f ]
            cc = $cc
            :(@c $cc $f ($fs , $name) $rt $at)
        end
    end
end

macro table(f_name, stx)
    if stx.head != :dict error("@table must take a dict literal as second argument") end
    #dump(stx.args)
    function lt(x, ls)
        if isempty(ls)
            :(error("unknown case : $x"))
        else
            quote
                if ($x == $(ls[1].args[1]))
                    $(ls[1].args[2])
                else
                    $(lt(x,ls[2:end]))
                end
            end
        end
    end
    quote
        function $(esc(f_name))(x)
            $(lt(:x, stx.args))
        end
    end
end

const SDL_INIT_VIDEO = 0x00000020

const SDL_WINDOW_OPENGL = 0x00000002
const SDL_WINDOWPOS_CENTERED = 0x2FFF0000

const SDL_RENDERER_PRESENTVSYNC = 0x00000004

const SDL_GL_CONTEXT_PROFILE_MASK = 0x15
const SDL_GL_CONTEXT_PROFILE_CORE = 0x1
const SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 0x2

const SDL_SC_ESC = 41

@unix_only @clib sdl "libSDL2" false
@windows_only @clib sdl "SDL2" false

@sdl SDL_Init Int32 (Uint32,)
@sdl SDL_CreateWindow Ptr{Void} (Ptr{Uint8}, Int32, Int32, Int32, Int32, Uint32)
@sdl SDL_CreateRenderer Ptr{Void} (Ptr{Void}, Int32, Int32)
@sdl SDL_RenderPresent Void (Ptr{Void},)
@sdl SDL_Delay Void (Uint32,)
@sdl SDL_GL_GetProcAddress Ptr{Void} (Ptr{Uint8},)
@sdl SDL_GL_CreateContext Ptr{Void} (Ptr{Void},)
@sdl SDL_GL_MakeCurrent Int32 (Ptr{Void}, Ptr{Void})
@sdl SDL_GL_SwapWindow Void (Ptr{Void},)
@sdl SDL_GetKeyboardState Ptr{Uint8} (Ptr{Int32},)
@sdl SDL_PumpEvents Void ()
@sdl SDL_PollEvent Int32 (Ptr{Void},)
@sdl SDL_StartTextInput Void ()
@sdl SDL_SetWindowGrab Void (Ptr{Void}, Uint8)
@sdl SDL_ShowCursor Int32 (Uint8,)
@sdl SDL_SetRelativeMouseMode Int32 (Uint8,)
@sdl SDL_WarpMouseInWindow Void (Ptr{Void}, Int32, Int32)
@sdl SDL_GL_SetAttribute Void (Int32, Int32)
@sdl SDL_GL_SetSwapInterval Void (Int32,)

const GL_RENDERER = 0x1F01
const GL_VERSION = 0x1F02
const GL_EXTENSIONS = 0x1F03
const GL_TEXTURE_MAG_FILTER = 0x2800
const GL_TEXTURE_MIN_FILTER = 0x2801
const GL_MAX_TEXTURE_MAX_ANISOTROPY = 0x84FF
const GL_TEXTURE_MAX_ANISOTROPY = 0x84FE
const GL_TEXTURE_WRAP_S = 0x2802
const GL_TEXTURE_WRAP_T = 0x2803
const GL_GENERATE_MIPMAP = 0x8191

const GL_INFO_LOG_LENGTH = 0x8B84

const GL_NEAREST = 0x2600
const GL_LINEAR = 0x2601
const GL_LINEAR_MIPMAP_LINEAR = 0x2703

const GL_TEXTURE_2D = 0x0DE1
const GL_TEXTURE_2D_ARRAY = 0x8C1A
const GL_RGB =  0x1907
const GL_RGBA = 0x1908
const GL_RGBA32F = 0x8814

const GL_COMPRESSED_RGB_S3TC_DXT1_EXT = 0x83F0
const GL_COMPRESSED_RGBA_S3TC_DXT1_EXT = 0x83F1
const GL_COMPRESSED_RGBA_S3TC_DXT3_EXT = 0x83F2
const GL_COMPRESSED_RGBA_S3TC_DXT5_EXT = 0x83F3

const GL_TEXTURE_CUBE_MAP            =  0x8513
const GL_TEXTURE_CUBE_MAP_POSITIVE_X =  0x8515
const GL_TEXTURE_CUBE_MAP_NEGATIVE_X =  0x8516
const GL_TEXTURE_CUBE_MAP_POSITIVE_Y =  0x8517
const GL_TEXTURE_CUBE_MAP_NEGATIVE_Y =  0x8518
const GL_TEXTURE_CUBE_MAP_POSITIVE_Z =  0x8519
const GL_TEXTURE_CUBE_MAP_NEGATIVE_Z =  0x851A
const GL_TEXTURE_CUBE_MAP_SEAMLESS   =  0x884F

const GL_VERTEX_SHADER = 0x8B31
const GL_FRAGMENT_SHADER = 0x8B30

const GL_LINES = 0x0001
const GL_TRIANGLES = 0x0004

const GL_COLOR_BUFFER_BIT = 0x00004000

const GL_UNSIGNED_INT = 0x1405
const GL_UNSIGNED_INT_VEC2 = 0x8DC6
const GL_UNSIGNED_INT_VEC3 = 0x8DC7
const GL_UNSIGNED_INT_VEC4 = 0x8DC8
const GL_UNSIGNED_BYTE = 0x1401
const GL_UNSIGNED_SHORT = 0x1403
const GL_FLOAT = 0x1406
const GL_FLOAT_VEC2 = 0x8B50
const GL_FLOAT_VEC3 = 0x8B51
const GL_FLOAT_VEC4 = 0x8B52
const GL_INT_VEC2 = 0x8B53
const GL_INT_VEC3 = 0x8B54
const GL_INT_VEC4 = 0x8B55
const GL_BOOL = 0x8B56
const GL_BOOL_VEC2 = 0x8B57
const GL_BOOL_VEC3 = 0x8B58
const GL_BOOL_VEC4 = 0x8B59
const GL_FLOAT_MAT2 = 0x8B5A
const GL_FLOAT_MAT3 = 0x8B5B
const GL_FLOAT_MAT4 = 0x8B5C
const GL_SAMPLER_1D = 0x8B5D
const GL_SAMPLER_2D = 0x8B5E
const GL_SAMPLER_3D = 0x8B5F
const GL_SAMPLER_CUBE = 0x8B60
const GL_SAMPLER_1D_SHADOW = 0x8B61
const GL_SAMPLER_2D_SHADOW = 0x8B6
const GL_SAMPLER_2D_ARRAY = 0x8DC1
const GL_TEXTURE0 = 0x84C0

const GL_LESS = 0x0201
const GL_DEPTH_TEST = 0x0B71
const GL_DEPTH_BUFFER_BIT = 0x00000100
const GL_BLEND = 0x0BE2
const GL_SRC_ALPHA = 0x0302
const GL_ONE_MINUS_SRC_ALPHA = 0x0303

const GL_READ_ONLY = 0x88B8
const GL_WRITE_ONLY = 0x88B9
const GL_READ_WRITE = 0x88BA

const GL_FRONT = 0x0404
const GL_BACK = 0x0405
const GL_FRONT_AND_BACK = 0x0408
const GL_POINT = 0x1B00
const GL_LINE = 0x1B01
const GL_FILL = 0x1B02

const GL_NICEST = 0x1102
const GL_FASTEST = 0x1101
const GL_GENERATE_MIPMAP_HINT = 0x8192

@windows_only @clib gl "opengl32" true
@unix_only @clib gl "libGL" false

@gl glClearColor Void (Float32, Float32, Float32, Float32)
@gl glClear Void (Uint32,)
@gl glDrawElements Void (Uint32, Int32, Uint32, Ptr{Void})
@gl glViewport Void (Int32, Int32, Int32, Int32)
@gl glGenTextures Void (Int32, Ptr{Uint32})
@gl glBindTexture Void (Uint32, Uint32)
@gl glGetError Uint32 ()
@gl glGetString Ptr{Uint8} (Uint32,)
@gl glEnable Void (Uint32,)
@gl glDisable Void (Uint32,)
@gl glDepthFunc Void (Uint32,)
@gl glBlendFunc Void (Uint32, Uint32)
@gl glPolygonMode Void (Uint32, Uint32)
@gl glHint Void (Uint32, Uint32)
@gl glReadPixels Void (Int32, Int32, Int32, Int32, Uint32, Uint32, Ptr{Void})
@gl glGetFloatv Void (Uint32, Ptr{Float32})

@unix_only macro glext(f, rt, at)
    :(@gl $f $rt $at)
end
@windows_only macro glext(f, rt, at)
    fn = string(f)
    quote
        proc = false
        @c stdcall $f (if proc == false proc = SDL_GL_GetProcAddress($(fn)) end; proc) $rt $at
    end
end


 const GL_COMPILE_STATUS = 0x8B81
const GL_LINK_STATUS = 0x8B82
const GL_ACTIVE_ATTRIBUTES = 0x8B89
const GL_ACTIVE_UNIFORMS = 0x8B86
const GL_ARRAY_BUFFER = 0x8892
const GL_ELEMENT_ARRAY_BUFFER = 0x8893
const GL_UNIFORM_BUFFER = 0x8A11
const GL_STATIC_DRAW = 0x88E4
#@gl wglGetProcAddress Void (Ptr{Uint8},)
@glext glCreateShader Uint32 (Uint32,)
@glext glShaderSource Void (Uint32, Int32, Ptr{Ptr{Uint8}}, Ptr{Int32})
@glext glCompileShader Void (Uint32,)
@glext glGetShaderiv Void (Uint32, Uint32, Ptr{Int32})
@glext glCreateProgram Uint32 ()
@glext glAttachShader Void (Uint32, Uint32)
@glext glLinkProgram Void (Uint32,)
@glext glGetProgramiv Void (Uint32, Uint32, Ptr{Int32})
@glext glGetAttribLocation Int32 (Uint32, Ptr{Uint8})
@glext glUseProgram Void (Uint32,)
@glext glGetShaderInfoLog Void (Uint32, Int32, Ptr{Int32}, Ptr{Uint8})
@glext glGetProgramInfoLog Void (Uint32, Int32, Ptr{Int32}, Ptr{Uint8})
@glext glGenerateMipmap Void (Uint32,)
@glext glActiveTexture Void (Uint32,)

@glext glDrawElementsBaseVertex Void (Uint32, Int32, Uint32, Ptr{Void}, Int32)
@glext glMultiDrawElementsBaseVertex Void (Uint32, Ptr{Int32}, Uint32, Ptr{Void}, Int32, Ptr{Int32})
@glext glDrawElementsInstancedBaseVertexBaseInstance Void (Uint32, Int32, Uint32, Ptr{Void}, Int32, Int32, Uint32)
@glext glMultiDrawElementsIndirect Void (Uint32, Uint32, Ptr{Void}, Int32, Int32)

@glext glGetActiveAttrib Void (Uint32, Uint32, Int32, Ptr{Int32}, Ptr{Int32}, Ptr{Uint32}, Ptr{Uint8})
@glext glGetActiveUniform Void (Uint32, Uint32, Int32, Ptr{Int32}, Ptr{Int32}, Ptr{Uint32}, Ptr{Uint8})

@glext glUniformMatrix4fv Void (Int32, Int32, Uint8, Ptr{Float32})
@glext glGetUniformLocation Int32 (Uint32, Ptr{Uint8})
@glext glGetUniformBlockIndex Int32 (Uint32, Ptr{Uint8})
@glext glUniform1i Void (Int32, Int32)
@glext glUniform1f Void (Int32, Float32)
@glext glUniform2f Void (Int32, Float32, Float32)
@glext glUniform3f Void (Int32, Float32, Float32, Float32)
@glext glUniform4f Void (Int32, Float32, Float32, Float32, Float32)
@glext glUniform1fv Void (Int32, Int32, Ptr{Float32})
@glext glUniform4fv Void (Int32, Int32, Ptr{Float32})

@glext glEnableVertexAttribArray Void (Uint32,)
@glext glDisableVertexAttribArray Void (Uint32,)
@glext glVertexAttribPointer Void (Uint32, Int32, Uint32, Uint8, Int32, Ptr{Void})
@glext glVertexAttribIPointer Void (Uint32, Int32, Uint32, Int32, Ptr{Void})
@glext glGenBuffers Void (Int32, Ptr{Uint32})
@glext glNamedBufferDataEXT Void (Int32, Int32, Ptr{Void}, Uint32)
@glext glMapNamedBufferEXT Ptr{Void} (Uint32, Uint32)
@glext glUnmapNamedBufferEXT Void (Uint32,)
@glext glNamedBufferSubDataEXT Void (Uint32, Int32, Int32, Ptr{Void})
@glext glBindBuffer Void (Uint32, Uint32)
@glext glBindBufferRange Void (Uint32, Uint32, Uint32, Int32, Int32)
@glext glDrawArraysEXT Void (Uint32, Int32, Int32)

@glext glGenVertexArrays Void (Int32, Ptr{Uint32})
@glext glBindVertexArray Void (Uint32,)

@glext glTextureStorage2DEXT Void (Uint32, Uint32, Int32, Uint32, Int32, Int32)
@glext glTextureStorage3DEXT Void (Uint32, Uint32, Int32, Uint32, Int32, Int32, Int32)
@glext glCompressedTextureImage2DEXT Void (Uint32, Uint32, Int32, Uint32, Int32, Int32, Int32, Int32, Ptr{Void})
@glext glCompressedTextureSubImage2DEXT Void (Uint32, Uint32, Int32, Int32, Int32, Int32, Int32, Uint32, Int32, Ptr{Void})
@glext glCompressedTextureSubImage3DEXT Void (Uint32, Uint32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Uint32, Int32, Ptr{Void})
@glext glTextureImage2DEXT Void (Uint32, Uint32, Int32, Uint32, Int32, Int32, Int32, Uint32, Uint32, Ptr{Void})
@glext glTextureParameteriEXT Void (Uint32, Uint32, Uint32, Int32)
@glext glTextureParameterfEXT Void (Uint32, Uint32, Uint32, Float32)


const GL_FRAMEBUFFER = 0x8D40
const GL_COLOR_ATTACHMENT0 = 0x8CE0
const GL_DEPTH24_STENCIL8 = 0x88F0
const GL_DEPTH_COMPONENT16 = 0x81A5
const GL_DEPTH_COMPONENT24 = 0x81A6
const GL_DEPTH_COMPONENT32 = 0x81A7
const GL_DEPTH_COMPONENT32F = 0x8CAC
const GL_DEPTH_COMPONENT = 0x1902 # not sure about you


const GL_DEPTH_ATTACHMENT = 0x8D00
const GL_STENCIL_ATTACHMENT = 0x8D20
const GL_DEPTH_STENCIL_ATTACHMENT = 0x821A
const GL_RENDERBUFFER = 0x8D41

@glext glGenFramebuffers Void (Int32, Ptr{Uint32})
@glext glGenRenderbuffers Void (Int32, Ptr{Uint32})
@glext glBindRenderbuffer Void (Uint32, Uint32)

@glext glBindFramebuffer Void (Uint32, Uint32)
@glext glNamedFramebufferTexture2DEXT Void (Uint32, Uint32, Uint32, Uint32, Int32)
@glext glNamedRenderbufferStorageEXT Void (Uint32, Uint32, Int32, Int32)
@glext glNamedFramebufferRenderbufferEXT Void (Uint32, Uint32, Uint32, Uint32)

@glext glDrawBuffers Void (Int32, Ptr{Uint32})
