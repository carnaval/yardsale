function grid{V}(n :: Int, m :: Int, default :: V)
    n > 0 && m > 0 || error()
    dim = (n+1,m+1)
    vertices = Array(V, dim...)
    for z = 0:m
        for x = 0:n
            uv = vec2(float32(x)/n, float32(z)/m)
            p = vec3(uv.x - 5f-1, 0f0, uv.y - 5f-1)
            vertices[1+x, 1+z] = copywith(default,
                                          pos = p,
                                          texc = uv)
        end
    end
    indices = Uint16[]
    sizehint(indices, 6*m*n)
    for z = 1:m
        for x = 1:n
            ll = uint16(sub2ind(dim, x,   z)) - 1
            lr = uint16(sub2ind(dim, x+1, z)) - 1
            ul = uint16(sub2ind(dim, x,   z+1)) - 1
            ur = uint16(sub2ind(dim, x+1, z+1)) - 1
            push!(indices, ll, lr, ur, ur, ul, ll)
        end
    end
    (typed_cpu_buffer(V, reshape(vertices, (n+1)*(m+1))), typed_cpu_buffer(Uint16, indices))
end

####

const heightfield_source = """
const int layer[] = { 0, 0, 1, 1, 2, 2, 2};
//const float fallbegin[] = {-0.25, 0.25, -0.25, 0.25, -0.25, 0.25 };
//const float falloff[] =   {0.75, 1.25, 0.75, 1.25, 0.75, 1.25 };
const float soff[] = { 0, 1, 0, 1, 0, 1, 0};
const float lin[] = { 1, 1, 8, 8, 32, 32, 64 };
const float off[] = { 0.0, 0.5, 0.0, 0.5, 0, 0.5, 0.5 };
//const vec2 offd[] = { vec2(1, 0.5), vec2(0.8, -1), vec2(-1.2, 0.7), vec2(0.6, -0.9), vec2(1, 0.9), vec2(0.8, -1.5), vec2(-1, 1.2), vec2(1.0, -1.3) };
const int offdp[] = { 2, 5, 4, 6, 1, 3, 2};
const vec2 offd[] = { vec2(0.26, 0.97), vec2(-0.71, 0.71), vec2(-0.97, -0.26), vec2(-0.26, -0.97), vec2(0.71, -0.71), vec2(0.97, 0.26) };
const float inf[] = { 2.0, 2.0, 0.5, 0.5, 0.05, 0.05, 0.05 };
const float gi = 0.8;
#define M_PI 3.1415926535897932384626433832795

/*const int ns = 8;
const vec2 samples[] = {vec2(1, 1), vec2(-1, -1), vec2(-1, 1), vec2(1, -1),
                        vec2(0.0, 1), vec2(0.0, -1), vec2(-1, 0.0), vec2(1, 0.0) };*/
/*const int ns = 16;
const vec2 samples[] = { vec2(0.007937789, 0.73124397),
                         vec2(-0.10177308, -0.6509396),
                         vec2(-0.9906806, -0.63400936),
                         vec2(-0.5583586, -0.3614012),
                         vec2(0.7163085, 0.22836149),
                         vec2(-0.65210974, 0.37117887),
                         vec2(-0.12714535, 0.112056136),
                         vec2(0.48898065, -0.66669613),
                         vec2(-0.9744036, 0.9155904),
                         vec2(0.9274436, -0.9896486),
                         vec2(0.9782181, 0.90990245),
                         vec2(0.96427417, -0.25506377),
                         vec2(-0.5021933, -0.9712455),
                         vec2(0.3091557, -0.17652994),
                         vec2(0.4665941, 0.96454906),
                         vec2(-0.461774, 0.9360856) };
*/

const float speed[] = { 2, 2, 1.5, 1.5, 1.0, 1.0, 2 };
const float gl = 0.5;
const int ns = 1;
const vec2 samples[] = {vec2(0, 0)};
float water_surface(sampler2DArray noise_tex, vec3 water_texc, float t)
{
  float y = 0;
  float tot = 0;
  for(int i = first_oct; i < octaves; i++) {
    vec2 p = (water_texc.xy)*lin[i] +  vec2(1,1)*off[i] - normalize(offd[offdp[i]-1])*t*speed[i]*lin[i] + (1.0/(octaves*1024))*i.xx;
    //vec2 rot = vec2(cos((t + i)*2), sin((t + i)*2));//offd[octaves - i];
    vec2 pp = p;//vec2(p.x*rot.x - p.y*rot.y, p.y*rot.x + p.x*rot.y);
    float r = 0;
    for(int s = 0; s < ns; s++) {
      vec2 offset = samples[s]/512;
//      if(octaves >= 6)
//        offset = vec2(offset.x*rot.x - offset.y*rot.y, offset.y*rot.x + offset.x*rot.y);
      r += texture(noise_tex, vec3(pp*gl + offset, water_texc.z))[layer[i]];
    }
    float at = mod(t*20, 1);
//    float mid = (fallbegin[i] + falloff[i])*0.5;
    y += (r*inf[i]/ns);
//*(1+cos(2*M_PI*at + soff[i]*M_PI))*0.5;
//*smoothstep(fallbegin[i]+0.1, mid, at)*(1 - smoothstep(mid, falloff[i]-0.1, at));//*cos((t*M_PI+i));///ns;//(i+1);
  }
  return y*gi;//*00000.1 + sin(water_texc.x*10 + t*50);
}

float dd(float fn2, float fn, float fp, float fp2, float h)
{
  return (-fp2 + 8*fp - 8*fn + fn2)/(12.0*h);
}

vec2 water_normals(float height, sampler2DArray noise_tex, vec3 water_texc, float t)
{
  float dl = 2.0/1024;
  /*
  float dx = height-water_surface(noise_tex, water_texc + vec2(dl, 0, 0), t);
  float dy = height-water_surface(noise_tex, water_texc + vec2(0, dl, 0), t);
  */
  const float hs[] = { -2, -1, 1, 2 };
  float px[4];
  float py[4];
  vec3 hx = vec3(1, 0, 0)*dl;
  vec3 hy = vec3(0, 1, 0)*dl;
  for(int i = 0; i < 4; i++) {
    px[i] = water_surface(noise_tex, water_texc + hx*hs[i], t);
    py[i] = water_surface(noise_tex, water_texc + hy*hs[i], t);
  }
  return vec2(-dd(px[0], px[1], px[2], px[3], dl),
              -dd(py[0], py[1], py[2], py[3], dl));
}

//  y += cos(f_texc.x + t);
//  y /= tot;
//  y += 3.0*sin(t*100 + 3*(1 + f_texc.x + f_texc.y));

""";

