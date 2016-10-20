# Software patch-panel.
class PatchPanel < Trema::Controller
  PRIORITY = {
    patch: 1000,
    mirror: 2000
  }

  def start(_args)
    @patch = Hash.new { [] }
    @mirror = Hash.new { [] } 
    logger.info 'PatchPanel started.'
  end

  def switch_ready(dpid)
    @patch[dpid].each do |port_a, port_b|
      delete_flow_entries dpid, port_a, port_b
      add_flow_entries dpid, port_a, port_b
    end
  end

  def create_patch(dpid, port_a, port_b)
    add_flow_entries dpid, port_a, port_b
    @patch[dpid] += [port_a, port_b].sort
  end

  def delete_patch(dpid, port_a, port_b)
    delete_flow_entries dpid, port_a, port_b
    @patch[dpid] -= [port_a, port_b].sort
  end

  def create_mirror(dpid, monitor_port, mirror_port)
    logger.info 'create mirror'
    add_mirror_entries dpid, monitor_port, mirror_port
    @mirror[dpid] += [monitor_port, mirror_port] #no sorting
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
    send_flow_mod_delete(dpid, strict: true, priority: PRIORITY[:patch], match: Match.new(in_port: port_a))
    send_flow_mod_delete(dpid, strict: true, priority: PRIORITY[:patch], match: Match.new(in_port: port_b))
  end

  def add_mirror_entries(dpid, monitor_port, mirror_port)
    cnt = 0
    @patch[dpid].each_slice(2) do |port_a, port_b|
      if port_a == monitor_port then
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

  def show_patch_mirror_list

  end
end
