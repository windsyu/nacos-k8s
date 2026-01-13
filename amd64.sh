#!/bin/bash

# --- 变量设置 ---
IMAGE_NAME="nacos/nacos-operator:latest" 
TAR_FILE="save/nacos-operator_amd64.tar"  # 推荐使用更简洁的文件名，避免路径问题

# 确保目标目录存在（如果 TAR_FILE 包含路径）
# 如果您使用了 "nacos/nacos-operator.tar"，您需要先创建 nacos 目录
# mkdir -p "$(dirname "$TAR_FILE")"


# --- 执行跨平台拉取并导出 ---
echo "正在拉取 AMD64 镜像 ${IMAGE_NAME} 并导出到 ${TAR_FILE}..."
docker buildx build \
  --platform linux/amd64 \
  --push=false \
  --tag nacos-operator-amd64:latest \
  --output type=tar,dest="${TAR_FILE}" \
  --file - \
  . <<EOF
FROM ${IMAGE_NAME}
EOF

# --- 结果检查 ---
if [ $? -eq 0 ]; then
  echo "✅ 成功! AMD64 镜像已保存到文件: ${TAR_FILE}"
  echo "---"
  echo "您可以使用以下命令在任何机器上加载它:"
  echo "docker load -i ${TAR_FILE}"
else
  echo "❌ 失败! 导出过程出错。"
fi