const map_shader = compile_shader(:WaterMap,
"""
in vec2 pos;
out vec2 f_texc;

void main(void)
{
  gl_Position = vec4(pos, -1.0, 1.0);
  f_texc = vec2(1.0 + pos.x, 1.0 + pos.y)*0.5;
}
""",
"""
const int octaves = 4;
const int first_oct = 0;
$heightfield_source
uniform vec2 uv_offset;
uniform sampler2DArray tex;
// time in [0, 1] wrapping around
uniform float t;
uniform float tex_layer;
in vec2 f_texc;
void main(void) {
  float height = water_surface(tex, vec3(f_texc + uv_offset, tex_layer), t);
//  gl_FragColor = vec4(height, dFdx(height), -dFdy(height), 1);
  
  gl_FragColor = vec4(height, 0, 0, 1);//water_normals(height, tex, f_texc, t), 1);
//  gl_FragColor = vec4(0,0,0,gl_FragColor*0.00001) + texture(tex, vec3(f_texc + uv_offset, tex_layer));
}

""")

const surf_shader = compile_shader(:WaterSurf,
"""
uniform mat4 proj;
uniform mat4 view;
uniform sampler2D tex;
uniform vec3 light_pos;

in vec3 pos;
in vec2 texc;
out vec2 f_texc;
out vec3 f_world;

void main(void)
{
  vec3 real_pos = pos.xyz;
  real_pos.y += texture2D(tex, texc).x;
  vec4 world = view*vec4(real_pos, 1.0);
//  world.y += min(t, 0);
  gl_Position = proj*world;
  f_texc = texc;
  f_world = world.xyz/world.w;
}
""",
"""
const int first_oct = 3;
const int octaves = 6;
$heightfield_source
uniform vec2 uv_offset;
uniform vec3 cam_world;
uniform vec3 light_pos;
uniform sampler2D tex;
uniform samplerCube sky;
uniform sampler2D foam_tex;
uniform sampler2DArray noise_tex;
uniform float t;
uniform float tex_layer;

in vec2 f_texc;
in vec3 f_world;
void main(void)
{
  vec3 ld = -normalize(f_world - light_pos);
  vec2 texc = f_texc + uv_offset;
  vec4 tx = texture2D(tex, f_texc);
  float height = tx.x;//water_surface(noise_tex, vec3(texc, tex_layer), t);
  vec2 nor_pck = water_normals(height, noise_tex, vec3(texc, tex_layer), t);
  float y_disp = tx.x;
  //vec2 qn = nor_pck*54; //*(1/(0.0133));
  vec2 qn = nor_pck*0.0133*2;
  vec3 nor = normalize(vec3(qn.x, 1, qn.y));
  vec3 V = f_world - cam_world.xyz;
  float dist = length(V);
  vec3 view_dir = V/dist;
  float gamma = max(0, dot(reflect(ld, nor), view_dir));
  float L = clamp(dot(nor, ld), 0.6, 1.0);
//  if(L != 0)
  float sp = pow(gamma, 150.0);
  //  gl_FragColor = vec4((nor + 1)*.5, 1);
  vec3 flat_color = mix(vec3(0.2, 0.4, 0.8), vec3(0.6, 0.8, 0.9), L.xxx);
  vec3 ofs = vec3(texc.x-0.5, 0, texc.y-0.5)*2;
  ofs.y += max(y_disp*0.013, 0);
  vec3 refl_dir = reflect(view_dir, nor) + ofs;
  refl_dir.y = max(refl_dir.y, 0.01);
  vec3 refl_color = texture(sky, refl_dir).rgb;
  vec3 refr_dir = refract(view_dir, nor, 0.75);
  vec3 water_abs = 1 - vec3(0.35, 0.04, 0.0);
  vec3 refr_color = texture(sky, refr_dir + ofs).rgb*water_abs;
  vec3 spc_color = (0.8).xxx;//vec3(1, 0, 0);
  vec4 foam_color = texture(foam_tex, texc*4);
  float foam = smoothstep(0.0, 1.0, y_disp)*(1 - dot(nor, vec3(0, 1, 0))*2);
  foam = clamp(foam, 0.0, 0.8);
  float F_bias = 0.5;
  float F = 1 - clamp(dot(-view_dir, nor), 0.0, 1.0);
  gl_FragColor = vec4(mix(mix(refr_color, refl_color, F), foam_color.rgb, foam*foam_color.w)*L + spc_color*sp, 0.99);
  //vec3 fogColor = vec3(94.0/255.0, 94.0/255.0, 110.0/255.0);
//  ofs.y = 0;
  vec3 fogColor = texture(sky, view_dir + ofs).rgb;
  gl_FragColor = mix(gl_FragColor, vec4(fogColor, 1.0), min(exp2(dist*0.0005)*0.5 - 1, 1.0));
//  gl_FragColor *= 0.00001;
//  gl_FragColor += vec4(/*height.xxx*/y_disp.xxx, 1);
//  gl_FragColor += vec4(L.xxx, 1);
//  gl_FragColor += vec4(L.xxx, 1);
//  gl_FragColor = vec4(length(qn*8).xxx, 1);
//  gl_FragColor = vec4(texture2D(tex, texc).xxx, 1);
}
""")

