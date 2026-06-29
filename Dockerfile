# === ステージ1: ビルド環境 (CUDA 11.8 + Ubuntu 22.04) ===
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/cuda/bin:${PATH}

# 必要な依存ツールのインストール
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    cmake \
    patch \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Go言語のインストール (v0.3.xのビルドに最適な1.22を指定)
RUN curl -fsSL https://golang.org/dl/go1.22.5.linux-amd64.tar.gz | tar -xz -C /usr/local
ENV PATH=$PATH:/usr/local/go/bin

WORKDIR /build

# 本家Ollamaのリポジトリから「v0.3.14」をピンポイントで取得
RUN git clone --branch v0.3.14 https://github.com/ollama/ollama.git .

# 【K40c最適化①】文字列型（"5"）と数値型（5）の両方を完全に破壊して 3.5 に書き換える最強パッチ
RUN find gpu/ -type f -name "*.go" -print | xargs -r sed -i -E \
    -e 's/CudaComputeMajorMin\s*([a-zA-Z0-9]*)\s*=\s*["\x27]?5["\x27]?/CudaComputeMajorMin = 3/g' \
    -e 's/CudaComputeMinorMin\s*([a-zA-Z0-9]*)\s*=\s*["\x27]?0["\x27]?/CudaComputeMinorMin = 5/g' \
    -e 's/cudaComputeMajorMin\s*([a-zA-Z0-9]*)\s*=\s*["\x27]?5["\x27]?/cudaComputeMajorMin = 3/g' \
    -e 's/cudaComputeMinorMin\s*([a-zA-Z0-9]*)\s*=\s*["\x27]?0["\x27]?/cudaComputeMinorMin = 5/g' \
    -e 's/([mM]ajor)\s*<\s*5/\1 < 3/g' \
    -e 's/([mM]ajor)\s*<=\s*4/\1 <= 2/g' || true

# 【K40c最適化②】内部のビルドスクリプトのターゲットをすべて sm_35 に統一
RUN find llm/ -type f -exec sed -i 's/compute_50/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_50/sm_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/compute_52/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_52/sm_35/g' {} +

# ==========================================
# 5. 実績ある環境変数の注入と生成・ビルドの実行
# ==========================================
ENV CMAKE_CUDA_ARCHITECTURES="35"
ENV OLLAMA_CUSTOM_CUDA_ARCH="35"
ENV CGO_ENABLED=1

# 【超重要】実績ある ldflags パラメーターを正確に引き継ぎ、コンパイル時に内部変数を強制書き換え
RUN go generate ./... && \
    go build -ldflags "-w -s -X=github.com/ollama/ollama/gpu.CudaMinVersion=3.5" -o /build/ollama_bin .

# === ステージ2: 実行用軽量環境 ===
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y ca-certificates && apt-get clean && rm -rf /var/lib/apt/lists/*

# ビルド成果物のみをコピー
COPY --from=builder /build/ollama_bin /bin/ollama

EXPOSE 11434
ENV OLLAMA_HOST=0.0.0.0:11434
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all

ENTRYPOINT ["/bin/ollama"]
CMD ["serve"]