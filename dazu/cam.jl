# a simple 1st person camera
# loosely binded for now, just give it a scene node
const speed = 100f0
const angular_speed = 1f-3
target = vec3(0, 0, 0)
theta = 0f0
phi = 0f0
target_dist = 0f0
const HALF = float32(pi/2)
spherical(target,r,theta,phi) =
    Aff(target)*Aff(Quat(vec3(0, 1, 0), phi*2))*Aff(Quat(vec3(1, 0, 0), theta))*Aff(vec3(0, 0, r))
    
function camera_handle_event(ty, data, cam_node)
    global theta, target_dist, phi, target
    if ty == :mousewheel
        target_dist = clamp(target_dist - speed*data[2], 0f0, 5000f0)
    elseif ty == :keydown
        if data == int('z')
#            target_dist -= speed
        elseif data == int('s')
#            target_dist += speed
        elseif data == int('q')
#            vec3(-1, 0, 0)
        elseif data == int('d')
#            vec3(1, 0, 0)
        else
#            vec3()
        end
    elseif ty == :mousemotion
        (x,y,relx,rely,buttons) = data
#        println(relx, rely)
#        q_yaw = Quat(vec4(0, 1, 0), -relx*angular_speed)
#        q_pitch = Quat(vec4(1,0,0), -rely*angular_speed)
#        cam_node.transform = Aff(q_yaw * cam_node.transform.q * q_pitch, cam_node.transform.t)
        if buttons & 1 != 0 # left
            target = target + cam_node.transform.q*vec3(relx, rely, 0)
        end
        if buttons & 2 != 0 # middle
            theta = clamp(theta - rely*angular_speed, -HALF, HALF)
            phi = phi - relx*angular_speed
        end
        if buttons & 4 != 0 # right
        end
#        println(data)
    end
    cam_node.transform = spherical(target, target_dist, theta, phi)
#    transform!(cam_node, 
end
