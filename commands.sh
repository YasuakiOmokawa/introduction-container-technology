## コンテナのルートファイルシステムを作成
## Dockerのbashイメージをテンポラリディレクトリに展開し、ここをコンテナのルートファイルシステムとする

# 一時ディレクトリの作成
ROOTFS=$(mktemp -d)

# Dockerイメージの展開
CID=$(sudo docker container create bash)

# 
sudo docker container export $CID | tar -x -C $ROOTFS

ln -s /usr/local/bin/bash $ROOTFS/bin/bash
sudo docker container rm $CID

