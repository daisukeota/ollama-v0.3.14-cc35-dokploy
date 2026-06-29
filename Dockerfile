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

# 【K40c最適化①】gpu/ 配下の全Goファイルを走査
# 変数名だけでなく、ハードコードされた「major < 5」などの条件式も正規表現で一網打尽にして「3（CC 3.5）」に引き下げます
RUN find gpu/ -type f -name "*.go" -print | xargs -r sed -i -E \
    -e 's/[mM]ajor\s*<\s*5/[mM]ajor < 3/g' \
    -e 's/CudaComputeMajorMin = 5/CudaComputeMajorMin = 3/g' \
    -e 's/CudaComputeMinorMin = 0/CudaComputeMinorMin = 5/g' \
    -e 's/CudaComputeMajorMin = "5"/CudaComputeMajorMin = "3"/g' \
    -e 's/CudaComputeMinorMin = "0"/CudaComputeMinorMin = "5"/g' \
    -e 's/cudaComputeMajorMin = 5/cudaComputeMajorMin = 3/g' \
    -e 's/cudaComputeMinorMin = 0/cudaComputeMinorMin = 5/g' \
    -e 's/cudaComputeMajorMin = "5"/cudaComputeMajorMin = "3"/g' \
    -e 's/cudaComputeMinorMin = "0"/cudaComputeMinorMin = "5"/g' || true

# 【K40c最適化②】内部のビルドスクリプトのコンパイルターゲット(sm_50等)をすべて「sm_35」に書き換える
RUN find llm/ -type f -exec sed -i 's/compute_50/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_50/sm_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/compute_52/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_52/sm_35/g' {} +

# ビルド実行
ENV CGO_ENABLED=1
RUN go generate ./... || { \
    echo "========================================="; \
    echo "=== BUILD FAILED: PRINTING CMAKE LOGS ==="; \
    echo "========================================="; \
    find /build/llm/build/ -name "CMakeError.log" -exec echo "--- {} ---" \; -exec cat {} \; ; \
    exit 1; \
}
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