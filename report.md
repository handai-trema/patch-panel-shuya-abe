#レポート課題3-1

氏名: 阿部修也  

##課題内容
パッチパネルに以下の機能を追加しなさい.ただし，それぞれpatch_panelのサブコマンドとして実装すること．

1. ポートのミラーリング
2. パッチとポートミラーリングの一覧

また，発展課題として，それ以外に機能を追加してもよい．

##課題解答
###ポートのミラーリング
ポートのミラーリングを実装する．
特筆すべき仕様は以下の通り．

* すでにパッチが作られたポートにのみミラーリングが設定できる
* ミラーリングされているポートに関するパッチが削除された場合はミラーリングも終了する

ミラーリング実行は以下のようにして行う．ただし，monitor portとはミラーリング元のポート，mirror portとはミラーリング先のポートを表す．
```
bin/patch_panel mirror <dpid> <monitor port> <mirror port> 
```

####bin/patch_panel
mirrorを作りだすためのサブコマンドmirrorによってlib/patch_panel.rb内のcreate_mirrorメソッドを呼び出す．ここでは引数を渡すのみで，戻り値は受け取らない．

```ruby
  desc 'Create a mirror'
  arg_name 'dpid monitor_port mirror_port'
  command :mirror do |c|
    c.desc 'Location to find socket files'
    c.flag [:S, :socket_dir], default_value: Trema::DEFAULT_SOCKET_DIR

    c.action do |_global_options, options, args|
      dpid = args[0].hex
      monitor_port = args[1].to_i
      mirror_port = args[2].to_i
      Trema.trema_process('PatchPanel', options[:socket_dir]).controller.
        create_mirror(dpid, monitor_port, mirror_port)
    end
  end
```

####lib/patch_panel.rb
スイッチは，フローテーブルにおいてpriorityの高いエントリから順に，
条件がマッチするまでエントリを探索する．

今回はこれを利用し，パッチに関するフローエントリにおけるpriorityの値よりも
priorityの値が大きいフローエントリを追加することで，ミラーリングを行う．

#####create_mirror
ミラーリングの開始命令を受け取り，ミラーリングを開始するadd_mirror_entriesメソッドを呼び出したあと，
連想配列@mirror中の（dpidをキーとする）二次元配列に
モニターポート（ミラーリング元）とミラーポート（ミラーリング先）からなる
配列を追加する．
このとき，パッチを作るcreate_patchとは異なり，配列のソートは行わない（配列内の順序に意味があるため）．

```ruby
  def create_mirror(dpid, monitor_port, mirror_port)
    add_mirror_entries dpid, monitor_port, mirror_port
    @mirror[dpid].push([monitor_port, mirror_port]) #no sorting
  end
```

#####add_mirror_entries
実際にFlowModを送信してミラーリングを開始するためのメソッド．
@patch中，引数で指定されたdpidをキーとする二次元配列を参照し，
モニターポートを含むものがあれば
FlowModによってミラーポートを宛先ポートに追加したフローエントリを送信する．
このとき，priorityの値をパッチ作成時に送るFlowModメッセージよりも大きくしておく．
また，モニターポートにおける送受信の監視を実現するため，FlowModメッセージは2回送信することになる（送信時と受信時）．

```ruby
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
```

以下はpriorityの実装例である．ミラーリング用のpriorityの値をパッチ用のものよりも大きくしてある．
```ruby
  PRIORITY = {
    patch: 1000,
    mirror: 2000
  }
```

###パッチとポートミラーリングの一覧
連想配列@patchと@mirrorの要素を出力すればよい．
ただし，出力先はbin/patch_panelを実行している側のコンソールであるため，
bin/patch_panelがlib/patch_panel.rb中のメソッドの戻り値を受け取る必要がある．

実行は以下のようにして行う．コマンドライン引数は利用しない．
```
bin/patch_panel show
```

####bin/patch_panel
lib/patch_panel.rbを呼び出し，show_listメソッドを実行し，戻り値strを出力する．
このとき，strは出力を一行ずつ格納した配列であるため，これを改行区切りでコンソールに出力する．
```ruby
  desc 'Show patch list'
  arg_name ''
  command :show do |c|
    c.desc 'Location to find socket files'
    c.flag [:S, :socket_dir], default_value: Trema::DEFAULT_SOCKET_DIR

    c.action do |_global_options, options, args|
      str = Trema.trema_process('PatchPanel', options[:socket_dir]).controller.
        show_list()
      print(str.join("\n"))
    end
  end
```

