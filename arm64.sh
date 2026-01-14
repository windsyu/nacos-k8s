#/bin/bash

# --- 变量定义 (确保脚本中有这些变量) ---
TAG="260113v0.2"
TAR_FILE="nacos-operator-arm64-${TAG}.tar"

# --- 执行构建并导出 ---
echo "正在基于 ./operator 目录构建 arm64 镜像并导出到 ${TAR_FILE}..."

# 1. 使用 type=docker 确保 load 后有标签
# 2. 确保你已经切换到了支持导出到文件的 builder (如之前创建的 mybuilder)
docker build \
  --network=host \
  --build-arg HTTP_PROXY=http://127.0.0.1:7890 \
  --build-arg HTTPS_PROXY=http://127.0.0.1:7890 \
  --platform linux/arm64 \
  --tag nacos/nacos-operator:${TAG} \
  ./operator


docker save -o save/${TAR_FILE} nacos/nacos-operator:${TAG}

docker rmi nacos/nacos-operator:${TAG}
echo "arm64镜像已经清理了"

# --- 结果检查 ---
if [ $? -eq 0 ]; then
  echo "------------------------------------------------"
  echo "✅ 成功! arm64 镜像已构建并保存为: ${TAR_FILE}"
  echo "文件大小: $(du -sh save/${TAR_FILE} | cut -f1)"
  echo "---"
  echo "您可以使用以下命令在任何机器上加载它:"
  echo "docker load -i ${TAR_FILE}"
  echo "------------------------------------------------"
else
  echo "❌ 失败! 构建或导出过程出错。"
  exit 1
fi