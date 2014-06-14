
type Framebuffer
    handle :: Uint32
    attachs :: Vector{Uint32}
end

function Framebuffer()
    handle = Uint32[0]
    glGenFramebuffers(1, handle)
    Framebuffer(handle[1], Uint32[])
end

const screen = Framebuffer(uint32(0), Uint32[])

attach_color!(fb :: Framebuffer, index, target) = (ty = GL_COLOR_ATTACHMENT0 + index; push!(fb.attachs, ty); attach!(fb, ty, target))
attach_depth!(fb :: Framebuffer, target) = attach!(fb, GL_DEPTH_ATTACHMENT, target)
function attach!(fb :: Framebuffer, attachment, tex :: Texture)
    if is_array(tex)
        glNamedFramebufferTexture3DEXT(fb.handle, attachment, tex.target, tex.handle, 0, tex.layer)
    else
        glNamedFramebufferTexture2DEXT(fb.handle, attachment, tex.target, tex.handle, 0) # 0 is mipmap lvl
    end
end

function bind(fb :: Framebuffer)
    glBindFramebuffer(GL_FRAMEBUFFER, fb.handle) # TODO GL_FB_DRAW/READ
    if fb.handle != 0
        glDrawBuffers(length(fb.attachs), fb.attachs)
#    else
#        glDrawBuffers()
    end
end
