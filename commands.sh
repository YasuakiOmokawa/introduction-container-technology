## コンテナのルートファイルシステムを作成
## Dockerのbashイメージをテンポラリディレクトリに展開し、ここをコンテナのルートファイルシステムとする

# 一時ディレクトリの作成
ROOTFS=$(mktemp -d)

# Dockerイメージの展開
CID=$(sudo docker container create bash)

# exportでコンテナを保存。exportするとtar形式のファイルになるらしいので、
# パイプで繋げて、一時ディレクトリへ解凍する
sudo docker container export $CID | tar -x -C $ROOTFS

# /usr/local/bin/bashを参照する一時ファイル/bin/bash というシンボリックリンクを作成
ln -s /usr/local/bin/bash $ROOTFS/bin/bash

# 作成したDockerのbashイメージを削除
sudo docker container rm $CID


## CPU, メモリを制限するグループ（cgroup）の作成。
## CPUは30%, メモリは10MBに制限

# Universally Unique Identifier（全世界で一意な識別子）を生成
UUID=$(uuidgen)

# コントロールグループの作成
# 書式）　cgcreate -t uid:gid -a uid:gid -g subsystems:path
# -t は、タスクを追加できるオプション。ユーザidとグループidを指定して、このグループのtasks疑似ファイルを所有する。
# -a は、タスクが持つシステムリソースへのアクセスを変更できるオプション。ユーザidとグループidを指定して、このグループのtasks以外の全疑似ファイルを所有する。
# -g は、コントロールグループが作成される「階層」を、subsystemという概念に関連付ける。cpuはCPU,memoryはメモリのこと。
#   コロンの後にはグループ名を指定する。今回は上記で作成したUUIDをグループ名とする。このコントロールグループはUUIDの名前で2つ作成され、
#   それぞれcpuとmemoryサブシステムによって制御される。
sudo cgcreate -t $(id -un):$(id -gn) -a $(id -un):$(id -gn) -g cpu,memory:$UUID

# サブシステムのパラメータを設定。
# 書式）　cgset -r parameter=value path_to_cgroup
#   parameter は、サブシステムの値を含んだ擬似ファイル
# UUIDで指定したコントロールグループに対し、memoryサブシステムのlimit_in_bytesを10MBに指定
cgset -r memory.limit_in_bytes=10000000 $UUID

# UUIDで指定したコントロールグループに対し、cpuサブシステムのcfs_period_usを1秒に指定（割り当ての単位はマイクロ秒。ここでは上限いっぱい割り当てる）
cgset -r cpu.cfs_period_us=1000000 $UUID

# UUIDで指定したコントロールグループに対し、cpuサブシステムのcfs_quota_usを300usに指定（割り当ての単位はマイクロ秒。ここでは上記の制限値の30%を割り当てる）
cgset -r cpu.cfs_quota_us=300000 $UUID


## コンテナの作成

CMD="/bin/sh"

# cgexecで、cgroup 内でプロセスを開始する。
# 書式） cgexec -g subsystems:path_to_cgroup command arguments
# subsystems .. カンマ区切りのサブシステム一覧。*を指定すると、利用可能なすべてのサブシステムに関連付けられたプロセスを指すことができる。
#               コンテナとして外部から独立させたいため、-g オプションを使い、サブシステムごとに同じ名前で作成したcgroup内で、プロセスを開始する。
#               cpuとmemoryサブシステムにUUIDの名前でcgroupを作成しているので、サブシステムごとにプロセスが開始される。
# command    .. 実行するコマンド
# arguments  .. 実行するコマンドの引数 
#
# unshareは、プロセスが新しいプロセスを生成することなく、
# 共有実行コンテキストを制御するために使う。コンテキストが制御される単位をNamespaceという。
# 書式） unshare [options] <program> [<argument>...]
# /bin/shコマンドの実行をNamespaceのなかで実行させることで、他から干渉されなくなる。干渉されたくないリソースの指定は下記オプションで指定できる。
#   -m .. mount名前空間
#   -u .. UTS名前空間。node名とdomain名を分離
#   -i .. IPC(Inter-Process Communication:プロセス間通信)名前空間。メッセージ・キュー、 セマフォ、共有メモリを分離
#   -n .. network名前空間。
#   -p .. pid名前空間。
#   -f .. プロセスフォークを分離。
#   -r .. UID/GIDを分離。異なる名前空間で同じUIDのユーザーを作ることができ、
#         root(UID=0)を名前空間内のroot権限のみに限定する。
cgexec -g cpu,memory:$UUID \
unshare -muinpfr /bin/sh -c "
  mount -t proc proc $ROOTFS/proc &&
  touch $ROOTFS$(tty); mount --bind $(tty) $ROOTFS$(tty) &&
  touch $ROOTFS/dev/pts/ptmx; mount --bind /dev/pts/ptmx $ROOTFS/dev/pts/ptmx &&
  ln -sf /dev/pts/ptmx $ROOTFS/dev/ptmx &&
  touch $ROOTFS/dev/null && mount --bind /dev/null $ROOTFS/dev/null &&
  /bin/hostname $UUID &&
  exec capsh --chroot=$ROOTFS --drop=cap_sys_chroot -- -c 'exec $CMD'
"

# 作成したルートファイルシステムとcgroupを削除して、後片付け
sudo cgdelete -r -g cpu,memory:$UUID
rm -rf $ROOTFS


## Namespaceの学習

