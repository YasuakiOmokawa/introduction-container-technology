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
# -g は、コントロールグループ
sudo cgcreate -t $(id -un):$(id -gn) -a $(id -un):$(id -gn) -g cpu,memory:$UUID

cgset -r memory.limit_in_bytes=10000000 $UUID
cgset -r cpu.cfs_period_us=1000000 $UUID
cgset -r cpu.cfs_quota_us=300000 $UUID
