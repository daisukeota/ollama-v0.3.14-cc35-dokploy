# === ステージ1: ビルド環境 (CUDA 11.4 + Ubuntu 20.04) ===
FROM nvidia/cuda:11.4.3-devel-ubuntu20.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# 必要な依存ツールのインストール
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    cmake \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Go言語のインストール (v0.3.xのビルドに最適な1.22を指定)
RUN curl -fsSL https://golang.org/dl/go1.22.5.linux-amd64.tar.gz | tar -xz -C /usr/local
ENV PATH=$PATH:/usr/local/go/bin

WORKDIR /build

# 本家Ollamaのリポジトリから「v0.3.14」をピンポイントで取得
RUN git clone --branch v0.3.14 https://github.com/ollama/ollama.git .

# 【K40c最適化①】gpu.go の制限を CC 3.5 まで引き下げる
RUN sed -i 's/CudaComputeMajorMin = 5/CudaComputeMajorMin = 3/g' gpu/gpu.go \
    && sed -i 's/CudaComputeMinorMin = 0/CudaComputeMinorMin = 5/g' gpu/gpu.go

# 【K40c最適化②】内部のビルドスクリプトのコンパイルターゲット(sm_50等)をすべて「sm_35」に書き換える
RUN find llm/ -type f -exec sed -i 's/compute_50/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_50/sm_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/compute_52/compute_35/g' {} + \
    && find llm/ -type f -exec sed -i 's/sm_52/sm_35/g' {} +

# ビルド実行
ENV CGO_ENABLED=1
RUN go generate ./...
RUN go build -o /build/ollama_bin .

# === ステージ2: 実行用軽量環境 ===
FROM nvidia/cuda:11.4.3-runtime-ubuntu20.04

RUN apt-get update && apt-get install -y ca-certificates && apt-get clean && rm -rf /var/lib/apt/lists/*

# ビルド成果物のみをコピー
COPY --from=builder /build/ollama_bin /bin/ollama

ENV OLLAMA_HOST=0.0.0.0:11434
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 11434
ENTRYPOINT ["/bin/ollama"]
CMD ["serve"]