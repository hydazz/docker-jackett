# build jackett for musl
FROM mcr.microsoft.com/dotnet/sdk:5.0-focal AS builder

# environment settings
ARG VERSION

RUN set -xe && \
	echo "**** install runtime packages ****" && \
	apt-get update && \
	apt-get install -y \
		binutils \
		musl-tools \
		jq && \
	if [ -z ${VERSION} ]; then \
		VERSION=$(curl -sL "https://api.github.com/repos/Jackett/Jackett/releases/latest" | jq -r .'tag_name' | cut -c 2-); \
	fi && \
	echo "**** download jackett ****" && \
	curl -o \
		/tmp/jackett.tar.gz -L \
		"https://github.com/Jackett/Jackett/archive/v${VERSION}.tar.gz" && \
	tar xzf \
		/tmp/jackett.tar.gz -C \
		/tmp/ --strip-components=1 && \
	echo "**** determine architecture ****" && \
	if [ "$(arch)" = "x86_64" ]; then \
		ARCH="x64"; \
	elif [ "$(arch)" = "aarch64" ]; then \
		ARCH="arm64"; \
	else \
		exit 1; \
	fi && \
	echo "**** build jackett ****" && \
	printf '{\n"configProperties": {\n"System.Globalization.Invariant": true\n}\n}' >/tmp/src/Jackett.Server/runtimeconfig.template.json && \
	dotnet publish /tmp/src/Jackett.Server \
		-f net5.0 \
		--self-contained \
		-c Release \
		-r linux-musl-${ARCH} \
		/p:TrimUnusedDependencies=true \
		/p:PublishTrimmed=true \
		-o /out && \
	echo "**** cleanup ****" && \
	rm -f /out/*.pdb && \
	chmod +x /out/jackett && \
	strip -s /out/*.so && \
	echo "**** done building jackett ****"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# runtime stage
FROM vcxpz/baseimage-alpine:latest

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Jackett version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="hydaz"

RUN set -xe && \
	echo "**** install runtime packages ****" && \
	apk add --no-cache \
		libcurl \
		libgcc \
		libstdc++ \
		libintl && \
	echo "**** cleanup ****" && \
	rm -rf \
		/tmp/*

# copy files from builder
COPY --from=builder /out /app/jackett

# add local files
COPY root/ /

# jackett healthcheck
HEALTHCHECK --start-period=10s --timeout=5s \
	CMD wget -qO /dev/null 'http://localhost:9117/torznab/all'

# ports and volumes
VOLUME /config
EXPOSE 9117