####lib/patch_panel.rb
#####show_list
bin/patch_panelから呼び出され，show_patch_mirror_listを呼び出すメソッド．
```ruby
  def show_list
    show_patch_mirror_list
  end
```

#####show_patch_mirror_list
パッチを管理する@patch及びミラーリングを管理する@mirrorという2つの連想配列の各要素を参照し，
パッチまたはミラーの組をそれぞれ " -- " ，" -> " という文字列で結合して出力文字列に追加する．
出力文字列は一次元配列に格納され，bin/patchpanelに戻り値として渡される．
```ruby
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
```



###発展課題: ポートミラーリングの解除
ポートミラーリングの解除を実装する．
ミラーリングはフローエントリの変更ではなく追加で実装されているため，
該当するフローエントリを削除することで通常のパッチとしての機能が動作する．

実行コマンドは以下の通り．
```
bin/patch_panel delmirror <dpid> <monitor port> <mirror port>
```

####bin/patch_panel
コマンドライン引数を受け取り，lib/patch_panel.rbにおけるdelete_mirrorメソッドに渡す．
```ruby
  desc 'Delete a mirror'
  arg_name 'dpid monitor_port mirror_port'
  command :delmirror do |c|
    c.desc 'Location to find socket files'
    c.flag [:S, :socket_dir], default_value: Trema::DEFAULT_SOCKET_DIR

    c.action do |_global_options, options, args|
      dpid = args[0].hex
      monitor_port = args[1].to_i
      mirror_port = args[2].to_i
      Trema.trema_process('PatchPanel', options[:socket_dir]).controller.
        delete_mirror(dpid, monitor_port, mirror_port)
    end
  end
```

####lib/patch_panel.rb
#####delete_mirror
bin/patch_panelから引数を受け取り，
実際にFlowModメッセージでエントリを削除するためのdelete_mirror_entriesメソッドを呼び出す．
また，ミラーリングの組を管理する連想配列@mirrorから，削除対象のミラーリングに関する要素を削除する．
```ruby
  def delete_mirror(dpid, monitor_port, mirror_port)
    delete_mirror_entries dpid, monitor_port, mirror_port
    @mirror[dpid].delete([monitor_port, mirror_port]) #no sorting
  end
```

#####delete_mirror_entries
引数をもとにスイッチのフローテーブルからミラーリングに関するエントリを削除する．
このとき，sned_flow_mod_deleteのオプションとしてout_portをミラーポートに指定することにより，
同じポートをin_portの条件に持つ通常のパッチに関するフローエントリを残したまま，ミラーリングに関するエントリを削除することができる．
```ruby
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
```

###動作確認
以下のようにして動作確認を行った．
ただし，スイッチやホストに関する設定ファイルは課題リポジトリ内のサンプルファイル（patch_panel.conf）を用いている．

```
1. パッチパネルを起動する
2. host1，host2間でパケットを送受信する
3. host1，host2間をパッチでつなぐ
4. 2. を再度行う
5. host1をhost3にミラーリングする
6. 2. を再度行う
7. パッチとポートミラーリングの一覧を出力する
8. ミラーリングを解除する
9. 7. を再度行う
```

####1. パッチパネルを起動する
このときのフローテーブルは空で，各ホストの統計情報も空である．

####2. host1，host2間でパケットを送受信する
パッチでつながれていないため，パケットは宛先に届かず，フローテーブルは空のままである．

```
[trema dump_flows patch_panel]
NXST_FLOW reply (xid=0x4):

[trema show_stats host1]
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 1 packet

[trema show_stats host2]
Packets sent:
  192.168.0.2 -> 192.168.0.1 = 1 packet
```

####3. host1，host2間をパッチでつなぐ
"patch_panel create 0xabc 1 2"を実行する．フローテーブルは以下のようになる．
```
[trema dump_flows patch_panel]
NXST_FLOW reply (xid=0x4):
 cookie=0x0, duration=4.691s, table=0, n_packets=0, n_bytes=0, idle_age=4, priority=1000,in_port=1 actions=output:2
 cookie=0x0, duration=4.68s, table=0, n_packets=0, n_bytes=0, idle_age=4, priority=1000,in_port=2 actions=output:1
```

