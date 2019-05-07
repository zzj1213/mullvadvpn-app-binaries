# Shared environment
FROM debian:9 as common

RUN apt-get update -y && apt-get install -y \
    curl \
    git \
    make \
    python \
    sudo \
    unzip

RUN useradd -ms /bin/bash -G sudo user && \
    echo "%sudo ALL = (ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sudo_group

USER user

RUN cd /tmp && \
    curl -sf -L -O https://dl.google.com/android/repository/android-ndk-r19b-linux-x86_64.zip && \
    sudo mkdir /opt/android && \
    cd /opt/android && \
    sudo unzip -q /tmp/android-ndk-r19b-linux-x86_64.zip && \
    sudo mkdir toolchains && \
    sudo /opt/android/android-ndk-r19b/build/tools/make-standalone-toolchain.sh --platform=android-28 --arch=arm64 --install-dir=/opt/android/toolchains/android28-aarch64

# Build OpenSSL
FROM common as openssl-build
ENV OPENSSL_CONFIG="no-weak-ssl-ciphers no-ssl3 no-ssl3-method no-bf no-rc2 no-rc4 no-rc5 no-md4 no-seed no-cast no-camellia no-idea enable-ec_nistp_64_gcc_128 enable-rfc3779" \
    CC="/opt/android/toolchains/android28-aarch64/bin/aarch64-linux-android28-clang" \
    SYSROOT="/opt/android/toolchains/android28-aarch64/sysroot"

RUN sudo apt-get update -y && sudo apt-get install -y \
    file \
    gcc

RUN cd /tmp && \
    git clone https://github.com/mullvad/mullvadvpn-app-binaries.git && \
    cd mullvadvpn-app-binaries && \
    git submodule init && \
    git submodule update && \
    cd openssl && \
    sudo mkdir /opt/openssl && \
    sudo chown user:user /opt/openssl && \
    sed -i -e 's/\([" ]\)-mandroid\([" ]\)/\1\2/g' Configurations/10-main.conf && \
    ./Configure android64-aarch64 no-shared -static --prefix=/opt/openssl --openssldir=/opt/openssl ${OPENSSL_CONFIG} && \
    make clean && \
    make build_libs build_apps && \
    make install_sw

# Build WireGuard-go
FROM common as wireguard-go-build
ENV ANDROID_SYSROOT="/opt/android/toolchains/android28-aarch64/sysroot" \
    ANDROID_LLVM_TRIPLE="aarch64-linux-android" \
    ANDROID_C_COMPILER="/opt/android/toolchains/android28-aarch64/bin/aarch64-linux-android28-clang" \
    ANDROID_NDK_HOME="/opt/android/" \
    ANDROID_TOOLCHAIN_ROOT="/opt/android/toolchains/android28-aarch64" \
    ANDROID_ARCH_NAME="arm64"

RUN cd /tmp && \
    curl -sf -L -O https://dl.google.com/go/go1.12.4.linux-amd64.tar.gz && \
    cd /opt && \
    sudo tar -xzf /tmp/go1.12.4.linux-amd64.tar.gz && \
    export PATH="$PATH:/opt/go/bin/" && \
    sudo mkdir wireguard-android && \
    sudo chown user:user wireguard-android && \
    cd wireguard-android && \
    git init && \
    git remote add origin https://github.com/WireGuard/wireguard-android.git && \
    git fetch && \
    git checkout master && \
    cd app/tools/libwg-go/ && \
    sed -i -e '/export CGO_LDFLAGS/ s|$| -L/opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/28 -v|' Makefile && \
    sudo ln -s /opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/28/crtbegin_dynamic.o /opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/ && \
    sudo ln -s /opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/28/crtend_android.o /opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/ && \
    sudo ln -s /opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/28/crtbegin_so.o /opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/ && \
    sudo ln -s /opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/28/crtend_so.o /opt/android/toolchains/android28-aarch64/sysroot/usr/lib/aarch64-linux-android/ && \
    make

# Collect binaries
FROM debian:9

COPY --from=openssl-build /opt/openssl/lib/libcrypto.a /opt/mullvadvpn-binaries/libcrypto.a
COPY --from=openssl-build /opt/openssl/lib/libssl.a /opt/mullvadvpn-binaries/libssl.a
COPY --from=openssl-build /opt/openssl/include/openssl/opensslconf.h /opt/mullvadvpn-binaries/include/openssl/opensslconf.h
COPY --from=openssl-build /opt/openssl/include/openssl/opensslv.h /opt/mullvadvpn-binaries/include/openssl/opensslv.h
COPY --from=wireguard-go-build /opt/wireguard-android/app/tools/libwg-go/out/libwg-go.h /opt/mullvadvpn-binaries/include/libwg-go.h
COPY --from=wireguard-go-build /opt/wireguard-android/app/tools/libwg-go/out/libwg-go.so /opt/mullvadvpn-binaries/libwg-go.so
