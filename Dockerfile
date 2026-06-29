# === ステージ1: ビルド環境 (CUDA 11.8 + Ubuntu 22.04) ===
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
# CUDAのバイナリパスを確実に明示
ENV PATH=/usr/local/cuda/bin:${PATH}

# 必要な依存ツールのインストール (Ubuntu 22.04標準のCMake 3.22を確保)
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

# 【K40c最適化①】門番の条件式や定数定義を、スペース・タブ・型指定を問わず正規表現で一網打尽にして引き下げ
RUN find gpu/ -type f -name "*.go" -print | xargs -r sed -i -E \
    -e 's/CudaComputeMajorMin\s*([a-zA-Z0-9]*)\s*=\s*5/CudaComputeMajorMin = 3/g' \
    -e 's/CudaComputeMinorMin\s*([a-zA-Z0-9]*)\s*=\s*0/CudaComputeMinorMin = 5/g' \
    -e 's/cudaComputeMajorMin\s*([a-zA-Z0-9]*)\s*=\s*5/cudaComputeMajorMin = 3/g' \
    -e 's/cudaComputeMinorMin\s*([a-zA-Z0-9]*)\s*=\s*0/cudaComputeMinorMin = 5/g' \
    -e 's/([mM]ajor)\s*<\s*5/\1 < 3/g' \
    -e 's/([mM]ajor)\s*<=\s*4/\1 <= 2/g' || true

# 【デバッグ用】パッチがどう当たったか、実際のソースコードの前後5行をDokployのビルドログに強制出力
RUN echo "=========================================" \
    && echo "=== DEBUG: LOGGING PATCHED SOURCE CODE ===" \
    && echo "=========================================" \
    && grep -n -C 5 "too old" gpu/gpu.go || true \
    && grep -n -i "CudaCompute" gpu/gpu.go || true

# 【K40c最適化②】内部のビルドスクリプトのターゲットをすべて sm_35 に統一
RUN find llm/ -type f -exec sed -i 's/compute_50/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_50/sm_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/compute_52/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_52/sm_35/g' {} +

# ビルド実行
ENV CGO_ENABLED=1
RUN go generate ./...
RUN go build -o /build/ollama_bin .

# === ステージ2: 実行用軽量環境 ===
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y ca-certificates && apt-get clean && rm -rf /var/lib/apt/lists/*

# ビルド成果物のみをコピー
COPY --from=builder /build/ollama_bin /bin/ollama

ENV OLLAMA_HOST=0.0.0.0:11434
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 11434
ENTRYPOINT ["/bin/ollama"]
CMD ["serve"]