#transform!(r.camera_node, vec3(-81.31444f0, 36.256485f0, 31.863846f0))
const map_bindings = bindings(map_shader, quad_buffer, @buffer_format pos)
#const SURF_MAP_DIM = vec2(4096, 4096)
const SURF_MAP_DIM = vec2(1024, 1024)
const hm = open(make_dds_tex, "noise.dds")
const map_tex = alloc_tex2d(SURF_MAP_DIM.x, SURF_MAP_DIM.y, :FLOAT)
const map_fb = Framebuffer()
attach_color!(map_fb, 0, map_tex)

###

const skybox_shader = compile_shader(:Skybox,
"""
uniform mat4 proj;
in vec3 pos;
out vec3 wp;
void main(void)
{
  wp = pos*4000;
  gl_Position = proj*vec4(wp, 1);
}
""",
"""
uniform samplerCube skybox;
in vec3 wp;
void main(void)
{
  gl_FragColor = texture(skybox, wp);
}
""")

const cube_vs = make_vertex_buffer(Vec3,
                                   [vec3(-1, -1,  1), vec3( 1, -1,  1),
                                    vec3( 1,  1,  1), vec3(-1,  1,  1),
                                    vec3(-1, -1, -1), vec3( 1, -1, -1),
                                    vec3( 1,  1, -1), vec3(-1,  1, -1)])