####4. 2. を再度行う
パッチで接続されたので，host1とhost2の間でパケットの送受信が行われる．
```
[trema show_stats host1]
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 2 packets
Packets received:
  192.168.0.2 -> 192.168.0.1 = 1 packet

[trema show_stats host2]
Packets sent:
  192.168.0.2 -> 192.168.0.1 = 2 packets
Packets received:
  192.168.0.1 -> 192.168.0.2 = 1 packet
```

####5. host1をhost3にミラーリングする
"patch_panel mirror 0xabc 1 3"を実行する．
フローテーブルに，ミラーリングに関するエントリが追加される．
このとき，確かにミラーリングに関するエントリの方がpriorityの値がパッチに関するエントリのものよりも大きくなっている．
```
[trema dump_flows patch_panel]
NXST_FLOW reply (xid=0x4):
 cookie=0x0, duration=6.19s, table=0, n_packets=0, n_bytes=0, idle_age=6, priority=2000,in_port=1 actions=output:2,output:3
 cookie=0x0, duration=47.984s, table=0, n_packets=1, n_bytes=42, idle_age=38, priority=1000,in_port=1 actions=output:2
 cookie=0x0, duration=6.184s, table=0, n_packets=0, n_bytes=0, idle_age=6, priority=2000,in_port=2 actions=output:1,output:3
 cookie=0x0, duration=47.973s, table=0, n_packets=1, n_bytes=42, idle_age=34, priority=1000,in_port=2 actions=output:1
```

####6. 2. を再度行う
このとき，host1，host2間では正しくパケットの送受信が行われる．
また，本来はhost3でも情報が読み取れるのだが，統計情報としては出力されない．
しかし，フローテーブルを確認すると，確かにhost3のつながっているポート3にもパケットが送信されている．
よって，パケットはhost3に到着しているが，そのパケットの宛先macアドレスが自らのものと一致しないために
パケットを捨てているものと思われる（これについては課題の範囲外であるため今回は無視した）．
```
[trema show_stats host1]
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 3 packets
Packets received:
  192.168.0.2 -> 192.168.0.1 = 2 packets

[trema show_stats host2]
Packets sent:
  192.168.0.2 -> 192.168.0.1 = 3 packets
Packets received:
  192.168.0.1 -> 192.168.0.2 = 2 packets

[trema show_stats host3]
実行結果なし

[trema dump_flows patch_panel]
NXST_FLOW reply (xid=0x4):
 cookie=0x0, duration=35.002s, table=0, n_packets=1, n_bytes=42, idle_age=20, priority=2000,in_port=1 actions=output:2,output:3
 cookie=0x0, duration=76.796s, table=0, n_packets=1, n_bytes=42, idle_age=67, priority=1000,in_port=1 actions=output:2
 cookie=0x0, duration=34.996s, table=0, n_packets=1, n_bytes=42, idle_age=15, priority=2000,in_port=2 actions=output:1,output:3
 cookie=0x0, duration=76.785s, table=0, n_packets=1, n_bytes=42, idle_age=63, priority=1000,in_port=2 actions=output:1
```

####7. パッチとポートミラーリングの一覧を出力する
"patch_panel show"を実行する．
確かに，パッチとポートミラーリングの一覧が出力されている．
```
[bin/patch_panel show]
[patch list (port1 -- port2)]
switch: 0xabc
1 -- 2

[mirror list (monitor --> mirror)]
switch: 0xabc
1 -> 3
```

####8. ミラーリングを解除する
"patch_panel delmirror 0xabc 1 3"を実行する．

####9. 7. を再度行う
確かに，ミラーリングに関するエントリは削除されている．
またパッチとポートミラーリングの一覧からも削除されている．
```
[trema dump_flows patch_panel]
NXST_FLOW reply (xid=0x4):
 cookie=0x0, duration=141.02s, table=0, n_packets=1, n_bytes=42, idle_age=131, priority=1000,in_port=1 actions=output:2
 cookie=0x0, duration=141.009s, table=0, n_packets=1, n_bytes=42, idle_age=127, priority=1000,in_port=2 actions=output:1

[bin/patch_panel show]
[patch list (port1 -- port2)]
switch: 0xabc
1 -- 2

[mirror list (monitor --> mirror)]
switch: 0xabc
```
