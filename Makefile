
BUILD_DIR = $(PWD)/build
WINDOWS_BUILDROOT = openvpn-build/generic/tmp
WINDOWS_SOURCEROOT = openvpn-build/generic/sources

OPENSSL_VERSION = openssl-1.1.0h
OPENSSL_CONFIG = no-weak-ssl-ciphers no-ssl3 no-ssl3-method no-bf no-rc2 no-rc4 no-rc5 \
	no-md4 no-seed no-cast no-camellia no-idea enable-ec_nistp_64_gcc_128 enable-rfc3779

OPENVPN_VERSION = openvpn-2.4.6
OPENVPN_CONFIG = --enable-static --disable-shared --disable-debug --disable-server \
	--disable-management --disable-port-share --disable-systemd --disable-dependency-tracking \
	--disable-def-auth --disable-pf --disable-pkcs11 --disable-lzo --disable-lz4 \
	--enable-ssl --enable-crypto --enable-plugins \
	--enable-password-save --enable-socks --enable-http-proxy

# You likely need GNU Make for this to work.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
	PLATFORM_OPENSSL_CONFIG = -static
	PLATFORM_OPENVPN_CONFIG = --enable-iproute2
	SHARED_LIB_EXT = so*
	TARGET_OUTPUT_DIR = "linux"
endif
ifeq ($(UNAME_S),Darwin)
	SHARED_LIB_EXT = dylib
	TARGET_OUTPUT_DIR = "macos"
endif

.PHONY: help clean clean-build clean-submodules openssl openvpn windows libmnl libnftnl

help:
	@echo "Please run a more specific target"
	@echo "'make openvpn' will build a statically linked OpenVPN binary"
	@echo "'make libnftnl' will build static libraries of libmnl and libnftnl and copy to linux/"

clean: clean-build clean-submodules

clean-build:
	rm -rf $(BUILD_DIR)

clean-submodules:
	cd openssl; [ -e "Makefile" ] && $(MAKE) clean || true
	cd openvpn; [ -e "Makefile" ] && $(MAKE) clean || true

openssl:
	@echo "Building OpenSSL"
	mkdir -p $(BUILD_DIR)
	cd openssl; \
	KERNEL_BITS=64 ./config no-shared \
		--prefix=$(BUILD_DIR) \
		--openssldir=$(BUILD_DIR) \
	$(PLATFORM_OPENSSL_CONFIG) \
	$(OPENSSL_CONFIG) ; \
	$(MAKE) clean ; \
	$(MAKE) build_libs build_apps ; \
	$(MAKE) install_sw

update_openssl: openssl
	# Copy libraries and header files to target output directory for openssl.
	# This is not required for OpenVPN, but will be used to link openssl
	# statically in our other utilities.
	mkdir -p $(TARGET_OUTPUT_DIR)/include/openssl ; \
	cp openssl/lib{crypto,ssl}.a $(TARGET_OUTPUT_DIR)/ ; \
	cp openssl/include/openssl/openssl{conf,v}.h $(TARGET_OUTPUT_DIR)/include/openssl/

openvpn: openssl
	@echo "Building OpenVPN"
	mkdir -p $(BUILD_DIR)
	cd openvpn ; \
	autoreconf -i -v ; \
	./configure \
		--prefix=$(BUILD_DIR) \
		$(OPENVPN_CONFIG) $(PLATFORM_OPENVPN_CONFIG) \
		OPENSSL_CFLAGS="-I$(BUILD_DIR)/include" \
		OPENSSL_LIBS="-L$(BUILD_DIR)/lib -lssl -lcrypto" ; \
	$(MAKE) clean ; \
	$(MAKE) ; \
	$(MAKE) install
	strip $(BUILD_DIR)/sbin/openvpn
	cp $(BUILD_DIR)/sbin/openvpn $(TARGET_OUTPUT_DIR)/

openvpn_windows: clean
	rm -r "$(WINDOWS_BUILDROOT)"
	mkdir -p $(WINDOWS_BUILDROOT)
	mkdir -p $(WINDOWS_SOURCEROOT)
	ln -sf $(PWD)/openssl $(WINDOWS_BUILDROOT)/$(OPENSSL_VERSION)
	ln -sf $(PWD)/openvpn $(WINDOWS_BUILDROOT)/$(OPENVPN_VERSION)
	cd openvpn; autoreconf -f -v
	EXTRA_OPENVPN_CONFIG="$(OPENVPN_CONFIG)" \
		EXTRA_OPENSSL_CONFIG="-static-libgcc no-shared $(OPENSSL_CONFIG)" \
		EXTRA_TARGET_LDFLAGS="-Wl,-Bstatic" \
		CHOST=x86_64-w64-mingw32 \
		CBUILD=x86_64-pc-linux-gnu \
		DO_STATIC=1 \
		IMAGEROOT="$(BUILD_DIR)" \
		./openvpn-build/generic/build
	strip openvpn/src/openvpn/openvpn.exe
	cp openvpn/src/openvpn/openvpn.exe ./windows/

libmnl:
	@echo "Building libmnl"
	cd libmnl; \
	./autogen.sh; \
	./configure --enable-static --disable-shared; \
	$(MAKE) clean; \
	$(MAKE)
	cp libmnl/src/.libs/libmnl.a linux/

libnftnl: libmnl
	@echo "Building libnftnl"
	cd libnftnl; \
	./autogen.sh; \
	LIBMNL_LIBS="-L$(PWD)/libmnl/src/.libs -lmnl" \
		LIBMNL_CFLAGS="-I$(PWD)/libmnl/include" \
		CFLAGS="-g -O2 -mcmodel=large" \
		./configure --enable-static --disable-shared; \
	$(MAKE) clean; \
	$(MAKE)
	cp libnftnl/src/.libs/libnftnl.a linux/