const cube_is =
    make_index_buffer(Uint16[0, 1, 2, 2, 3, 0, 3, 2, 6, 6, 7, 3,
                             7, 6, 5, 5, 4, 7, 4, 0, 3, 3, 7, 4,
                             0, 1, 5, 5, 4, 0, 1, 5, 6, 6, 2, 1])
const skybox_bnds = bindings(skybox_shader, cube_vs, @buffer_format pos)
const foam_tex = open(make_dds_tex, "foam.dds")

###



bind(screen)

function render_surf_map(ofs)
    uniforms = WaterMapUniforms()
    bind(map_fb)
    glViewport(0, 0, SURF_MAP_DIM.x, SURF_MAP_DIM.y)
    glUseProgram(map_shader.program)
    bind(map_bindings)
    bind(quad_ibuffer)
    bind_tex(hm, int32(0))
    uniforms.tex = int32(0)
    uniforms.uv_offset = ofs
    uniforms.tex_layer = hm.layer
    global tms;
    tms = float32((time() - t0)*0.008 % 1.0)
#    if :t in names(uniforms)
    uniforms.t = tms
#    end
    bind(uniforms)
#    glBlendFunc(1, 0);
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0)
#    glBlendFunc(GL_ONE, GL_ZERO);
    glGenerateMipmap(GL_TEXTURE_2D)
    bind(screen)
    glViewport(0, 0, W, H) #TODO !!!
end

#const PER = shuffle(["front", "left", "back", "right", "top", "top"])
#println(PER)
#const PER = ["left", "back", "top", "bot", "front", "right"]
const PER = ["right", "left", "top", "bot", "front", "back"]
const sky_cubemap = make_dds_cube(map(open, ["sky_"*x*".dds" for x in PER]))

immutable SurfVertex
    pos :: Vec3
    texc :: Vec2
end
copywith(v::SurfVertex;pos=v.pos,texc=v.texc) = SurfVertex(pos, texc)
(vs,is) = grid(200, 200, SurfVertex(vec3(), vec2()))
const surf_vs = make_vertex_buffer(SurfVertex, vs[:])
const surf_is = make_index_buffer(is[:])
const bnds = bindings(surf_shader, surf_vs, SurfVertex)
const t0 = time()

wire = false
function rendersurf(r :: Renderer, prj :: Mat4, view :: Mat4, ofs :: Vec2)
    skybox_uniforms = SkyboxUniforms()
    glUseProgram(skybox_shader.program)
    bind(skybox_bnds)
    bind_tex(sky_cubemap, int32(0))
    skybox_uniforms.proj = prj*view
    skybox_uniforms.skybox = int32(0)
    bind(skybox_uniforms)
    bind(cube_is)
    glDrawElements(GL_TRIANGLES, length(surf_is), GL_UNSIGNED_SHORT, 0)

    render_surf_map(ofs)

    glUseProgram(surf_shader.program)
    bind(bnds)
    bind_tex(map_tex, int32(0))
    glGenerateMipmap(GL_TEXTURE_2D)
    bind_tex(sky_cubemap, int32(1))
    bind_tex(foam_tex, int32(2))
    bind_tex(hm, int32(3))
    surf_uniforms = WaterSurfUniforms()
    surf_uniforms.tex = int32(0)
    surf_uniforms.tex_layer = hm.layer
    surf_uniforms.sky = int32(1)
    surf_uniforms.foam_tex = int32(2)
    surf_uniforms.noise_tex = int32(3)
    surf_uniforms.t = tms
    surf_uniforms.proj = prj*view
    surf_uniforms.view = translation(0, -40, 0)*scale(2*1500f0, 40f0, 2*1500f0)*translation(ofs.x, 0, ofs.y)
    surf_uniforms.light_pos = vec3(0, 1000, 100)#world_transform(light_node).t
    surf_uniforms.cam_world = world_transform(r.camera_node).t
    surf_uniforms.uv_offset = ofs;
    bind(surf_uniforms)
    bind(surf_is)
    wire && glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
    glDrawElements(GL_TRIANGLES, length(is), GL_UNSIGNED_SHORT, 0)
    wire && glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

end
