# Software patch-panel.
class PatchPanel < Trema::Controller
  PRIORITY = {
    patch: 1000,
    mirror: 2000
  }

  def start(_args)
    @patch = Hash.new { |h,k| h[k]=[] }
    @mirror = Hash.new { |h,k| h[k]=[] }
    logger.info 'PatchPanel started.'
  end

  def switch_ready(dpid)
    @patch[dpid].each do |port_a, port_b|
      delete_flow_entries dpid, port_a, port_b
      add_flow_entries dpid, port_a, port_b
    end
    @mirror[dpid].each do |port_a, port_b|
      delete_flow_entries dpid, port_a, port_b
      add_flow_entries dpid, port_a, port_b
    end
  end

  def create_patch(dpid, port_a, port_b)
    add_flow_entries dpid, port_a, port_b
    @patch[dpid].push([port_a, port_b].sort)
  end

  def delete_patch(dpid, port_a, port_b)
    delete_flow_entries dpid, port_a, port_b
    @patch[dpid].delete([port_a, port_b].sort)
    @mirror[dpid].each do | mir |
      if mir[0] == port_a || mir[0] == port_b then
        @mirror[dpid].delete(mir)
      end
    end
  end

  def create_mirror(dpid, monitor_port, mirror_port)
    add_mirror_entries dpid, monitor_port, mirror_port
    @mirror[dpid].push([monitor_port, mirror_port]) #no sorting
  end

  def delete_mirror(dpid, monitor_port, mirror_port)
    delete_mirror_entries dpid, monitor_port, mirror_port
    @mirror[dpid].delete([monitor_port, mirror_port]) #no sorting
  end

  def show_list
    show_patch_mirror_list
  end

  private

  def add_flow_entries(dpid, port_a, port_b)
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_a),
                      priority: PRIORITY[:patch],
                      actions: SendOutPort.new(port_b))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_b),
                      priority: PRIORITY[:patch],
                      actions: SendOutPort.new(port_a))
  end

  def delete_flow_entries(dpid, port_a, port_b)
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_a))
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_b))
  end

  def add_mirror_entries(dpid, monitor_port, mirror_port)
    cnt = 0
    @patch[dpid].each do |port_a, port_b|
      if port_a == monitor_port || port_b == monitor_port then
        send_flow_mod_add(dpid,
                          match: Match.new(in_port: port_a),
                          priority: PRIORITY[:mirror],
                          actions: [SendOutPort.new(port_b),
                                    SendOutPort.new(mirror_port)])
        send_flow_mod_add(dpid,
                          match: Match.new(in_port: port_b),
                          priority: PRIORITY[:mirror],
                          actions: [SendOutPort.new(port_a),
                                    SendOutPort.new(mirror_port)])
        cnt += 1
      end
    end
    if cnt == 0 then
      logger.info 'cannot create mirror'
    end
  end

  def delete_mirror_entries(dpid, monitor_port, mirror_port)
    send_flow_mod_delete(dpid, 
                         match: Match.new(in_port: monitor_port), 
                         out_port: mirror_port)
    @patch[dpid].each do | pat |
      if pat[0] == monitor_port then
        send_flow_mod_delete(dpid, 
                             match: Match.new(in_port: pat[1]), 
                             out_port: mirror_port)
        break
      end
    end
  end

  def show_patch_mirror_list
    str = []
    str.push("[patch list (port1 -- port2)]")
    @patch.each do | p |
      str.push("switch: 0x#{p[0].to_s(16)}")
      p[1].each do | pat |
        str.push(pat.join(" -- "))
      end
      str.push("")
    end
    str.push("[mirror list (monitor --> mirror)]")
    @mirror.each do | m |
      str.push("switch: 0x#{m[0].to_s(16)}")
      m[1].each do | mir |
        str.push(mir.join(" -> "))
      end
      str.push("")
    end
    return str
  end
end
