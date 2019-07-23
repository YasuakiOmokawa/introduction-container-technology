
# コンテナのルートファイルシステムを作成
# Dockerのbashイメージをテンポラリディレクトリに展開し、ここをコンテナのルートファイルシステムとする
ROOTFS=$(mktemp -d)
CID=$(sudo docker container create bash)
sudo docker container export $CID | tar -x -C $ROOTFS
ln -s /usr/local/bin/bash $ROOTFS/bin/bash
sudo docker container rm $CID

