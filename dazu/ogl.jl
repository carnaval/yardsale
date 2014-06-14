#include("geom.jl")
const W = 1920
const H = 1200
include("ff.jl")
SDL_Init(SDL_INIT_VIDEO)
SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_COMPATIBILITY)
win = SDL_CreateWindow("!", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, W, H, SDL_WINDOW_OPENGL)
ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_PRESENTVSYNC)
ctx = SDL_GL_CreateContext(win)
SDL_GL_SetSwapInterval(0)
SDL_GL_MakeCurrent(win, ctx)
SDL_StartTextInput()
bytestring(glGetString(GL_VERSION)) |> println
bytestring(glGetString(GL_RENDERER)) |> println
begin
    include("math.jl")
    m2 = lin_id
    include("skl.jl")
    include("skn.jl")
    include("dds.jl")
    include("anm.jl")
    include("tex.jl")
    include("sh.jl")
    include("buf.jl")
    include("cam.jl")
    include("fb.jl")
end

glClearColor(float32(1.0), float32(0.4), float32(0.0), float32(1.0))

cube_vxs = float32([
    -1.0, -1.0, -1.0,
     1.0, -1.0, -1.0,
     1.0,  1.0, -1.0,
    -1.0,  1.0, -1.0,
])
#ixs = [4, 5, 6]
cube_ixs = uint16([
0, 1, 2, 2, 3, 0,
])

function lookat(pos :: Vec4, target :: Vec4, up :: Vec4)
    dir = normalize(target - pos)
    right = normalize(cross(dir, up))
    up = normalize(cross(right,dir))
    Mat4(right.x, right.y, right.z,
		 up.x,   up.y,    up.z,
		-dir.x,  -dir.y,   -dir.z)*translation(-pos)
end

function proj(fov :: Float32, ratio :: Float32, znear :: Float32, zfar :: Float32)
    f = float32(1/tan(fov/2))
    Mat4(f/ratio, 0f0, 0f0, 0f0,
         0f0, f, 0f0, 0f0,
         0f0, 0f0, (zfar + znear)/(znear - zfar), -2*zfar*znear/(zfar-znear),
         0f0, 0f0, -1f0, 0f0)
end


include("scene.jl")
include("rq.jl")
include("char.jl")
include("ft.jl")




const GL_LEQUAL = 0x0203
glEnable(GL_DEPTH_TEST)
glDepthFunc(GL_LEQUAL)
glEnable(GL_BLEND)
glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS)
glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
glViewport(0, 0, W, H)

