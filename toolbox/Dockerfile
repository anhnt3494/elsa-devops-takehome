# syntax=docker/dockerfile:1.7
FROM alpine:3.22 AS fetch
ARG TARGETARCH
ARG KUBECTL_VERSION=v1.36.5
ARG HELM_VERSION=v3.22.1
ARG TERRAFORM_VERSION=1.16.7
ARG K6_VERSION=v1.8.2
ARG KUBECONFORM_VERSION=v0.8.0
ARG ARGOCD_VERSION=v3.5.6
RUN apk add --no-cache curl unzip
WORKDIR /out
RUN set -eux; \
    curl -fsSLo kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256")  kubectl" | sha256sum -c -; \
    curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"; \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz.sha256sum" | sha256sum -c -; \
    tar -xzf "helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" --strip-components=1 "linux-${TARGETARCH}/helm"; \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip"; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "linux_${TARGETARCH}.zip" | sha256sum -c -; \
    unzip -q "terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" terraform; \
    curl -fsSL "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-${TARGETARCH}.tar.gz" \
      | tar -xz --strip-components=1 "k6-${K6_VERSION}-linux-${TARGETARCH}/k6"; \
    curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-${TARGETARCH}.tar.gz" \
      | tar -xz kubeconform; \
    curl -fsSLo argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${TARGETARCH}"; \
    chmod +x kubectl helm terraform k6 kubeconform argocd; \
    rm -f ./*.tar.gz ./*.zip

FROM alpine:3.22
RUN apk add --no-cache bash curl jq git ca-certificates coreutils
COPY --from=fetch /out/ /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENV KUBECONFIG=/root/.kube/config
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
