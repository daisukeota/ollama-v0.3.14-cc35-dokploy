# ==========================================
# 1. ベースイメージの指定 (実績のある CUDA 11.4 + Ubuntu 20.04)
# ==========================================
FROM nvidia/cuda:11.4.3-devel-ubuntu20.04

ENV DEBIAN_FRONTEND=noninteractive

# ==========================================
# 2. 必要な依存パッケージと最新のGo言語・GCC11の導入 (実績構成)
# ==========================================
RUN apt-get update && apt-get install -y \
    curl \
    git \
    software-properties-common \
    build-essential \
    && add-apt-repository ppa:longsleep/golang-backports -y \
    && add-apt-repository ppa:ubuntu-toolchain-r/test -y \
    && apt-get update && apt-get install -y \
    golang-go \
    gcc-11 \
    g++-11 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 110 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 110 \
    && rm -rf /var/lib/apt/lists/*

# ==========================================
# 2.5. 最新の CMake を公式スクリプトからインストール (v0.3.14の要件を満たす)
# ==========================================
RUN curl -sSL https://cmake.org/files/v3.26/cmake-3.26.4-linux-x86_64.sh -o /tmp/cmake.sh && \
    chmod +x /tmp/cmake.sh && \
    /tmp/cmake.sh --prefix=/usr/local --skip-license && \
    rm /tmp/cmake.sh

# ==========================================
# 3. Ollamaのソース取得とチェックアウト (ターゲットを v0.3.14 に変更)
# ==========================================
RUN git clone https://github.com/ollama/ollama.git /app/ollama && \
    cd /app/ollama && \
    git checkout refs/tags/v0.3.14

WORKDIR /app/ollama

# ==========================================
# 4. パッチの適用と門番の無効化 (プレーンテキスト一斉掃射)
# ==========================================
# メタ文字のエスケープ崩壊を防ぐため、愚直に全パターンを並べて確実に仕留めます
RUN sed -i 's/var CudaComputeMajorMin = "5"/var CudaComputeMajorMin = "3"/g' gpu/gpu.go || true \
    && sed -i 's/var CudaComputeMinorMin = "0"/var CudaComputeMinorMin = "5"/g' gpu/gpu.go || true \
    && sed -i 's/CudaComputeMajorMin = 5/CudaComputeMajorMin = 3/g' gpu/gpu.go || true \
    && sed -i 's/CudaComputeMinorMin = 0/CudaComputeMinorMin = 5/g' gpu/gpu.go || true \
    && sed -i 's/CudaComputeMajorMin = "5"/CudaComputeMajorMin = "3"/g' gpu/gpu.go || true \
    && sed -i 's/CudaComputeMinorMin = "0"/CudaComputeMinorMin = "5"/g' gpu/gpu.go || true \
    && sed -i 's/major < 5/major < 3/g' gpu/gpu.go || true \
    && sed -i 's/Major < 5/Major < 3/g' gpu/gpu.go || true \
    && sed -i 's/major <= 4/major <= 2/g' gpu/gpu.go || true \
    && sed -i 's/Major <= 4/Major <= 2/g' gpu/gpu.go || true

# 【K40c最適化②】内部のビルドスクリプトのターゲットをすべて sm_35 に統一
RUN find llm/ -type f -exec sed -i 's/compute_50/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_50/sm_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/compute_52/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_52/sm_35/g' {} +

# ==========================================
# 5. 環境変数の注入と生成・ビルドの実行 (実績構成)
# ==========================================
ENV CMAKE_CUDA_ARCHITECTURES="35"
ENV OLLAMA_CUSTOM_CUDA_ARCH="35"
ENV CGO_ENABLED=1

RUN go generate ./... && \
    go build -ldflags "-w -s -X=github.com/ollama/ollama/gpu.CudaMinVersion=3.5" -o /usr/local/bin/ollama .

# ==========================================
# 6. コンテナ起動設定
# ==========================================
EXPOSE 11434
ENV OLLAMA_HOST=0.0.0.0

ENTRYPOINT ["ollama", "serve"]