# 現在のNamespaceとPID1のNamespaceを比較して、同じNamespaceを参照していることを確認
# ※ ls -l のシンボリックリンクの箇所のみ比較したかったので、下記のようなコマンドになった。差異は出なかったので、
# 同じNamespaceを参照していることが確認できた。
#
# 例） ls -l /proc/$$/ns
# total 0
# lrwxrwxrwx 1 ubuntu ubuntu 0 Aug 18 08:22 cgroup -> 'cgroup:[4026531835]'
# lrwxrwxrwx 1 ubuntu ubuntu 0 Aug 18 08:22 ipc -> 'ipc:[4026531839]'
# lrwxrwxrwx 1 ubuntu ubuntu 0 Aug 18 08:22 mnt -> 'mnt:[4026531840]'
# lrwxrwxrwx 1 ubuntu ubuntu 0 Aug 18 08:22 net -> 'net:[4026532041]'
# lrwxrwxrwx 1 ubuntu ubuntu 0 Aug 18 08:22 pid -> 'pid:[4026531836]'
# lrwxrwxrwx 1 ubuntu ubuntu 0 Aug 18 08:22 pid_for_children -> 'pid:[4026531836]'
# lrwxrwxrwx 1 ubuntu ubuntu 0 Aug 18 08:22 user -> 'user:[4026531837]'
# lrwxrwxrwx 1 ubuntu ubuntu 0 Aug 18 08:22 uts -> 'uts:[4026531838]'
diff <(ls -l /proc/$$/ns | perl -alne 'print "$F[8] $F[9] $F[10]"') <(sudo ls -l /proc/1/ns | perl -alne 'print "$F[8] $F[9] $F[10]"')

# 実行中のプロセスのNamespaceに接続して指定したコマンド実行できる。
# コマンド内部では現在のプロセスを既存のNamespaceに関連付けるsetns(2)を実行。
# ちなみに、コマンドの後ろについてる(2)というのは、コマンドのセクションの名前。2はシステムコールのこと。
# 参考) https://www.atmarkit.co.jp/flinux/rensai/linuxtips/073mannum.html
# UTSとUserのNamespaceを隔離し、ホスト名をfoobarに変更し、15秒スリープさせる
unshare -ur /bin/sh -c 'hostname foobar; sleep 15' &
# バックグラウンドで起動した上記のコマンドのプロセスを取得
PID=$(jobs -p)
# nsenterで上記のプロセスのホスト名を取得
#  -u .. UTS Namespaceを指定。
#  -t .. ターゲットにするPIDを指定
sudo nsenter -u -t $PID hostname

# 関連するすべてのプロセスが消えても、Namespaceを維持する。
# /proc/PID/ns 以下のファイルをbind mountすることで維持できる。
# bind mountとは。。シンボリックリンクに似た機能だが、マウントしている点が違う。
# マウント済の既存のディレクトリを別のディレクトリにマウントさせる機能。
# http://aikotobaha.blogspot.com/2011/10/bind-mount.html
# 設定ファイルのあるディレクトリ/etc/conf/みたいな箇所のコピーディレクトリを作って設定ファイルを弄り、bindマウントして設定ファイルの動作確認をする。
# OKだったら、弄ったコピーディレクトリのファイルをディレクトリ丸ごとコピー元に上書きしてしまう。
# ファイル単位で編集するとディレクトリレベルで設定を読み込むアプリケーションだと対応できないので、独立した領域で編集・テストすると安全ですよ。
touch ns_uts
sudo unshare --uts=ns_uts /bin/sh -c 'hostname foobar'
# bind mountされているか確認
mount | grep ns_uts
# プロセスとして終了しているが、bind mountされたファイルにコマンドを送ると以前のNamespaceをプロセスに関連付けられる。
# よって、仮想化インスタンスを追加せずにカーネルリソースを隔離できる
sudo nsenter --uts=ns_uts hostname


## cgroupの学習

# cgroup .. グループ化したプロセスのリソースを制限する。
# ディレクトリによる階層構造でグループを表現する。
# マウント先の確認
mount -t cgroup
# サブシステムごとの階層確認
tree -d /sys/fs/cgroup/cpu
# cgroupの操作方法 .. 以下の２種類
# cgroupfsに対するファイル操作、cgroup-tools(libcgroup)パッケージに含まれるコマンドで操作
#
# cgroupの作成と確認 .. プロセスが属するグループは/proc/<PID>/cgroup で確認する
UUID=$(uuidgen)
sudo cgcreate -g cpu,memory:$UUID
sudo cgexec -g cpu,memory:$UUID cat /proc/self/cgroup
# cgroupのグループに属するプロセスを確認 ( <SUBSYSTEM>/[<SUBGROUP>]/cgroup.procs を参照することで確認する)
sudo cgexec -g cpu:$UUID sleep 10 &
cat /sys/fs/cgroup/cpu/$UUID/cgroup.procs
# cgroupfsを直接操作してサブグループを作成し、CPUを制限する ( <SUBSYSTEM>/<SUBGROUP>/cgroup.procs にPIDを書き込むことで実現する )
# tee .. 標準出力にも出して、ファイルにも書き込むコマンド
UUID=$(uuidgen)
sudo mkdir /sys/fs/cgroup/cpu/$UUID
# 50000は単なる数字じゃなくて、使用量を制限するための値
sudo echo 50000 | sudo tee /sys/fs/cgroup/cpu/$UUID/cpu.cfs_quota_us
# PIDの書き込み
echo $$ | sudo tee /sys/fs/cgroup/cpu/$UUID/cgroup.procs
timeout 15s yes >/dev/null &
# topコマンドで、yesコマンドのCPU使用量が50%で頭打ちになることを確認

## Capabilityの学習

# root権限を細分化してプロセスやファイルに設定する。