basic_shader = compile_shader(:basic,
"
uniform mat4 proj;
in vec3 v_posn;
out vec2 uv;
void main(void)
{
   gl_Position = vec4(v_posn, 1);
   uv = (gl_Position.xy + 1)*0.5;
}
 ",
"
uniform sampler2D tex0;
uniform sampler2D tex1;
uniform sampler2D depth;
uniform sampler2D shadow_depth;
uniform mat4 light_world;
in vec2 uv;

void main()
{
 gl_FragColor = texture2D(tex0, uv);
}

/*
void main(void)
{
 vec3 L = normalize(vec3(0, -1, -0.5));
 vec3 albedo = texture2D(tex0, uv).rgb;
 vec3 norm = texture2D(tex1, uv).rgb*2 - 1;
 float depth = texture2D(depth, uv).r;

 vec4 wp = vec4(uv.x, uv.y, depth, 1);
 wp = light_world*wp;
 vec2 shadow_uv = wp.xy/wp.w;
 float light_d = wp.z/wp.w;
 shadow_uv = clamp((shadow_uv + 1)*0.5, 0, 1);
 float d = texture2D(shadow_depth, shadow_uv).r;
 if(d <= light_d)
   gl_FragColor = vec4(albedo.xyz, 1);
 else
   gl_FragColor = vec4(0,1,0,1);
// gl_FragColor = vec4(d, 0,0,1);
}*/
")
#qqt = 0f0
function drawfsq(mat,mat2)
    glUseProgram(basic_shader.program)
    bind(NoVertexBuffer)
    bind_attr(basic_shader.attributes[ :v_posn ], cube_vxs)
#    set_uniform(basic_shader.uniforms[:proj], mat)
#    set_uniform(basic_shader.uniforms[ :light_world], mat2)
    set_uniform(basic_shader.uniforms[ :tex0 ], 0)
#   set_uniform(basic_shader.uniforms[ :tex1 ], 1)
#   set_uniform(basic_shader.uniforms[ :t ], qqt)
#   qqt += 0.1f0
#   set_uniform(basic_shader.uniforms[ :depth ], 2)
#   set_uniform(basic_shader.uniforms[ :shadow_depth ], 3)
    glDrawElements(GL_TRIANGLES, length(cube_ixs), GL_UNSIGNED_SHORT, cube_ixs)
    unbind_attr(basic_shader.attributes[ :v_posn ])
end

const flat_shader = compile_shader(:flat,
"""
uniform mat4 proj;
in vec3 pos;
in vec3 nor;
in vec2 texc;
out vec3 f_nor;
out vec2 f_texc;
void main(void)
{
  gl_Position = proj*vec4(pos, 1.0);
  f_nor = nor;
  f_texc = texc;
}
""",
"""
in vec3 f_nor;
in vec2 f_texc;
void main(void)
{
  vec3 ld = normalize(vec3(1, 1, 1));
  gl_FragColor = vec4(vec3(1, 1, 0)*max(0.2, dot(ld, f_nor)) , 1.0);
}
""")


function update_events()
    evt = zeros(Uint8, 60)
    if SDL_PollEvent(evt) == 1
        evtd = IOBuffer()
        write(evtd, evt)
        seekstart(evtd)
        evt_type = uint16(read(evtd, Uint32))
        evt_types = { 0x300 => :keydown, 0x301 => :keyup, 0x302 => :txtedit, 0x303 => :txtappend, 0x400 => :mousemotion, 0x403 => :mousewheel }
        #        println(evt_type)
        if haskey(evt_types, evt_type)
            ty = evt_types[evt_type]
            d = if ty == :txtappend# || ty == :txtedit
                _ = read(evtd, Uint32, 2) # useless infos
                str = replace(bytestring(readuntil(evtd, '\0')), "\0", "")
                str
            elseif ty == :keydown || ty == :keyup
                _ = read(evtd, Uint32, 4)
                read(evtd, Uint32)
            elseif ty == :mousemotion
		        _1 = read(evtd, Uint32, 3)
                buttonstate = read(evtd, Uint32)
		        x = read(evtd, Int32)
		        y = read(evtd, Int32)
		        rel_x = read(evtd, Int32)
		        rel_y = read(evtd, Int32)
		        #render_lines(["Motion: $_2 / $_3"], 500f0, 0f0, 0)
		        [x,y,rel_x,rel_y,buttonstate]
            elseif ty == :mousewheel
                _ = read(evtd, Uint32, 3)
                [read(evtd, Int32), read(evtd, Int32)]
	        else
                ()
            end
            #            println("e $ty : $d")
            (ty,d)
        else
	        #render_lines(["Event: $evt_type)"], 500f0, 0f0, 0)
	        (:unknown,[evt_type])
	    end
    else
        false
    end
end

function clip()
	global cursor_clipped
	# TODO SDL2 bug
     SDL_SetRelativeMouseMode(1)
	
	# Not working (deprecated ?)
    SDL_SetWindowGrab(win,1)
#	SDL_ShowCursor(0)
	cursor_clipped = true
end
function unclip()
	global cursor_clipped
	# TODO SDL2 bug
	# SDL_SetRelativeMouseMode(0)
	
	# Not working (deprecated ?)
	# SDL_SetWindowGrab(win,0)
#	SDL_ShowCursor(1)
	cursor_clipped = false
end


include("cl.jl")

const DISPLAY_MAP = false
const DISPLAY_SCB = false
cursor_clipped = false

include("shapes.jl")
function main()
    L = lin_id
    P = proj(float32(pi/4), float32(W/H), 1f0, 100000.0f0)
    if DISPLAY_MAP
        include("map.jl")
        L = lookat(vec4(), vec4(0,0,-1000), vec4(0,1,1))
    end
    if DISPLAY_SCB
        include("scb.jl")
        L = lookat(vec4(), vec4(0,0,-1000), vec4(0,1,1))
    end


    clear()
    clip()

    gc()

    #read_all_riot()
    cam_node = Node(main_scene.root, name = "camera")
    #transform!(cam_node, vec4(0, 50, 300))
    r = Renderer(main_scene, cam_node)

    lastfps = 0.0
    lastfps_update = time()
    console_opened = true

    light_node = Node(main_scene.root, name = "Light")

    shadow_r = Renderer(main_scene, light_node)
    shadow_fb = Framebuffer()
    shadow_depthtex = alloc_tex2d(W, H, :DEPTH32)
    attach_depth!(shadow_fb, shadow_depthtex)
    bind(shadow_fb)
    glViewport(0, 0, W, H)
    bind(screen)


    #fb = Framebuffer()
    #ERR()
    #colortex0 = alloc_tex2d(W, H, :RGBA)
    #colortex1 = alloc_tex2d(W, H, :RGBA)
    #ERR()
    #depthtex = alloc_tex2d(W, H, :DEPTH32)
    #ERR()
    #attach_color!(fb, 0, colortex0)
    #attach_color!(fb, 1, colortex1)
    #attach_depth!(fb, depthtex)
    #ERR()
    #bind(fb)
    #glViewport(0, 0, W, H)
    #bind(screen)
    dbgtx = nothing

    read_all_riot()
    glHint(GL_GENERATE_MIPMAP_HINT, GL_NICEST)
    gc()

    buf = Array(Uint8, W*H*3)

    n = 0

    fps_label = TextFrame()

    while true
        tbegin = time()
        bytes_begin = Base.gc_bytes()

        n += 1
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

	    
        ERR()
        light_node.transform = spherical(vec3(0,0,0), 2000f0, -0.3f0, 1.182f0)
        # LEGACY #######################################
        mat = P*L	
        # render scb
        if DISPLAY_SCB
            render_all_scb(mat)
        end
        ERR()
        # render map
        if DISPLAY_MAP
	        render_map(mat)
        end
        ERR()
        # END LEGACY ###################################

        # handle events, console only for now
        while (evt = update_events()) != false
            if evt[1] == :keydown && (evt[2] == 339 || evt[2] == int('²')) # ²
                console_opened = !console_opened
            else
                if console_opened
                    console_handle_event(evt[1], evt[2])
                else
                    camera_handle_event(evt[1], evt[2], cam_node)
                end
            end
        end
#        gc_disable()    
        yield()
        update_world_transform!(main_scene.root)
        #    fill_frame(SkinnedMesh, r)
        prepare(shadow_r)
        m2 = shadow_r.proj*shadow_r.view#*aff_to_mat(world_transform(cam_node));
        bind(shadow_fb)
        glClear(GL_DEPTH_BUFFER_BIT)
        #    render(shadow_r)

        bind(screen)  
        prepare(r)
        #    bind(fb)

        bind_tex(shadow_depthtex, int32(1))
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        #    render(r)
        fill_frame(SkinnedMesh, r)
        for dc in sm_rq.batch
            perform(r, dc)
        end
        #    println("Drawcalls : $(length(sm_rq.batch))\n")

        #    rendercsg(r.proj)
            rendersurf(r, r.proj, r.view, vec2(0, 0))
        #    rendersurf(r, r.proj, r.view, vec2(1, 0))
        #    rendersurf(r, r.proj, r.view, vec2(0, 1))
        #    rendersurf(r, r.proj, r.view, vec2(-1, 0))
        #    rendersurf(r, r.proj, r.view, vec2(0, -1))
        #    bind_tex(colortex0, int32(0))
        #    bind_tex(colortex1, int32(1))
        #    bind_tex(depthtex, int32(2))
        #    bind_tex(shadow_depthtex, int32(3))
        #    m2 = shadow_r.proj*aff_to_mat(inv(world_transform(light_node)))*aff_to_mat(world_transform(cam_node))*inv(r.proj)
#        dbgtx = map_tex
#        if dbgtx != nothing
#            bind_tex(dbgtx, int32(0))
#            drawfsq(P, m2)
#        end

        ERR()
        
        if console_opened
            render_console()
        end
        
        # shitty fps label
        glDisable(GL_DEPTH_TEST)
        
        bytes_this_frame = int(Base.gc_bytes()) - int(bytes_begin)
        fps_string = (lastfps >= 1000 ? "1s+" : @sprintf "%.2f" lastfps*1000)
        fps_label.text = "$fps_string ms/f / BPF $(bytes_this_frame/1024) Ko"
        fps_label.at = vec2(0f0, 0f0)
        update(fps_label)
        fill_frame(fps_label)
        for dc in txt_rq.batch
            perform(r, dc)
        end
        
        glEnable(GL_DEPTH_TEST)

#        gc_enable()
#        gc() # This imposes worst case scenario every frame
        # It's actually a good thing to develop with this because
        # it forces to keep the allocation count low for most frames
        # and thus will give predictable frame rate, even when we switch
        # to a less aggressive collection strategy. However, eventually,
        # TODO change this

        SDL_GL_SwapWindow(win)
        #    glReadPixels(0, 0, W, H, GL_RGB, GL_UNSIGNED_BYTE, buf)
        #    open("frame$n.raw", "w") do f
        #        write(f, buf)
        #    end
        if time() - lastfps_update > 1.0
#            println(lastfps*1000, " ms/f")
            lastfps = 0.0
            lastfps_update = time()
        end
        lastfps = max(lastfps, (time() - tbegin))
        ERR()
    end
end
main()
print("I'm ok !")
