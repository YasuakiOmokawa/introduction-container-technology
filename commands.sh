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
cgexec -g cpu,memory:$UUID \

# unshareは、プロセスが新しいプロセスを生成することなく、
# 共有実行コンテキストを制御するために使う。コンテキストが制御される単位をNamespaceという。
# 書式） unshare [options] <program> [<argument>...]
# /bin/shコマンドの実行をNamespaceのなかで実行させることで、コマンドが他から干渉されなくなる。
#   -m .. mount名前空間
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

